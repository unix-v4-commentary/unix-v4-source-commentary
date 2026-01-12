# Chapter 9: Inodes and the Superblock

## Overview

The UNIX file system is built on two fundamental abstractions: the **inode** (index node) and the **superblock**. Every file—whether a regular file, directory, or device—is represented by an inode that stores its metadata and block addresses. The superblock contains critical file system parameters and maintains caches of free blocks and free inodes for fast allocation.

This chapter examines how UNIX v4 organizes data on disk and manages the in-memory inode cache—the foundation upon which all file operations are built.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/inode.h` | In-memory inode structure and flags |
| `usr/sys/filsys.h` | Superblock structure |
| `usr/sys/ken/iget.c` | Inode cache operations |
| `usr/sys/ken/alloc.c` | Block and inode allocation |

## Prerequisites

- Chapter 2: PDP-11 Architecture (memory layout)
- Chapter 4: Boot Sequence (`iinit()` called during startup)
- Chapter 12: Buffer Cache (understanding `bread`/`bwrite`)

## Disk Layout

A UNIX v4 file system has this structure:

```
Block 0     Boot block (bootstrap code)
Block 1     Superblock (file system metadata)
Block 2     ┐
  ...       │ Inode area (on-disk inodes)
Block N     ┘
Block N+1   ┐
  ...       │ Data blocks
Block M     ┘
```

Each block is 512 bytes. The number of inode blocks depends on the file system size—the superblock's `s_isize` field records this.

### On-Disk Inode Format

Each on-disk inode is 32 bytes:

```
Offset  Size  Field
0       2     i_mode    (type/permissions)
2       1     i_nlink   (link count)
3       1     i_uid     (owner)
4       1     i_gid     (group)
5       1     i_size0   (size high byte)
6       2     i_size1   (size low bytes)
8       16    i_addr[8] (block addresses)
24      4     i_atime   (access time)
28      4     i_mtime   (modification time)
```

With 32 bytes per inode, each 512-byte block holds 16 inodes. Inode numbering starts at 1 (inode 0 is unused); inode 1 is the root directory (`ROOTINO`).

## The In-Memory Inode

When a file is opened, its inode is read into memory and cached:

```c
/* inode.h */
struct inode {
    char  i_flag;       /* Flags (ILOCK, IUPD, etc.) */
    char  i_count;      /* Reference count */
    int   i_dev;        /* Device number */
    int   i_number;     /* Inode number on device */
    int   i_mode;       /* Type and permissions */
    char  i_nlink;      /* Link count */
    char  i_uid;        /* Owner user ID */
    char  i_gid;        /* Owner group ID */
    char  i_size0;      /* Size (high byte) */
    char  *i_size1;     /* Size (low 16 bits) */
    int   i_addr[8];    /* Block addresses */
    int   i_lastr;      /* Last block read (for read-ahead) */
} inode[NINODE];
```

The in-memory inode has additional fields not stored on disk:

| Field | Purpose |
|-------|---------|
| `i_flag` | Lock state, update pending, mount point |
| `i_count` | Number of references to this cached inode |
| `i_dev` | Which device this inode is from |
| `i_number` | Which inode number on that device |
| `i_lastr` | Enables read-ahead optimization |

### Inode Flags

```c
#define ILOCK   01      /* Inode is locked */
#define IUPD    02      /* Inode modified, needs write */
#define IACC    04      /* Access time changed */
#define IMOUNT  010     /* Mount point */
#define IWANT   020     /* Process waiting for lock */
#define ITEXT   040     /* Text segment (shared executable) */
```

### Mode Bits

The `i_mode` field encodes file type and permissions:

```c
#define IALLOC  0100000   /* Inode is allocated */
#define IFMT    060000    /* Type mask */
#define IFDIR   040000    /* Directory */
#define IFCHR   020000    /* Character device */
#define IFBLK   060000    /* Block device */
#define ILARG   010000    /* Large file (indirect blocks) */
#define ISUID   04000     /* Set-user-ID */
#define ISGID   02000     /* Set-group-ID */
#define IREAD   0400      /* Owner read */
#define IWRITE  0200      /* Owner write */
#define IEXEC   0100      /* Owner execute */
```

File types encoded in `IFMT`:
- `000000` — Regular file
- `040000` — Directory
- `020000` — Character special
- `060000` — Block special

## The Superblock

The superblock lives in block 1 and describes the file system:

```c
/* filsys.h */
struct filsys {
    int   s_isize;      /* Size of inode area in blocks */
    int   s_fsize;      /* Total size in blocks */
    int   s_nfree;      /* Number of free blocks in cache */
    int   s_free[100];  /* Free block cache */
    int   s_ninode;     /* Number of free inodes in cache */
    int   s_inode[100]; /* Free inode cache */
    char  s_flock;      /* Lock during free list manipulation */
    char  s_ilock;      /* Lock during inode list manipulation */
    char  s_fmod;       /* Superblock modified flag */
    char  s_ronly;      /* Read-only flag */
    int   s_time[2];    /* Last modification time */
};
```

The superblock caches up to 100 free block numbers and 100 free inode numbers in memory. This dramatically speeds allocation—most allocations don't require disk I/O.

## iinit() — File System Initialization

Called once during boot to initialize the root file system:

```c
/* alloc.c */
iinit()
{
    register *cp, *bp;

    bp = bread(rootdev, 1);         /* Read superblock */
    cp = getblk(NODEV);             /* Get buffer for in-memory copy */
    if(u.u_error)
        panic("iinit");
    bcopy(bp->b_addr, cp->b_addr, 256);  /* Copy superblock */
    brelse(bp);
    mount[0].m_bufp = cp;           /* Save in mount table */
    mount[0].m_dev = rootdev;
    cp = cp->b_addr;
    cp->s_flock = 0;                /* Clear locks */
    cp->s_ilock = 0;
    cp->s_ronly = 0;
    time[0] = cp->s_time[0];        /* Initialize system time */
    time[1] = cp->s_time[1];
}
```

Key points:
1. The superblock is read from disk block 1
2. It's copied into a dedicated buffer that stays in memory
3. The mount table entry records this buffer
4. System time is initialized from the superblock

## iget() — Getting an Inode

`iget()` retrieves an inode, either from cache or disk:

```c
/* iget.c */
iget(dev, ino)
int dev;
int ino;
{
    register struct inode *p;
    register *ip2;
    int *ip1;
    register struct mount *ip;

loop:
    ip = NULL;
    for(p = &inode[0]; p < &inode[NINODE]; p++) {
        if(dev==p->i_dev && ino==p->i_number) {
            /* Found in cache */
            if((p->i_flag&ILOCK) != 0) {
                p->i_flag =| IWANT;
                sleep(p, PINOD);
                goto loop;          /* Retry after wakeup */
            }
```

The first loop searches the inode cache. If found but locked, the process sleeps until the lock is released.

```c
            if((p->i_flag&IMOUNT) != 0) {
                /* This is a mount point - cross to mounted fs */
                for(ip = &mount[0]; ip < &mount[NMOUNT]; ip++)
                if(ip->m_inodp == p) {
                    dev = ip->m_dev;
                    ino = ROOTINO;
                    goto loop;
                }
                panic("no imt");
            }
            p->i_count++;
            p->i_flag =| ILOCK;
            return(p);
        }
        if(ip==NULL && p->i_count==0)
            ip = p;                 /* Remember free slot */
    }
```

Mount point handling: if the inode is a mount point, `iget()` transparently crosses to the mounted file system's root.

```c
    if((p=ip) == NULL)
        panic("no inodes");
    if (p>maxip)
        maxip = p;
    p->i_dev = dev;
    p->i_number = ino;
    p->i_flag = ILOCK;
    p->i_count++;
    p->i_lastr = -1;
```

If not in cache, use the free slot found during the search. Initialize the in-memory fields.

```c
    ip = bread(dev, ldiv(ino+31,16));
    ip1 = ip->b_addr + 32*lrem(ino+31, 16);
    ip2 = &p->i_mode;
    while(ip2 < &p->i_addr[8])
        *ip2++ = *ip1++;
    brelse(ip);
    return(p);
}
```

The disk block containing the inode is calculated:
- `ldiv(ino+31, 16)` gives the block number (16 inodes per block, offset by 2 for boot+super, so +31 adjusts for 1-based inode numbers)
- `32*lrem(ino+31, 16)` gives the byte offset within the block

The on-disk inode (32 bytes from `i_mode` through `i_addr[7]`) is copied into the in-memory structure.

## iput() — Releasing an Inode

`iput()` decrements the reference count and handles cleanup:

```c
/* iget.c */
iput(p)
struct inode *p;
{
    register *rp;

    rp = p;
    if(rp->i_count == 1) {
        rp->i_flag =| ILOCK;
        if(rp->i_nlink <= 0) {
            itrunc(rp);             /* Free all data blocks */
            rp->i_mode = 0;         /* Mark as unallocated */
            ifree(rp->i_dev, rp->i_number);
        }
        iupdat(rp);                 /* Write changes to disk */
        prele(rp);
        rp->i_flag = 0;
        rp->i_number = 0;
    }
    rp->i_count--;
    prele(rp);
}
```

When the last reference is released (`i_count` goes to 0):
1. If link count is zero, the file is deleted—`itrunc()` frees data blocks, `ifree()` frees the inode
2. `iupdat()` writes any pending changes to disk
3. The inode slot is cleared for reuse

## iupdat() — Writing Inode to Disk

```c
/* iget.c */
iupdat(p)
int *p;
{
    register *ip1, *ip2, *rp;
    int *bp, i;

    rp = p;
    if((rp->i_flag&(IUPD|IACC)) != 0) {
        if(getfs(rp->i_dev)->s_ronly)
            return;                 /* Read-only filesystem */
        i = rp->i_number+31;
        bp = bread(rp->i_dev, ldiv(i,16));
        ip1 = bp->b_addr + 32*lrem(i, 16);
        ip2 = &rp->i_mode;
        while(ip2 < &rp->i_addr[8])
            *ip1++ = *ip2++;        /* Copy inode to buffer */
        if(rp->i_flag&IACC) {
            *ip1++ = time[0];       /* Update access time */
            *ip1++ = time[1];
        } else
            ip1 =+ 2;
        if(rp->i_flag&IUPD) {
            *ip1++ = time[0];       /* Update modification time */
            *ip1++ = time[1];
        }
        bwrite(bp);                 /* Write synchronously */
    }
}
```

Only writes if `IUPD` or `IACC` flags are set. The times are written after the main inode data.

## itrunc() — Truncating a File

When a file is deleted or truncated, its blocks must be freed:

```c
/* iget.c */
itrunc(ip)
int *ip;
{
    register *rp, *bp, *cp;

    rp = ip;
    if((rp->i_mode&(IFCHR&IFBLK)) != 0)
        return;                     /* Devices have no blocks */
    for(ip = &rp->i_addr[0]; ip < &rp->i_addr[8]; ip++)
    if(*ip) {
        if((rp->i_mode&ILARG) != 0) {
            /* Large file: this is an indirect block */
            bp = bread(rp->i_dev, *ip);
            for(cp = bp->b_addr; cp < bp->b_addr+512; cp++)
                if(*cp)
                    free(rp->i_dev, *cp);
            brelse(bp);
        }
        free(rp->i_dev, *ip);
        *ip = 0;
    }
    rp->i_mode =& ~ILARG;
    rp->i_size0 = 0;
    rp->i_size1 = 0;
    rp->i_flag =| IUPD;
}
```

For small files (ILARG not set), `i_addr[0-7]` point directly to data blocks.

For large files (ILARG set), `i_addr[0-7]` point to indirect blocks, each containing 256 block numbers. The indirect blocks are read, their contents freed, then the indirect blocks themselves are freed.

## Block Allocation

### alloc() — Allocate a Block

```c
/* alloc.c */
alloc(dev)
{
    int bno;
    register *bp, *ip, *fp;

    fp = getfs(dev);
    while(fp->s_flock)
        sleep(&fp->s_flock, PINOD);
    bno = fp->s_free[--fp->s_nfree];
    if(bno == 0) {
        fp->s_nfree++;
        printf("No space on dev %d\n", dev);
        u.u_error = ENOSPC;
        return(NULL);
    }
```

The superblock caches free blocks in `s_free[]`. Allocation pops from this array.

```c
    if(fp->s_nfree <= 0) {
        /* Cache empty - reload from linked list */
        fp->s_flock++;
        bp = bread(dev, bno);
        ip = bp->b_addr;
        fp->s_nfree = *ip++;
        bcopy(ip, fp->s_free, 100);
        brelse(bp);
        fp->s_flock = 0;
        wakeup(&fp->s_flock);
    }
    bp = getblk(dev, bno);
    clrbuf(bp);
    fp->s_fmod = 1;
    return(bp);
}
```

When the cache empties, the block just "allocated" is actually a link block—it contains the next batch of 100 free block numbers. This creates a linked list of free block batches across the disk.

### free() — Free a Block

```c
/* alloc.c */
free(dev, bno)
{
    register *fp, *bp, *ip;

    fp = getfs(dev);
    fp->s_fmod = 1;
    while(fp->s_flock)
        sleep(&fp->s_flock, PINOD);
    if(fp->s_nfree >= 100) {
        /* Cache full - flush to disk */
        fp->s_flock++;
        bp = getblk(dev, bno);
        ip = bp->b_addr;
        *ip++ = fp->s_nfree;
        bcopy(fp->s_free, ip, 100);
        fp->s_nfree = 0;
        bwrite(bp);
        fp->s_flock = 0;
        wakeup(&fp->s_flock);
    }
    fp->s_free[fp->s_nfree++] = bno;
    fp->s_fmod = 1;
}
```

The reverse of `alloc()`: when the cache fills, the current 100 free blocks are written to the block being freed, creating a new link in the chain.

### The Free Block List

```
Superblock                Link Block 1              Link Block 2
+------------------+     +------------------+      +------------------+
| s_nfree = 47     |     | count = 100      |      | count = 100      |
| s_free[0..46]    |     | blocks[0..99] ───┼─────►| blocks[0..99] ───┼───► ...
+------------------+     +------------------+      +------------------+
        │
        └── s_free[46] points to Link Block 1
```

This design means:
- Most allocations require no disk I/O (just decrement s_nfree)
- The free list is rebuilt in batches, amortizing disk access

## Inode Allocation

### ialloc() — Allocate an Inode

```c
/* alloc.c */
ialloc(dev)
{
    register *fp, *bp, *ip;
    int i, j, k, ino;

    fp = getfs(dev);
    while(fp->s_ilock)
        sleep(&fp->s_ilock, PINOD);
loop:
    if(fp->s_ninode > 0) {
        /* Use cached free inode number */
        ino = fp->s_inode[--fp->s_ninode];
        ip = iget(dev, ino);
        if(ip->i_mode == 0) {
            for(bp = &ip->i_mode; bp < &ip->i_addr[8];)
                *bp++ = 0;
            fp->s_fmod = 1;
            return(ip);
        }
        /* Inode was busy - try next */
        printf("busy i\n");
        iput(ip);
        goto loop;
    }
```

Like blocks, free inode numbers are cached in the superblock. If available, pop one and verify it's actually free.

```c
    /* Cache empty - scan inode area */
    fp->s_ilock++;
    ino = 0;
    for(i=0; i<fp->s_isize; i++) {
        bp = bread(dev, i+2);       /* Inode blocks start at 2 */
        ip = bp->b_addr;
        for(j=0; j<256; j=+16) {    /* 16 inodes per block, 32 bytes each */
            ino++;
            if(ip[j] != 0)          /* Check i_mode - 0 means free */
                continue;
            /* Skip if currently in use in memory */
            for(k=0; k<NINODE; k++)
            if(dev==inode[k].i_dev && ino==inode[k].i_number)
                goto cont;
            fp->s_inode[fp->s_ninode++] = ino;
            if(fp->s_ninode >= 100)
                break;
        cont:;
        }
        brelse(bp);
        if(fp->s_ninode >= 100)
            break;
    }
    if(fp->s_ninode <= 0)
        panic("out of inodes");
    fp->s_ilock = 0;
    wakeup(&fp->s_ilock);
    goto loop;
}
```

When the cache empties, the entire inode area is scanned to refill it. This is expensive but rare—the cache holds 100 inodes.

### ifree() — Free an Inode

```c
/* alloc.c */
ifree(dev, ino)
{
    register *fp;

    fp = getfs(dev);
    if(fp->s_ilock)
        return;                     /* Someone scanning - skip */
    if(fp->s_ninode >= 100)
        return;                     /* Cache full - will be found by scan */
    fp->s_inode[fp->s_ninode++] = ino;
    fp->s_fmod = 1;
}
```

Unlike block freeing, `ifree()` is simple: just add to cache if there's room. If the cache is full, the freed inode will be found on the next `ialloc()` scan.

## getfs() — Finding a File System

```c
/* alloc.c */
getfs(dev)
{
    register struct mount *p;

    for(p = &mount[0]; p < &mount[NMOUNT]; p++)
        if(p->m_bufp != NULL && p->m_dev == dev) {
            p = p->m_bufp->b_addr;
            return(p);
        }
    panic("no fs");
}
```

Given a device number, return a pointer to its in-memory superblock. The mount table maps devices to superblock buffers.

## update() — Sync to Disk

`update()` flushes all modified data to disk:

```c
/* alloc.c */
update()
{
    register struct inode *ip;
    register struct mount *mp;
    register *bp;

    if(updlock)
        return;
    updlock++;

    /* Write all modified superblocks */
    for(mp = &mount[0]; mp < &mount[NMOUNT]; mp++)
        if(mp->m_bufp != NULL) {
            ip = mp->m_bufp->b_addr;
            if(ip->s_fmod==0 || ip->s_ilock!=0 ||
               ip->s_flock!=0 || ip->s_ronly!=0)
                continue;
            bp = getblk(mp->m_dev, 1);
            ip->s_fmod = 0;
            ip->s_time[0] = time[0];
            ip->s_time[1] = time[1];
            bcopy(ip, bp->b_addr, 256);
            bwrite(bp);
        }
```

First, all modified superblocks are written to their block 1.

```c
    /* Write all modified inodes */
    for(ip = &inode[0]; ip < &inode[NINODE]; ip++)
        if((ip->i_flag&ILOCK) == 0) {
            ip->i_flag =| ILOCK;
            iupdat(ip);
            prele(ip);
        }
    updlock = 0;
    bflush(NODEV);
}
```

Then all unlocked inodes with pending changes are written. Finally, `bflush()` writes all dirty buffers. This is called by `sync(2)` and periodically by the update daemon.

## maknode() — Creating a New File

```c
/* iget.c */
maknode(mode)
{
    register *ip;

    ip = ialloc(u.u_pdir->i_dev);
    ip->i_flag =| IACC|IUPD;
    ip->i_mode = mode|IALLOC;
    ip->i_nlink = 1;
    ip->i_uid = u.u_uid;
    ip->i_gid = u.u_gid;
    wdir(ip);
    return(ip);
}
```

Allocates a new inode and creates a directory entry for it:

1. `ialloc()` gets a free inode
2. Initialize mode, link count, owner
3. `wdir()` writes the directory entry

## wdir() — Writing a Directory Entry

```c
/* iget.c */
wdir(ip)
int *ip;
{
    register char *cp1, *cp2;

    u.u_dent.u_ino = ip->i_number;
    cp1 = &u.u_dent.u_name[0];
    for(cp2 = &u.u_dbuf[0]; cp2 < &u.u_dbuf[DIRSIZ];)
        *cp1++ = *cp2++;
    u.u_count = DIRSIZ+2;           /* 14 bytes name + 2 bytes ino */
    u.u_segflg = 1;
    u.u_base = &u.u_dent;
    writei(u.u_pdir);
    iput(u.u_pdir);
}
```

Directory entries are 16 bytes: 2-byte inode number + 14-byte name. The entry is written at the position found by `namei()` (stored in `u.u_offset`).

## How It All Fits Together

### Opening a File

```
open("/etc/passwd", 0)
        │
        ▼
    namei() ──────────────► iget(rootdev, 1)    [root inode]
        │                         │
        │                         ▼
        │                   lookup "etc"
        │                         │
        │                         ▼
        │                   iget(rootdev, 5)    [/etc inode]
        │                         │
        │                         ▼
        │                   lookup "passwd"
        │                         │
        ▼                         ▼
    return ◄──────────────── iget(rootdev, 42)  [/etc/passwd inode]
```

### Creating a File

```
creat("/tmp/foo", 0644)
        │
        ▼
    namei() ──────────► returns NULL (not found)
        │                u.u_pdir = /tmp inode
        │
        ▼
    maknode(0644)
        │
        ├──► ialloc() ──► get free inode #87
        │
        └──► wdir() ──► write entry to /tmp directory
                         inode=87, name="foo"
```

### Deleting a File

```
unlink("/tmp/foo")
        │
        ▼
    namei() ──────────► returns inode #87
        │                u.u_pdir = /tmp inode
        │
        ▼
    ip->i_nlink--       [now 0]
        │
        ▼
    clear directory entry
        │
        ▼
    iput(ip)
        │
        ├──► itrunc() ──► free all data blocks
        │
        └──► ifree() ──► return inode to free list
```

## Summary

- **Inodes** store all file metadata except the name
- **Superblock** holds file system parameters and free lists
- **iget/iput** manage the in-memory inode cache with reference counting
- **alloc/free** manage disk blocks using a linked-list cache
- **ialloc/ifree** manage inodes using a simple array cache
- **update** syncs everything to disk

The elegance of this design:
1. Most operations hit the in-memory cache
2. Reference counting prevents premature deallocation
3. The free block list amortizes disk I/O
4. Lock flags prevent concurrent modification

## Key Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `NINODE` | 100 | In-memory inode cache size |
| `ROOTINO` | 1 | Root directory inode number |
| `DIRSIZ` | 14 | Maximum filename length |

## Experiments

1. **Trace inode allocation**: Add printf to `ialloc()` to see when the cache is refilled.

2. **Count cache hits**: Track how often `iget()` finds inodes in cache vs. reading from disk.

3. **Free list structure**: Examine the free block list by reading link blocks with `od`.

4. **Fill the filesystem**: Create files until "No space" appears, then delete some and observe `alloc()` behavior.

## Further Reading

- Chapter 10: File I/O — How data flows through inodes
- Chapter 11: Path Resolution — How `namei()` traverses directories
- Chapter 12: Buffer Cache — The `bread`/`bwrite` interface used here

---

**Next: Chapter 10 — File I/O**
