# Chapter 12: The Buffer Cache

## Overview

The buffer cache is the kernel's interface to block devices. Every disk read and write passes through this layer, which maintains an in-memory cache of recently-used disk blocks. The cache dramatically improves performance by avoiding redundant disk I/O and provides a uniform interface that hides device-specific details.

This is Dennis Ritchie's code (`usr/sys/dmr/bio.c`)—elegant, compact, and the foundation upon which all file operations rest.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/buf.h` | Buffer structure and flags |
| `usr/sys/dmr/bio.c` | Buffer cache implementation |

## Prerequisites

- Chapter 9: Inodes and Superblock (uses `bread`/`bwrite`)
- Chapter 10: File I/O (uses buffer cache for all I/O)

## The Buffer Structure

```c
/* buf.h */
struct buf {
    int   b_flags;      /* Status flags */
    struct buf *b_forw; /* Hash chain forward */
    struct buf *b_back; /* Hash chain backward */
    struct buf *av_forw; /* Free list forward */
    struct buf *av_back; /* Free list backward */
    int   b_dev;        /* Device number */
    int   b_wcount;     /* Word count for transfer */
    char  *b_addr;      /* Buffer memory address */
    char  *b_blkno;     /* Block number on device */
    char  b_error;      /* Error code */
    char  *b_resid;     /* Residual count after I/O */
} buf[NBUF];
```

Each buffer has two sets of links:
- `b_forw`/`b_back` — Hash chain (by device + block number)
- `av_forw`/`av_back` — Free list (LRU order)

With `NBUF=15`, the system has 15 buffers, each 514 bytes (512 data + 2 for word count).

### Buffer Flags

```c
#define B_WRITE   0       /* Write operation */
#define B_READ    01      /* Read operation */
#define B_DONE    02      /* I/O complete */
#define B_ERROR   04      /* Error occurred */
#define B_BUSY    010     /* Buffer in use */
#define B_XMEM    060     /* Extended memory bits */
#define B_WANTED  0100    /* Process waiting for buffer */
#define B_RELOC   0200    /* Relocatable buffer */
#define B_ASYNC   0400    /* Asynchronous I/O */
#define B_DELWRI  01000   /* Delayed write pending */
```

Key flags:
- `B_BUSY` — Buffer is allocated to someone
- `B_DONE` — I/O has completed (data is valid)
- `B_DELWRI` — Buffer has been written but not yet flushed to disk
- `B_ASYNC` — Don't wait for I/O completion

## Buffer Lists

### The Hash Chains

Buffers are organized by device into hash chains:

```
devtab[0] (rk0)     devtab[1] (rk1)     ...
+--------+          +--------+
| b_forw |──►buf──► | b_forw |──►buf──►buf──►
| b_back |◄──   ◄── | b_back |◄──   ◄──   ◄──
+--------+          +--------+
```

Each device has a `devtab` structure serving as the list head. To find a cached block, search the appropriate device's chain.

### The Free List

Available buffers form a doubly-linked LRU list:

```
bfreelist
+----------+
| av_forw  |──► oldest ──► ... ──► newest ──┐
| av_back  |◄── oldest ◄── ... ◄── newest ◄─┘
+----------+
     ▲                                  │
     └──────────────────────────────────┘
```

Buffers are taken from the front (oldest) and returned to the back (newest). This implements LRU replacement.

## binit() — Initialization

```c
/* bio.c */
binit()
{
    register struct buf *bp;
    register struct devtab *dp;
    register int i;
    struct bdevsw *bdp;

    bfreelist.b_forw = bfreelist.b_back =
        bfreelist.av_forw = bfreelist.av_back = &bfreelist;
```

Initialize the free list as an empty circular list.

```c
    for (i=0; i<NBUF; i++) {
        bp = &buf[i];
        bp->b_dev = -1;
        bp->b_addr = buffers[i];
        bp->b_back = &bfreelist;
        bp->b_forw = bfreelist.b_forw;
        bfreelist.b_forw->b_back = bp;
        bfreelist.b_forw = bp;
        bp->b_flags = B_BUSY;
        brelse(bp);
    }
```

Link each buffer into the free list and assign its data area from the `buffers` array.

```c
    i = 0;
    for (bdp = bdevsw; bdp->d_open; bdp++) {
        dp = bdp->d_tab;
        dp->b_forw = dp;
        dp->b_back = dp;
        i++;
    }
    nblkdev = i;
}
```

Initialize each device's hash chain as empty.

## getblk() — Get a Buffer

The heart of the buffer cache:

```c
/* bio.c */
getblk(dev, blkno)
{
    register struct buf *bp;
    register struct devtab *dp;

    if(dev.d_major >= nblkdev)
        panic("blkdev");

loop:
    if (dev < 0)
        dp = &bfreelist;        /* NODEV: just get any buffer */
    else {
        dp = bdevsw[dev.d_major].d_tab;
        for (bp=dp->b_forw; bp != dp; bp = bp->b_forw) {
            if (bp->b_blkno!=blkno || bp->b_dev!=dev)
                continue;
```

Search the device's hash chain for the requested block.

```c
            spl6();             /* Disable interrupts */
            if (bp->b_flags&B_BUSY) {
                bp->b_flags =| B_WANTED;
                sleep(bp, PRIBIO);
                spl0();
                goto loop;      /* Retry after wakeup */
            }
            spl0();
            notavail(bp);       /* Remove from free list */
            return(bp);
        }
    }
```

If found but busy, wait for it. If found and free, remove from free list and return.

```c
    spl6();
    if (bfreelist.av_forw == &bfreelist) {
        bfreelist.b_flags =| B_WANTED;
        sleep(&bfreelist, PRIBIO);
        spl0();
        goto loop;              /* Retry when buffer freed */
    }
    spl0();
    notavail(bp = bfreelist.av_forw);  /* Take oldest buffer */
```

If not in cache, take the oldest buffer from the free list. If the free list is empty, wait.

```c
    if (bp->b_flags & B_DELWRI) {
        bp->b_flags =| B_ASYNC;
        bwrite(bp);             /* Flush dirty buffer */
        goto loop;              /* Retry with different buffer */
    }
```

If the victim buffer has pending writes, flush it first and try again.

```c
    bp->b_flags = B_BUSY | B_RELOC;
    bp->b_back->b_forw = bp->b_forw;   /* Remove from old hash chain */
    bp->b_forw->b_back = bp->b_back;
    bp->b_forw = dp->b_forw;           /* Insert in new hash chain */
    bp->b_back = dp;
    dp->b_forw->b_back = bp;
    dp->b_forw = bp;
    bp->b_dev = dev;
    bp->b_blkno = blkno;
    return(bp);
}
```

Move the buffer from its old hash chain to the new one, update device and block number.

## bread() — Read a Block

```c
/* bio.c */
bread(dev, blkno)
{
    register struct buf *rbp;

    rbp = getblk(dev, blkno);
    if (rbp->b_flags&B_DONE)
        return(rbp);            /* Already in cache! */
    rbp->b_flags =| B_READ;
    rbp->b_wcount = -256;       /* 256 words = 512 bytes */
    (*bdevsw[dev.d_major].d_strategy)(rbp);
    iowait(rbp);
    return(rbp);
}
```

1. Get a buffer for the block
2. If `B_DONE` is set, data is already valid—cache hit!
3. Otherwise, initiate a read through the device's strategy routine
4. Wait for completion

The strategy routine is device-specific (e.g., `rkstrategy` for the RK05 disk).

## breada() — Read with Read-Ahead

```c
/* bio.c */
breada(adev, blkno, rablkno)
{
    register struct buf *rbp, *rabp;
    register int dev;

    dev = adev;
    rbp = 0;
    if (!incore(dev, blkno)) {
        rbp = getblk(dev, blkno);
        if ((rbp->b_flags&B_DONE) == 0) {
            rbp->b_flags =| B_READ;
            rbp->b_wcount = -256;
            (*bdevsw[adev.d_major].d_strategy)(rbp);
        }
    }
```

If the requested block isn't cached, start reading it.

```c
    if (rablkno && !incore(dev, rablkno) && raflag) {
        rabp = getblk(dev, rablkno);
        if (rabp->b_flags & B_DONE)
            brelse(rabp);
        else {
            rabp->b_flags =| B_READ|B_ASYNC;
            rabp->b_wcount = -256;
            (*bdevsw[adev.d_major].d_strategy)(rabp);
        }
    }
```

If a read-ahead block is specified and not cached, start reading it **asynchronously** (`B_ASYNC`). This means we don't wait for it—it will be ready when needed.

```c
    if (rbp==0)
        return(bread(dev, blkno));  /* Was already cached */
    iowait(rbp);
    return(rbp);
}
```

Wait for the primary block and return it. The read-ahead block completes in the background.

## incore() — Check Cache

```c
/* bio.c */
incore(adev, blkno)
{
    register int dev;
    register struct buf *bp;
    register struct devtab *dp;

    dev = adev;
    dp = bdevsw[adev.d_major].d_tab;
    for (bp=dp->b_forw; bp != dp; bp = bp->b_forw)
        if (bp->b_blkno==blkno && bp->b_dev==dev)
            return(bp);
    return(0);
}
```

Returns the buffer if the block is in cache, NULL otherwise. Used by `breada()` to avoid redundant I/O.

## Write Operations

### bwrite() — Synchronous Write

```c
/* bio.c */
bwrite(bp)
struct buf *bp;
{
    register struct buf *rbp;
    register flag;

    rbp = bp;
    flag = rbp->b_flags;
    rbp->b_flags =& ~(B_READ | B_DONE | B_ERROR | B_DELWRI);
    rbp->b_wcount = -256;
    (*bdevsw[rbp->b_dev.d_major].d_strategy)(rbp);
    if ((flag&B_ASYNC) == 0) {
        iowait(rbp);
        brelse(rbp);
    } else if ((flag&B_DELWRI)==0)
        geterror(rbp);
}
```

Start the write operation. If not async, wait for completion and release the buffer.

### bdwrite() — Delayed Write

```c
/* bio.c */
bdwrite(bp)
struct buf *bp;
{
    register struct buf *rbp;

    rbp = bp;
    if (bdevsw[rbp->b_dev.d_major].d_tab == &tmtab)
        bawrite(rbp);           /* Magtape: no delay */
    else {
        rbp->b_flags =| B_DELWRI | B_DONE;
        brelse(rbp);
    }
}
```

Mark the buffer as dirty (`B_DELWRI`) and release it. The actual write happens later, when:
- The buffer is reclaimed by `getblk()`
- `bflush()` is called (by `sync`)

This batches writes for efficiency.

### bawrite() — Asynchronous Write

```c
/* bio.c */
bawrite(bp)
struct buf *bp;
{
    register struct buf *rbp;

    rbp = bp;
    rbp->b_flags =| B_ASYNC;
    bwrite(rbp);
}
```

Start the write but don't wait. The buffer is released when I/O completes (in `iodone()`).

## brelse() — Release Buffer

```c
/* bio.c */
brelse(bp)
struct buf *bp;
{
    register struct buf *rbp, **backp;
    register int sps;

    rbp = bp;
    if (rbp->b_flags&B_WANTED)
        wakeup(rbp);            /* Wake waiters */
    if (bfreelist.b_flags&B_WANTED) {
        bfreelist.b_flags =& ~B_WANTED;
        wakeup(&bfreelist);     /* Wake buffer-starved processes */
    }
    if (rbp->b_flags&B_ERROR)
        rbp->b_dev.d_minor = -1;  /* Disassociate on error */
```

Wake any processes waiting for this buffer or for any free buffer.

```c
    backp = &bfreelist.av_back;
    sps = PS->int;
    spl6();
    rbp->b_flags =& ~(B_WANTED|B_BUSY|B_ASYNC);
    (*backp)->av_forw = rbp;
    rbp->av_back = *backp;
    *backp = rbp;
    rbp->av_forw = &bfreelist;
    PS->int = sps;
}
```

Insert at the back of the free list (newest). The buffer remains on its hash chain—if the same block is needed again soon, it can be found instantly.

## I/O Completion

### iowait() — Wait for I/O

```c
/* bio.c */
iowait(bp)
struct buf *bp;
{
    register struct buf *rbp;

    rbp = bp;
    spl6();
    while ((rbp->b_flags&B_DONE)==0)
        sleep(rbp, PRIBIO);
    spl0();
    geterror(rbp);
}
```

Sleep until the device sets `B_DONE`, then check for errors.

### iodone() — I/O Complete (Interrupt Handler)

```c
/* bio.c */
iodone(bp)
struct buf *bp;
{
    register struct buf *rbp;

    rbp = bp;
    rbp->b_flags =| B_DONE;
    if (rbp->b_flags&B_ASYNC)
        brelse(rbp);
    else {
        rbp->b_flags =& ~B_WANTED;
        wakeup(rbp);
    }
}
```

Called from device interrupt handlers. Sets `B_DONE` and either releases the buffer (async) or wakes waiting processes.

## notavail() — Remove from Free List

```c
/* bio.c */
notavail(bp)
struct buf *bp;
{
    register struct buf *rbp;
    register int sps;

    rbp = bp;
    sps = PS->int;
    spl6();
    rbp->av_back->av_forw = rbp->av_forw;
    rbp->av_forw->av_back = rbp->av_back;
    rbp->b_flags =| B_BUSY;
    PS->int = sps;
}
```

Unlinks a buffer from the free list and marks it busy. The buffer stays on its hash chain.

## bflush() — Flush Dirty Buffers

```c
/* bio.c */
bflush(dev)
{
    register struct buf *bp;

loop:
    spl6();
    for (bp = bfreelist.av_forw; bp != &bfreelist; bp = bp->av_forw) {
        if (bp->b_flags&B_DELWRI && (dev == NODEV||dev==bp->b_dev)) {
            bp->b_flags =| B_ASYNC;
            notavail(bp);
            bwrite(bp);
            goto loop;
        }
    }
    spl0();
}
```

Write all dirty buffers for a device (or all devices if `NODEV`). Called by `sync` system call and `update()`.

## swap() — Swap I/O

```c
/* bio.c */
swap(blkno, coreaddr, count, rdflg)
{
    register int *fp;

    fp = &swbuf.b_flags;
    spl6();
    while (*fp&B_BUSY) {
        *fp =| B_WANTED;
        sleep(fp, PSWP);
    }
    *fp = B_BUSY | rdflg | (coreaddr>>6)&B_XMEM;
    swbuf.b_dev = swapdev;
    swbuf.b_wcount = - (count<<5);
    swbuf.b_blkno = blkno;
    swbuf.b_addr = coreaddr<<6;
    (*bdevsw[swapdev>>8].d_strategy)(&swbuf);
    spl6();
    while((*fp&B_DONE)==0)
        sleep(fp, PSWP);
    if (*fp&B_WANTED)
        wakeup(fp);
    spl0();
    *fp =& ~(B_BUSY|B_WANTED);
    return(*fp&B_ERROR);
}
```

Special buffer (`swbuf`) for swap I/O. Bypasses the normal cache since swapped pages don't need caching—they're only read once when needed.

## The Device Strategy Interface

The buffer cache calls device drivers through the strategy routine:

```c
(*bdevsw[dev.d_major].d_strategy)(bp);
```

The driver queues the request, starts the device if idle, and returns immediately. When I/O completes, the device interrupt handler calls `iodone(bp)`.

## Complete Read Flow

```
read(fd, buf, 512)
        │
        ▼
    readi() ────► bmap() → block number
        │
        ▼
    bread(dev, blkno)
        │
        ├──► getblk() ────► Found in cache with B_DONE?
        │                           │
        │                    Yes    │   No
        │                     │     │
        │                     ▼     ▼
        │               return   Call driver strategy
        │                           │
        │                           ▼
        │                      iowait()
        │                           │
        │                           ▼
        │                  [Device interrupt]
        │                           │
        │                           ▼
        │                      iodone()
        │                           │
        ▼                           ▼
    iomove() ◄─────────────── return buffer
        │
        ▼
    brelse()
```

## Summary

- **15 buffers** cache recent disk blocks
- **Hash chains** enable fast lookup by device + block
- **Free list** implements LRU replacement
- **Delayed write** batches writes for efficiency
- **Read-ahead** prefetches sequential blocks
- **Strategy interface** abstracts device differences

## Key Design Points

1. **Unified interface**: All block I/O goes through `bread`/`bwrite`, hiding device complexity.

2. **Double linking**: Each buffer is on both a hash chain (for lookup) and the free list (for allocation).

3. **Lazy writes**: `bdwrite()` defers writing, improving performance for multiple writes to the same block.

4. **Asynchronous I/O**: `B_ASYNC` allows the CPU to continue while I/O proceeds.

5. **LRU replacement**: Most recently used blocks stay cached longest.

6. **Cache coherence**: A block can only be in one buffer—no stale copies.

## Experiments

1. **Cache hit rate**: Count `B_DONE` hits in `bread()` vs disk reads.

2. **Buffer starvation**: Reduce `NBUF` and observe performance degradation.

3. **Delayed write timing**: Track how long `B_DELWRI` buffers stay dirty before flush.

4. **Read-ahead effectiveness**: Compare performance with `raflag=0` vs `raflag=1`.

## Further Reading

- Chapter 14: Block Devices — Device drivers and strategy routines
- Chapter 9: Inodes and Superblock — How the file system uses the cache
- Chapter 10: File I/O — The higher-level I/O functions

---

**Part III Complete! Next: Part IV — Device Drivers**
