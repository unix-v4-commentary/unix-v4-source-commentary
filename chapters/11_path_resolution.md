# Chapter 11: Path Resolution (namei)

## Overview

Every file operation begins with a pathname: `/etc/passwd`, `../foo`, `file.txt`. The `namei()` function translates these human-readable paths into inode pointers the kernel can work with. It handles absolute and relative paths, traverses directories, checks permissions, crosses mount points, and supports three modes: lookup, create, and delete.

This single function is the gateway to the entire file system.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/ken/nami.c` | `namei()`, `schar()`, `uchar()` |
| `usr/sys/user.h` | Path resolution state in user structure |

## Prerequisites

- Chapter 9: Inodes and Superblock (`iget`/`iput`)
- Chapter 10: File I/O (directory reading)

## Directory Structure

A directory is simply a file containing 16-byte entries:

```c
struct {
    int  u_ino;         /* Inode number (2 bytes) */
    char u_name[DIRSIZ]; /* Filename (14 bytes) */
};
```

With `DIRSIZ=14`, filenames are limited to 14 characters. An inode number of 0 indicates an empty (deleted) slot.

Example directory contents:
```
Offset  Inode  Name
0       1      .
16      1      ..
32      47     passwd
48      0      (empty)
64      52     group
...
```

## The User Structure Fields

`namei()` uses several fields in the user structure:

```c
/* user.h */
struct user {
    ...
    int   *u_cdir;              /* Current directory inode */
    char  u_dbuf[DIRSIZ];       /* Component being searched */
    char  *u_dirp;              /* Pointer into pathname */
    struct {
        int  u_ino;             /* Found entry's inode number */
        char u_name[DIRSIZ];    /* Found entry's name */
    } u_dent;
    int   *u_pdir;              /* Parent directory (for create) */
    ...
};
```

| Field | Purpose |
|-------|---------|
| `u_cdir` | Current working directory inode |
| `u_dbuf` | Current path component being matched |
| `u_dirp` | Pointer to next character in pathname |
| `u_dent` | Last directory entry read |
| `u_pdir` | Parent directory (set during create mode) |

## namei() Function Signature

```c
namei(func, flag)
int (*func)();
int flag;
```

**func**: Function to get the next pathname character
- `&uchar` — pathname is in user space
- `&schar` — pathname is in kernel space

**flag**: Operation mode
- `0` — Lookup: find existing file
- `1` — Create: find parent directory for new file
- `2` — Delete: find file to be deleted

**Returns**: Locked inode pointer, or NULL on error

## namei() Walkthrough

### Initialization

```c
{
    register struct inode *dp;
    register c;
    register char *cp;
    int eo, *bp;

    /*
     * start from indicated directory
     */
    dp = u.u_cdir;              /* Start at current directory */
    if((c=(*func)()) == '/')
        dp = rootdir;           /* Absolute path: start at root */
    iget(dp->i_dev, dp->i_number);
    while(c == '/')
        c = (*func)();          /* Skip leading/consecutive slashes */
```

The starting point depends on the first character:
- `/etc/passwd` → start at root
- `foo/bar` → start at current directory
- `///foo` → start at root (extra slashes ignored)

`iget()` is called to get a locked, reference-counted copy of the starting directory.

### Main Loop (cloop)

```c
cloop:
    /*
     * here dp contains pointer to last component matched.
     */

    if(u.u_error)
        goto out;
    if(c == '\0')
        return(dp);             /* Path exhausted: success! */
```

If we've consumed the entire path with no errors, return the current inode.

```c
    /*
     * if there is another component,
     * dp must be a directory and must have x permission
     */

    if((dp->i_mode&IFMT) != IFDIR) {
        u.u_error = ENOTDIR;
        goto out;
    }

    if(access(dp, IEXEC))
        goto out;
```

To traverse into a directory, it must:
1. Actually be a directory (not a regular file)
2. Have execute permission (the "search" permission for directories)

### Parsing the Component

```c
    /*
     * gather up name into users' dir buffer
     */

    cp = &u.u_dbuf[0];
    while(c!='/' && c!='\0' && u.u_error==0) {
        if(cp < &u.u_dbuf[DIRSIZ])
            *cp++ = c;
        c = (*func)();
    }
    while(cp < &u.u_dbuf[DIRSIZ])
        *cp++ = '\0';           /* Pad with nulls */
    while(c == '/')
        c = (*func)();          /* Skip trailing slashes */
```

Extract one path component (e.g., "etc" from "/etc/passwd") into `u_dbuf`. Components longer than 14 characters are silently truncated.

### Directory Search Setup

```c
    /*
     * search the directory
     */

    u.u_offset[1] = 0;
    u.u_offset[0] = 0;
    u.u_segflg = 1;             /* Reading to kernel space */
    eo = 0;                     /* First empty slot offset */
    u.u_count = ldiv(dp->i_size1, DIRSIZ+2);  /* Entry count */
    bp = NULL;
```

Prepare to scan the directory from the beginning. `u_count` is the number of 16-byte entries.

### Directory Search Loop (eloop)

```c
eloop:
    if(u.u_count == 0) {
        /* Searched entire directory without finding it */
        if(bp != NULL)
            brelse(bp);
        if(flag==1 && c=='\0') {
            /* Create mode: return parent for new file */
            if(access(dp, IWRITE))
                goto out;
            u.u_pdir = dp;
            if(eo)
                u.u_offset[1] = eo-DIRSIZ-2;  /* Use empty slot */
            else
                dp->i_flag =| IUPD;           /* Append to directory */
            return(NULL);
        }
        u.u_error = ENOENT;     /* File not found */
        goto out;
    }
```

When the search exhausts all entries:
- **Create mode** (`flag==1`) and at final component: Success! Return NULL with `u_pdir` pointing to parent directory. The offset indicates where to write the new entry.
- **Otherwise**: File not found, return ENOENT.

```c
    if((u.u_offset[1]&0777) == 0) {
        /* Need to read next directory block */
        if(bp != NULL)
            brelse(bp);
        bp = bread(dp->i_dev,
            bmap(dp, ldiv(u.u_offset[1], 512)));
    }
```

Read directory blocks as needed. Each 512-byte block holds 32 entries.

```c
    bcopy(bp->b_addr+(u.u_offset[1]&0777), &u.u_dent, (DIRSIZ+2)/2);
    u.u_offset[1] =+ DIRSIZ+2;
    u.u_count--;
```

Copy the current 16-byte entry into `u_dent` and advance.

```c
    if(u.u_dent.u_ino == 0) {
        /* Empty slot - remember for create */
        if(eo == 0)
            eo = u.u_offset[1];
        goto eloop;
    }
```

Empty slots (inode 0) are skipped but remembered—`eo` records the first empty slot for potential reuse during create.

```c
    for(cp = &u.u_dbuf[0]; cp < &u.u_dbuf[DIRSIZ]; cp++)
        if(*cp != cp[u.u_dent.u_name - u.u_dbuf])
            goto eloop;
```

Compare the entry's name with the component we're looking for. This is a character-by-character comparison.

### Match Found

```c
    if(bp != NULL)
        brelse(bp);
    if(flag==2 && c=='\0') {
        /* Delete mode: return current directory with entry info */
        if(access(dp, IWRITE))
            goto out;
        return(dp);
    }
```

For **delete mode** (`flag==2`) at the final component: return the *parent* directory with `u_dent` containing the entry to delete.

```c
    bp = dp->i_dev;
    iput(dp);
    dp = iget(bp, u.u_dent.u_ino);
    if(dp == NULL)
        return(NULL);
    goto cloop;
```

For lookup or intermediate components: release the current directory, get the matched inode, and continue parsing.

### Cleanup on Error

```c
out:
    iput(dp);
    return(NULL);
}
```

On any error, release the current inode and return NULL.

## Character Fetch Functions

### uchar() — From User Space

```c
uchar()
{
    register c;

    c = fubyte(u.u_dirp++);
    if(c == -1)
        u.u_error = EFAULT;
    return(c);
}
```

Fetches the next character from a user-space pathname using `fubyte()` (fetch user byte). Returns -1 on fault.

### schar() — From Kernel Space

```c
schar()
{
    return(*u.u_dirp++ & 0377);
}
```

Fetches directly from kernel memory. Used when the pathname is already in kernel space (e.g., during `exec()` of `/etc/init`).

## Usage Examples

### open() — Lookup Mode

```c
open()
{
    u.u_dirp = u.u_arg[0];      /* Pathname from user */
    ip = namei(&uchar, 0);      /* flag=0: lookup */
    if(ip == NULL)
        return;                 /* ENOENT already set */
    /* ip is the file's inode */
}
```

### creat() — Create Mode

```c
creat()
{
    u.u_dirp = u.u_arg[0];
    ip = namei(&uchar, 1);      /* flag=1: create */
    if(ip != NULL) {
        /* File exists - truncate it */
        ...
    } else if(u.u_error == 0) {
        /* File doesn't exist - create it */
        /* u.u_pdir = parent directory */
        /* u.u_offset = where to write entry */
        ip = maknode(mode);
    }
}
```

### unlink() — Delete Mode

```c
unlink()
{
    u.u_dirp = u.u_arg[0];
    ip = namei(&uchar, 2);      /* flag=2: delete */
    if(ip == NULL)
        return;
    /* ip = parent directory */
    /* u.u_dent = entry to delete */
    u.u_dent.u_ino = 0;         /* Clear the entry */
    writei(ip);                 /* Write back */
    ...
}
```

## Path Resolution Examples

### Absolute Path: `/etc/passwd`

```
namei(&uchar, 0) with u.u_dirp = "/etc/passwd"

1. c='/', dp = rootdir, iget root
2. c='e', parse "etc" into u.u_dbuf
3. Search root directory:
   - Entry ".": skip
   - Entry "..": skip
   - Entry "etc": match! inode=5
4. iput(root), dp = iget(5)
5. c='p', parse "passwd" into u.u_dbuf
6. Search /etc directory:
   - Entry ".": skip
   - Entry "..": skip
   - Entry "passwd": match! inode=47
7. c='\0', return inode 47
```

### Relative Path: `../foo`

```
namei(&uchar, 0) with u.u_dirp = "../foo"

1. c='.', dp = u.u_cdir (say inode 10), iget(10)
2. parse ".." into u.u_dbuf
3. Search current directory:
   - Entry ".": skip
   - Entry "..": match! inode=3
4. iput(10), dp = iget(3)
5. parse "foo" into u.u_dbuf
6. Search parent directory:
   - Entry "foo": match! inode=25
7. c='\0', return inode 25
```

### Create: `/tmp/newfile`

```
namei(&uchar, 1) with u.u_dirp = "/tmp/newfile"

1. c='/', dp = rootdir
2. parse "tmp", search root, find inode 4
3. dp = iget(4)
4. parse "newfile", search /tmp:
   - Not found!
5. flag==1 and c=='\0':
   - Check write permission on /tmp
   - u.u_pdir = dp (inode 4)
   - u.u_offset = position for new entry
   - return NULL (success!)
```

## Mount Point Traversal

Note that mount point handling actually happens in `iget()` (Chapter 9), not `namei()`. When `iget()` finds an inode marked `IMOUNT`, it automatically redirects to the mounted filesystem's root.

```
/usr/include/stdio.h
  where /usr is a mount point

namei traverses:
1. / (root)
2. usr → iget() sees IMOUNT, redirects to mounted fs root
3. include
4. stdio.h
```

## Error Handling

| Error | Condition |
|-------|-----------|
| `ENOENT` | Component not found (lookup/delete mode) |
| `ENOTDIR` | Intermediate component is not a directory |
| `EACCES` | No search (x) permission on directory |
| `EFAULT` | Bad user-space pathname pointer |

## The "." and ".." Entries

Every directory contains two special entries:

```
.   → inode of the directory itself
..  → inode of the parent directory
```

For the root directory, `..` points to itself. These entries are created by `mkdir` and are traversed by `namei()` just like any other entries.

## Summary

- `namei()` translates pathnames to inodes
- Three modes: lookup (0), create (1), delete (2)
- Parses components left-to-right, searching each directory
- Checks execute permission at each directory
- Uses `u_dbuf` for current component, `u_dent` for matched entry
- Returns locked inode (or NULL with `u_pdir` set for create)

## Key Design Points

1. **Single function**: One function handles all path resolution needs through the flag parameter.

2. **No recursion**: Iterative loop avoids stack overflow on deep paths.

3. **Flexible input**: Function pointer allows user-space or kernel-space pathnames.

4. **Empty slot reuse**: Tracks first empty slot during search for efficient create.

5. **Atomic operation**: Inode locking prevents races during create/delete.

## Experiments

1. **Trace path resolution**: Add printf showing each component and matched inode.

2. **Deep paths**: Create deeply nested directories and observe behavior.

3. **Permission denied**: Remove execute permission from a directory and try to traverse it.

4. **Long names**: Try creating files with names longer than 14 characters.

## Further Reading

- Chapter 9: Inodes and Superblock — `iget()` and mount point handling
- Chapter 10: File I/O — How directories are read
- System calls that use `namei()`: `open`, `creat`, `stat`, `unlink`, `link`, `chdir`, `chmod`, `chown`

---

**Next: Chapter 12 — The Buffer Cache**
