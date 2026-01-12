# Chapter 10: File I/O

## Overview

When a user program calls `read()` or `write()`, the request passes through three layers of abstraction: **file descriptors** (per-process), the **open file table** (system-wide), and **inodes** (representing files). This chapter traces the data path from user space through these layers, examining how UNIX v4 translates file positions into disk blocks and moves data between user memory and the buffer cache.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/file.h` | Open file table structure |
| `usr/sys/ken/fio.c` | File descriptor operations |
| `usr/sys/ken/rdwri.c` | `readi()`, `writei()`, `iomove()` |
| `usr/sys/ken/subr.c` | `bmap()` block mapping |

## Prerequisites

- Chapter 9: Inodes and Superblock (inode structure, `i_addr[]`)
- Chapter 12: Buffer Cache (`bread`, `bwrite`, `brelse`)

## The Three-Level File Abstraction

```
User Process                 Kernel
+------------------+        +------------------------+
| fd 0 ──────────────────►  | file[17]               |
| fd 1 ──────────────────►  |   f_inode ─────────────┼───► inode[5]
| fd 2 ──────────────────►  |   f_offset             |        │
| ...              |        +------------------------+        ▼
| u.u_ofile[15]    |        | file[23]               |    disk blocks
+------------------+        |   f_inode ─────────────┼───► inode[12]
                            |   f_offset             |
                            +------------------------+
```

**File descriptors** (`u.u_ofile[]`): Per-process array of pointers to open file entries. Small integers (0, 1, 2...) that user programs use.

**Open file table** (`file[]`): System-wide array of open file structures. Contains the current file offset and a pointer to the inode. Multiple descriptors can point to the same file entry (after `dup()` or `fork()`).

**Inodes** (`inode[]`): In-memory cache of file metadata. Contains block addresses. Multiple file entries can point to the same inode (multiple opens of the same file).

## The File Structure

```c
/* file.h */
struct file {
    char  f_flag;       /* FREAD, FWRITE, FPIPE */
    char  f_count;      /* Reference count */
    int   f_inode;      /* Pointer to inode */
    char  *f_offset[2]; /* Current position (32-bit) */
} file[NFILE];

#define FREAD   01      /* Open for reading */
#define FWRITE  02      /* Open for writing */
#define FPIPE   04      /* This is a pipe */
```

The offset is 32 bits (two 16-bit words) to support files larger than 64KB. With `NFILE=100`, the system supports 100 simultaneous open files across all processes.

## File Descriptor Operations

### getf() — Validate File Descriptor

```c
/* fio.c */
getf(f)
{
    register *fp, rf;

    rf = f;
    if(rf<0 || rf>=NOFILE)
        goto bad;
    fp = u.u_ofile[rf];
    if(fp == NULL) {
    bad:
        u.u_error = EBADF;
        fp = NULL;
    }
    return(fp);
}
```

Converts a file descriptor (small integer) to a file pointer. Returns NULL and sets `EBADF` if invalid.

### ufalloc() — Find Free Descriptor

```c
/* fio.c */
ufalloc()
{
    register i;

    for (i=0; i<NOFILE; i++)
        if (u.u_ofile[i] == NULL) {
            u.u_ar0[R0] = i;        /* Return fd in r0 */
            return(i);
        }
    u.u_error = EMFILE;             /* Too many open files */
    return(-1);
}
```

Finds the lowest available file descriptor. Places the result in both the return value and `r0` (for system call return).

### falloc() — Allocate File Entry

```c
/* fio.c */
falloc()
{
    register struct file *fp;
    register i;

    if ((i = ufalloc()) < 0)
        return(NULL);
    for (fp = &file[0]; fp < &file[NFILE]; fp++)
        if (fp->f_count==0) {
            u.u_ofile[i] = fp;      /* Link descriptor to file */
            fp->f_count++;
            fp->f_offset[0] = 0;    /* Start at beginning */
            fp->f_offset[1] = 0;
            return(fp);
        }
    printf("no file\n");
    u.u_error = ENFILE;             /* File table full */
    return(NULL);
}
```

Allocates both a file descriptor and a file table entry, linking them together. The offset is initialized to zero.

### closef() — Close File Entry

```c
/* fio.c */
closef(fp)
int *fp;
{
    register *rfp, *ip;

    rfp = fp;
    if(rfp->f_flag&FPIPE) {
        ip = rfp->f_inode;
        ip->i_mode =& ~(IREAD|IWRITE);
        wakeup(ip+1);               /* Wake pipe readers */
        wakeup(ip+2);               /* Wake pipe writers */
    }
    if(rfp->f_count <= 1)
        closei(rfp->f_inode, rfp->f_flag&FWRITE);
    rfp->f_count--;
}
```

Decrements the reference count. When it reaches zero, the underlying inode is closed. Pipes get special handling to wake waiting processes.

### closei() — Close Inode

```c
/* fio.c */
closei(ip, rw)
int *ip;
{
    register *rip;
    register dev, maj;

    rip = ip;
    dev = rip->i_addr[0];
    maj = rip->i_addr[0].d_major;
    if(rip->i_count <= 1)
    switch(rip->i_mode&IFMT) {

    case IFCHR:
        (*cdevsw[maj].d_close)(dev, rw);
        break;

    case IFBLK:
        (*bdevsw[maj].d_close)(dev, rw);
    }
    iput(rip);
}
```

For device files, calls the device's close routine. Then releases the inode with `iput()`.

### openi() — Open Inode

```c
/* fio.c */
openi(ip, rw)
int *ip;
{
    register *rip;
    register dev, maj;

    rip = ip;
    dev = rip->i_addr[0];
    maj = rip->i_addr[0].d_major;
    switch(rip->i_mode&IFMT) {

    case IFCHR:
        if(maj >= nchrdev)
            goto bad;
        (*cdevsw[maj].d_open)(dev, rw);
        break;

    case IFBLK:
        if(maj >= nblkdev) {
        bad:
            u.u_error = ENXIO;
            return;
        }
        (*bdevsw[maj].d_open)(dev, rw);
    }
}
```

For device files, calls the device's open routine. Regular files don't need any special open processing.

## Permission Checking

### access() — Check Permissions

```c
/* fio.c */
access(ip, mode)
int *ip;
{
    register *rip, m;

    rip = ip;
    m = mode;
    if(m == IWRITE && getfs(ip->i_dev)->s_ronly != 0) {
        u.u_error = EROFS;          /* Read-only filesystem */
        return(1);
    }
    if(u.u_uid == 0)
        return(0);                  /* Root can do anything */
    if(u.u_uid != rip->i_uid) {
        m =>> 3;                    /* Check group bits */
        if(u.u_gid != rip->i_gid)
            m =>> 3;                /* Check other bits */
    }
    if((rip->i_mode&m) != 0)
        return(0);                  /* Permission granted */
    u.u_error = EACCES;
    return(1);
}
```

The classic UNIX permission algorithm:
1. Check for read-only filesystem (for writes)
2. Root (uid 0) bypasses all checks
3. Check owner bits, group bits, or other bits depending on identity
4. Return 0 for success, 1 for failure

### owner() and suser()

```c
/* fio.c */
owner(ip)
int *ip;
{
    if(u.u_uid == ip->i_uid)
        return(1);
    return(suser());
}

suser()
{
    if(u.u_uid == 0)
        return(1);
    u.u_error = EPERM;
    return(0);
}
```

`owner()` checks if the user owns the file or is root. `suser()` checks for root privileges.

## Reading Files: readi()

The heart of file reading:

```c
/* rdwri.c */
readi(aip)
struct inode *aip;
{
    int *bp;
    int lbn, bn, on;
    register dn, n;
    register struct inode *ip;

    ip = aip;
    if(u.u_count == 0)
        return;
    ip->i_flag =| IACC;             /* Mark access time update */
```

Parameters are passed through the user structure:
- `u.u_base` — User buffer address
- `u.u_count` — Bytes to read
- `u.u_offset` — File position
- `u.u_segflg` — 0 for user space, 1 for kernel space

```c
    if((ip->i_mode&IFMT) == IFCHR) {
        (*cdevsw[ip->i_addr[0].d_major].d_read)(ip->i_addr[0]);
        return;
    }
```

Character devices go directly to their driver's read routine.

```c
    do {
        lbn = bn = lshift(u.u_offset, -9);  /* Logical block number */
        on = u.u_offset[1] & 0777;          /* Offset within block */
        n = min(512-on, u.u_count);         /* Bytes this iteration */
```

The 32-bit offset is converted:
- `lbn` = offset / 512 (logical block number)
- `on` = offset % 512 (byte within block)
- `n` = bytes to transfer (at most to end of block)

```c
        if((ip->i_mode&IFMT) != IFBLK) {
            dn = dpcmp(ip->i_size0, ip->i_size1,
                u.u_offset[0], u.u_offset[1]);
            if(dn <= 0)
                return;                     /* At or past EOF */
            n = min(n, dn);                 /* Don't read past EOF */
            if ((bn = bmap(ip, lbn)) == 0)
                return;                     /* Error in block mapping */
            dn = ip->i_dev;
        } else {
            dn = ip->i_addr[0];             /* Block device: use directly */
            rablock = bn+1;
        }
```

For regular files, check for EOF and call `bmap()` to translate logical to physical block. For block devices, the block number is used directly.

```c
        if (ip->i_lastr+1 == lbn)
            bp = breada(dn, bn, rablock);   /* Read-ahead */
        else
            bp = bread(dn, bn);             /* Simple read */
        ip->i_lastr = lbn;
        iomove(bp, on, n, B_READ);
        brelse(bp);
    } while(u.u_error==0 && u.u_count!=0);
}
```

**Read-ahead optimization**: If reading sequentially (current block = last block + 1), use `breada()` to start fetching the next block while processing this one. `i_lastr` tracks the last block read.

## Writing Files: writei()

```c
/* rdwri.c */
writei(aip)
struct inode *aip;
{
    int *bp;
    int n, on;
    register dn, bn;
    register struct inode *ip;

    ip = aip;
    ip->i_flag =| IACC|IUPD;        /* Mark access and update times */
    if((ip->i_mode&IFMT) == IFCHR) {
        (*cdevsw[ip->i_addr[0].d_major].d_write)(ip->i_addr[0]);
        return;
    }
    if (u.u_count == 0)
        return;
```

Similar setup to `readi()`. Character devices go to their driver.

```c
    do {
        bn = lshift(u.u_offset, -9);
        on = u.u_offset[1] & 0777;
        n = min(512-on, u.u_count);
        if((ip->i_mode&IFMT) != IFBLK) {
            if ((bn = bmap(ip, bn)) == 0)
                return;
            dn = ip->i_dev;
        } else
            dn = ip->i_addr[0];
```

Same block calculation as reading. `bmap()` will allocate new blocks if needed.

```c
        if(n == 512)
            bp = getblk(dn, bn);    /* Full block: no need to read first */
        else
            bp = bread(dn, bn);     /* Partial: read existing content */
        iomove(bp, on, n, B_WRITE);
```

**Optimization**: If writing a full 512-byte block, there's no need to read the old contents first—just get an empty buffer.

```c
        if(u.u_error != 0)
            brelse(bp);
        else if ((u.u_offset[1]&0777)==0)
            bawrite(bp);            /* Block boundary: async write */
        else
            bdwrite(bp);            /* Delayed write */
```

Write strategy:
- On error, just release the buffer
- At block boundary, use async write (`bawrite`)—starts the I/O but doesn't wait
- Mid-block, use delayed write (`bdwrite`)—buffer stays in cache until needed

```c
        if(dpcmp(ip->i_size0, ip->i_size1,
          u.u_offset[0], u.u_offset[1]) < 0 &&
          (ip->i_mode&(IFBLK&IFCHR)) == 0) {
            ip->i_size0 = u.u_offset[0];
            ip->i_size1 = u.u_offset[1];
        }
        ip->i_flag =| IUPD;
    } while(u.u_error==0 && u.u_count!=0);
}
```

If the write extended the file (offset > size), update the file size.

## Block Mapping: bmap()

`bmap()` translates a logical block number to a physical disk block:

```c
/* subr.c */
bmap(ip, bn)
struct inode *ip;
int bn;
{
    register *bp, *bap, nb;
    int *nbp, d, i;

    d = ip->i_dev;

    if (bn & ~03777) {
        u.u_error = EFBIG;          /* Block number too large */
        return(0);
    }
```

Maximum file size: 03777 (octal) = 2047 blocks = ~1MB.

### Small File Algorithm

```c
    if((ip->i_mode&ILARG) == 0) {

        /*
         * small file algorithm
         */

        if((bn & ~7) != 0) {
            /*
             * convert small to large
             */
            if ((bp = alloc(d)) == NULL)
                return(0);
            bap = bp->b_addr;
            for(i=0; i<8; i++) {
                *bap++ = ip->i_addr[i];
                ip->i_addr[i] = 0;
            }
            ip->i_addr[0] = bp->b_blkno;
            bdwrite(bp);
            ip->i_mode =| ILARG;
            goto large;
        }
```

For small files (ILARG not set), `i_addr[0-7]` are direct block pointers. This handles blocks 0-7.

If block 8+ is requested, the file must be converted to large format:
1. Allocate an indirect block
2. Copy the 8 direct pointers into it
3. Point `i_addr[0]` to the indirect block
4. Set ILARG flag

```c
        nb = ip->i_addr[bn];
        if(nb == 0 && (bp = alloc(d)) != NULL) {
            bdwrite(bp);
            nb = bp->b_blkno;
            ip->i_addr[bn] = nb;
            ip->i_flag =| IUPD;
        }
        if (bn<7)
            rablock = ip->i_addr[bn+1];
        else
            rablock = 0;
        return(nb);
    }
```

For blocks 0-7: return the direct pointer, allocating if necessary. Set `rablock` for read-ahead.

### Large File Algorithm

```c
    /*
     * large file algorithm
     */

large:
    i = bn>>8;                      /* Which indirect block */
    if((nb=ip->i_addr[i]) == 0) {
        ip->i_flag =| IUPD;
        if ((bp = alloc(d)) == NULL)
            return(0);
        nb = bp->b_blkno;
        ip->i_addr[i] = nb;
    } else
        bp = bread(d, nb);
```

For large files, `i_addr[0-7]` point to indirect blocks. Each indirect block contains 256 block numbers (512 bytes / 2 bytes per pointer).

- `bn >> 8` = which indirect block (0-7)
- `bn & 0377` = index within that indirect block (0-255)

```c
    bap = bp->b_addr;
    i = bn & 0377;
    if((nb=bap[i]) == 0 && (nbp = alloc(d)) != NULL) {
        nb = nbp->b_blkno;
        bap[i] = nb;
        bdwrite(nbp);
        bdwrite(bp);
    } else
        brelse(bp);
    rablock = bap[i+1];
    return(nb);
}
```

Look up the block in the indirect block, allocating if needed.

### File Size Limits

```
Small file (ILARG=0):
  i_addr[0-7] → direct blocks
  Max: 8 blocks = 4KB

Large file (ILARG=1):
  i_addr[0-7] → indirect blocks
  Each indirect: 256 block numbers
  Max: 8 × 256 = 2048 blocks = 1MB
```

## Data Transfer: iomove()

```c
/* rdwri.c */
iomove(bp, o, an, flag)
struct buf *bp;
{
    register char *cp;
    register int n, t;

    n = an;
    cp = bp->b_addr + o;            /* Buffer address + offset */
```

`iomove()` copies data between a buffer and user space.

```c
    if(u.u_segflg==0 && ((n | cp | u.u_base)&01)==0) {
        /* Fast path: user space, all aligned */
        if (flag==B_WRITE)
            cp = copyin(u.u_base, cp, n);
        else
            cp = copyout(cp, u.u_base, n);
        if (cp) {
            u.u_error = EFAULT;
            return;
        }
        u.u_base =+ n;
        dpadd(u.u_offset, n);
        u.u_count =- n;
        return;
    }
```

**Fast path**: When transferring to/from user space with aligned addresses, use `copyin`/`copyout` for efficient bulk transfer.

```c
    if (flag==B_WRITE) {
        while(n--) {
            if ((t = cpass()) < 0)
                return;
            *cp++ = t;
        }
    } else
        while (n--)
            if(passc(*cp++) < 0)
                return;
}
```

**Slow path**: Byte-by-byte transfer using `cpass()` (get byte from user) and `passc()` (put byte to user). Used for unaligned transfers or kernel-space I/O.

### passc() and cpass()

```c
/* subr.c */
passc(c)
char c;
{
    if(u.u_segflg)
        *u.u_base = c;              /* Kernel space: direct */
    else
        if(subyte(u.u_base, c) < 0) {
            u.u_error = EFAULT;
            return(-1);
        }
    u.u_count--;
    if(++u.u_offset[1] == 0)
        u.u_offset[0]++;            /* Handle 32-bit overflow */
    u.u_base++;
    return(u.u_count == 0? -1: 0);
}

cpass()
{
    register c;

    if(u.u_count == 0)
        return(-1);
    if(u.u_segflg)
        c = *u.u_base;              /* Kernel space: direct */
    else
        if((c=fubyte(u.u_base)) < 0) {
            u.u_error = EFAULT;
            return(-1);
        }
    u.u_count--;
    if(++u.u_offset[1] == 0)
        u.u_offset[0]++;
    u.u_base++;
    return(c&0377);
}
```

These handle the byte-by-byte case:
- `u.u_segflg=0`: User space, use `subyte`/`fubyte` (store/fetch user byte)
- `u.u_segflg=1`: Kernel space, direct memory access
- Update count, offset, and base pointer after each byte

## The Complete Read Path

```
read(fd, buf, count)
        │
        ▼
    sys2.c: read()
        │ u.u_base = buf
        │ u.u_count = count
        │ fp = getf(fd)
        │ u.u_offset = fp->f_offset
        ▼
    rdwri.c: readi(fp->f_inode)
        │
        ├──► Character device? → cdevsw[].d_read()
        │
        │ Loop for each block:
        │    lbn = offset / 512
        │    on = offset % 512
        │    n = min(512-on, count)
        │    │
        │    ▼
        │ subr.c: bmap(ip, lbn) → physical block
        │    │
        │    ▼
        │ bio.c: bread(dev, block) → buffer
        │    │
        │    ▼
        │ rdwri.c: iomove(bp, on, n, B_READ)
        │    │ copyin/copyout or cpass/passc
        │    ▼
        │ bio.c: brelse(bp)
        │
        ▼
    Update fp->f_offset
    Return bytes read in r0
```

## The Complete Write Path

```
write(fd, buf, count)
        │
        ▼
    sys2.c: write()
        │ u.u_base = buf
        │ u.u_count = count
        │ fp = getf(fd)
        │ u.u_offset = fp->f_offset
        ▼
    rdwri.c: writei(fp->f_inode)
        │
        ├──► Character device? → cdevsw[].d_write()
        │
        │ Loop for each block:
        │    bn = offset / 512
        │    on = offset % 512
        │    n = min(512-on, count)
        │    │
        │    ▼
        │ subr.c: bmap(ip, bn) → physical block (allocating if needed)
        │    │
        │    ▼
        │ bio.c: bread() or getblk() → buffer
        │    │
        │    ▼
        │ rdwri.c: iomove(bp, on, n, B_WRITE)
        │    │
        │    ▼
        │ bio.c: bdwrite() or bawrite()
        │    │
        │    ▼
        │ Update i_size if file grew
        │
        ▼
    Update fp->f_offset
    Return bytes written in r0
```

## Summary

- **Three levels**: file descriptors → open file table → inodes
- **readi()/writei()**: Loop over blocks, calling `bmap()` and `iomove()`
- **bmap()**: Translates logical to physical blocks, handles small/large files
- **iomove()**: Transfers data between buffers and user space
- **Read-ahead**: Sequential reads trigger prefetching of the next block
- **Write optimization**: Full blocks don't need to be read first

## Key Design Points

1. **Separation of concerns**: File descriptors handle per-process state, file entries handle sharing, inodes handle storage

2. **Lazy allocation**: Blocks are allocated only when written, not when the file is created or extended

3. **Small file optimization**: Files ≤4KB use direct blocks, avoiding indirect block overhead

4. **Read-ahead**: Sequential access patterns are detected and optimized

5. **Delayed writes**: Data stays in cache, written later, improving performance

## Experiments

1. **Trace bmap()**: Add printf to see small→large file conversion when writing block 8+.

2. **Measure read-ahead**: Compare sequential vs random read performance.

3. **Watch the file table**: Print `file[]` to see sharing after `fork()` or `dup()`.

4. **Fill the file table**: Open files until ENFILE, observe the limit.

## Further Reading

- Chapter 9: Inodes and Superblock — Where `i_addr[]` comes from
- Chapter 11: Path Resolution — How files are found
- Chapter 12: Buffer Cache — The `bread`/`bwrite` layer beneath

---

**Next: Chapter 11 — Path Resolution (namei)**
