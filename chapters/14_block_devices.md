# Chapter 14: Block Devices

## Overview

Block devices transfer data in fixed-size blocks (512 bytes in UNIX v4) and support random access. The primary block device is the disk—the RK05 cartridge disk that holds 2.4 megabytes on a removable pack. Block devices go through the buffer cache, providing caching and a uniform interface that hides the complexity of disk geometry and timing.

This chapter examines the RK05 disk driver as a case study in block device implementation.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/conf.h` | Device switch tables |
| `usr/sys/dmr/rk.c` | RK05 disk driver |
| `usr/sys/dmr/bio.c` | Buffer I/O interface |

## Prerequisites

- Chapter 12: Buffer Cache (`bread`, `bwrite`, strategy interface)

## The Block Device Switch

```c
/* conf.h */
struct bdevsw {
    int (*d_open)();      /* Open device */
    int (*d_close)();     /* Close device */
    int (*d_strategy)();  /* Queue I/O request */
    int *d_tab;           /* Device queue table */
} bdevsw[];
```

Every block device provides these four entry points. The `d_strategy` routine is the key—it accepts buffer requests and handles all I/O.

Example configuration:
```c
/* conf/c.c */
struct bdevsw bdevsw[] {
    &nulldev, &nulldev, &rkstrategy, &rktab,   /* 0 = rk */
    &nulldev, &nulldev, &tmstrategy, &tmtab,   /* 1 = tm (tape) */
    0
};
```

## Device Numbers

```c
/* conf.h */
struct {
    char d_minor;    /* Unit number within device type */
    char d_major;    /* Index into bdevsw[] */
};
```

A device number encodes:
- **Major number**: Which driver (0=rk, 1=tm, etc.)
- **Minor number**: Which unit or partition

For example, device 0407 = major 04, minor 07 = RK disk, unit 7.

## The RK05 Disk

The RK05 is a cartridge disk:
- **Capacity**: 2.4 MB per pack
- **Geometry**: 203 cylinders × 2 surfaces × 12 sectors
- **Block size**: 512 bytes (256 words)
- **Total blocks**: 4,872 per disk

```
        ┌─────────────────────┐
        │     RK05 Drive      │
        │  ┌───────────────┐  │
        │  │ Removable     │  │
        │  │ Cartridge     │  │
        │  │  2.4 MB       │  │
        │  └───────────────┘  │
        └─────────────────────┘
```

### Hardware Registers

```c
#define RKADDR 0177400    /* Base address */

struct {
    int rkds;    /* Drive status */
    int rker;    /* Error register */
    int rkcs;    /* Control/status */
    int rkwc;    /* Word count */
    int rkba;    /* Bus address */
    int rkda;    /* Disk address */
};
```

The disk address register encodes cylinder, surface, and sector:
```
rkda = (drive << 13) | (cylinder << 4) | sector
```

## rkstrategy() — Queue a Request

The strategy routine is called by the buffer cache to perform I/O:

```c
/* rk.c */
rkstrategy(abp)
struct buf *abp;
{
    register struct buf *bp;
    register *qc, *ql;
    int d;

    bp = abp;
    d = bp->b_dev.d_minor-7;
    if(d <= 0)
        d = 1;
    if (bp->b_blkno >= NRKBLK*d) {
        bp->b_flags =| B_ERROR;
        iodone(bp);
        return;
    }
```

Validate the block number. If it's beyond the disk capacity, return an error immediately.

```c
    bp->av_forw = 0;
    bp->b_flags =& ~B_SEEK;
    if(bp->b_dev.d_minor < 8)
        d = bp->b_dev.d_minor;
    else
        d = lrem(bp->b_blkno, d);
```

Determine which physical drive this request is for.

```c
    spl5();
    if ((ql = *(qc = &rk_q[d])) == NULL) {
        *qc = bp;
        if (RKADDR->rkcs&CTLRDY)
            rkstart();
        goto ret;
    }
```

If the drive's queue is empty, add this request and start I/O if the controller is ready.

```c
    while ((qc = ql->av_forw) != NULL) {
        if (ql->b_blkno<bp->b_blkno
         && bp->b_blkno<qc->b_blkno
         || ql->b_blkno>bp->b_blkno
         && bp->b_blkno>qc->b_blkno) {
            ql->av_forw = bp;
            bp->av_forw = qc;
            goto ret;
        }
        ql = qc;
    }
    ql->av_forw = bp;
ret:
    spl0();
}
```

**Elevator algorithm**: Insert the request in sorted order by block number. This minimizes seek time by processing requests in the direction the head is moving, like an elevator.

## rkstart() — Initiate Seeks

```c
/* rk.c */
rkstart()
{
    register struct buf *bp;
    register int *qp;

    for (qp = rk_q; qp < &rk_q[NRK];) {
        if ((bp = *qp++) && (bp->b_flags&B_SEEK)==0) {
            RKADDR->rkda = rkaddr(bp);
            rkcommand(IENABLE|SEEK|GO);
            if (RKADDR->rkcs<0) {
                bp->b_flags =| B_ERROR;
                *--qp = bp->av_forw;
                iodone(bp);
                rkerror();
            } else
                bp->b_flags =| B_SEEK;
        }
    }
}
```

**Overlapped seeks**: Start seeks on all drives that have pending requests. While one drive is seeking, another can be transferring data. The RK11 controller supports this parallelism.

## rkaddr() — Compute Disk Address

```c
/* rk.c */
rkaddr(bp)
struct buf *bp;
{
    register struct buf *p;
    register int b;
    int d, m;

    p = bp;
    b = p->b_blkno;
    m = p->b_dev.d_minor - 7;
    if(m <= 0)
        d = p->b_dev.d_minor;
    else {
        d = lrem(b, m);
        b = ldiv(b, m);
    }
    return(d<<13 | (b/12)<<4 | b%12);
}
```

Converts a linear block number to RK05 physical address:
- Sector = block % 12
- Cylinder = block / 12
- Pack into: `(drive << 13) | (cylinder << 4) | sector`

## rkintr() — Interrupt Handler

```c
/* rk.c */
rkintr()
{
    register struct buf *bp;

    if (RKADDR->rkcs < 0) {
        if (RKADDR->rker&WLO || ++rktab.d_errcnt>10)
            rkpost(B_ERROR);
        rkerror();
    }
```

Check for errors. Write-lock errors are fatal; others retry up to 10 times.

```c
    if (RKADDR->rkcs&SEEKCMP) {
        rk_ap = &rk_q[(RKADDR->rkds>>13) & 07];
        devstart(*rk_ap, &RKADDR->rkda, rkaddr(*rk_ap), 0);
    } else
        rkpost(0);
}
```

Two types of interrupts:
1. **Seek complete** (SEEKCMP): Start the data transfer using `devstart()`
2. **Transfer complete**: Call `rkpost()` to finish up

## devstart() — Start Data Transfer

```c
/* bio.c */
devstart(bp, devloc, devblk, hbcom)
struct buf *bp;
int *devloc;
{
    register int *dp;
    register struct buf *rbp;
    register int com;

    dp = devloc;
    rbp = bp;
    *dp = devblk;               /* Block address */
    *--dp = rbp->b_addr;        /* Buffer address */
    *--dp = rbp->b_wcount;      /* Word count */
    com = (hbcom<<8) | IENABLE | GO | rbp->b_flags&B_XMEM;
    if (rbp->b_flags&B_READ)
        com =| RCOM;
    else
        com =| WCOM;
    *--dp = com;
}
```

Programs the device registers and starts the transfer. The PDP-11 DMA controller handles the actual data movement.

## rkpost() — Complete I/O

```c
/* rk.c */
rkpost(errbit)
{
    register struct buf *bp;

    if (rk_ap) {
        bp = *rk_ap;
        bp->b_flags =| B_DONE | errbit;
        *rk_ap = bp->av_forw;
        rk_ap = NULL;
        iodone(bp);
        rktab.d_errcnt = 0;
        rkstart();
    }
}
```

Mark the buffer done, remove from queue, call `iodone()` to wake waiting processes, and start the next request.

## Raw I/O: rkread() and rkwrite()

```c
/* rk.c */
rkread(dev)
{
    physio(rkstrategy, &rrkbuf, dev, B_READ);
}

rkwrite(dev)
{
    physio(rkstrategy, &rrkbuf, dev, B_WRITE);
}
```

Raw (character) device interface bypasses the buffer cache, transferring directly to/from user memory. Uses `physio()` from bio.c.

## physio() — Physical I/O

```c
/* bio.c */
physio(strat, abp, dev, rw)
struct buf *abp;
int (*strat)();
{
    register struct buf *bp;
    register char *base;
    register int nb;

    bp = abp;
    base = u.u_base;
    /* Validate user buffer address */
    if (base&01 || u.u_count&01 || base>=base+u.u_count)
        goto bad;
```

Check alignment and bounds.

```c
    spl6();
    while (bp->b_flags&B_BUSY) {
        bp->b_flags =| B_WANTED;
        sleep(bp, PRIBIO);
    }
    bp->b_flags = B_BUSY | rw;
    bp->b_dev = dev;
    /* Set up transfer parameters */
    bp->b_blkno = lshift(u.u_offset, -9);
    bp->b_wcount = -(u.u_count>>1);
```

Wait for the raw buffer, then set it up for transfer.

```c
    u.u_procp->p_flag =| SLOCK;
    (*strat)(bp);
    spl6();
    while ((bp->b_flags&B_DONE) == 0)
        sleep(bp, PRIBIO);
    u.u_procp->p_flag =& ~SLOCK;
```

Lock process in memory (can't swap during DMA!), call strategy, wait for completion.

## I/O Flow Summary

### Buffered Read

```
bread(dev, blkno)
        │
        ▼
    getblk() → buffer
        │
        ▼
    B_DONE set? ───Yes──► return (cache hit)
        │
        No
        ▼
    rkstrategy(bp)
        │
        ├──► Insert in queue (elevator order)
        │
        └──► rkstart() if idle
                │
                ▼
            SEEK command
                │
         [seek interrupt]
                │
                ▼
            devstart()
                │
         [transfer interrupt]
                │
                ▼
            rkpost() → iodone()
                │
                ▼
            wakeup(bp)
                │
                ▼
            iowait() returns
                │
                ▼
            return buffer
```

### Raw Read

```
read(/dev/rrk0, buf, count)
        │
        ▼
    rkread(dev)
        │
        ▼
    physio(rkstrategy, &rrkbuf, dev, B_READ)
        │
        ├──► Lock process in memory
        │
        ├──► rkstrategy(bp)
        │         │
        │    [same as buffered]
        │         │
        ▼         ▼
    sleep until B_DONE
        │
        ▼
    Unlock process
        │
        ▼
    Return to user
```

## Error Handling

```c
rkerror()
{
    register int *qp;
    register struct buf *bp;

    rkcommand(IENABLE|RESET|GO);
    for (qp = rk_q; qp < &rk_q[NRK];)
        if ((bp = *qp++) != NULL && bp->b_flags&B_SEEK) {
            RKADDR->rkda = rkaddr(bp);
            while ((RKADDR->rkds&(DRY|ARDY)) == DRY);
            rkcommand(IENABLE|DRESET|GO);
        }
}
```

On error: reset controller, recalibrate all drives that were seeking. The strategy routine will retry up to 10 times before giving up.

## Multiple Drives

```
           rk_q[0]        rk_q[1]        rk_q[2]        rk_q[3]
           ┌─────┐        ┌─────┐        ┌─────┐        ┌─────┐
           │ bp  │───►    │ bp  │───►    │NULL │        │ bp  │───►
           └─────┘        └─────┘        └─────┘        └─────┘
              │              │                             │
              ▼              ▼                             ▼
          ┌──────┐      ┌──────┐                      ┌──────┐
          │ blk  │      │ blk  │                      │ blk  │
          │  47  │      │ 102  │                      │ 891  │
          └──────┘      └──────┘                      └──────┘
              │              │
              ▼              ▼
          ┌──────┐      ┌──────┐
          │ blk  │      │ blk  │
          │ 156  │      │ 340  │
          └──────┘      └──────┘
```

Each drive has its own queue. Seeks can overlap across drives—while drive 0 seeks to cylinder 47, drive 1 can be transferring block 102.

## Summary

- **Strategy routine**: Main entry point, queues requests
- **Elevator algorithm**: Minimizes seek time
- **Overlapped seeks**: Multiple drives seek simultaneously
- **Interrupt-driven**: CPU free during disk operations
- **Error retry**: Automatic recovery from transient errors
- **Raw I/O**: Bypasses cache for special applications

## Key Design Points

1. **Asynchronous**: `rkstrategy()` returns immediately; completion via interrupt.

2. **Queueing**: Requests accumulate and are processed optimally.

3. **Parallelism**: Controller handles seeks on multiple drives.

4. **Abstraction**: Buffer cache sees only `strategy()`—no geometry details.

5. **DMA**: Data moves without CPU involvement.

## Experiments

1. **Trace seeks**: Add printf to see elevator ordering in action.

2. **Measure throughput**: Compare sequential vs random block access.

3. **Force errors**: Observe retry behavior with a bad block.

4. **Raw vs buffered**: Compare performance for large sequential reads.

## Further Reading

- Chapter 12: Buffer Cache — The interface above block devices
- Chapter 13: TTY Subsystem — Contrasts character device model
- Chapter 15: Character Devices — Non-block device patterns

---

**Next: Chapter 15 — Character Devices**
