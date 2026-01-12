# Chapter 6: Memory Management

## Overview

UNIX v4 manages memory with elegant simplicity. There's no virtual memory in the modern sense—no page tables, no demand paging, no memory-mapped files. Instead, processes exist entirely in physical memory or entirely on swap. This chapter examines how UNIX allocates, tracks, and swaps memory.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/dmr/malloc.c` | `malloc()`, `mfree()` — map allocator |
| `usr/sys/ken/main.c` | Memory discovery, `estabur()`, `sureg()` |
| `usr/sys/ken/slp.c` | `expand()`, `sched()`, `xswap()` |
| `usr/sys/systm.h` | `coremap[]`, `swapmap[]` definitions |
| `usr/sys/param.h` | MAXMEM, CMAPSIZ, SMAPSIZ |

## Prerequisites

- Chapter 2: PDP-11 Architecture (MMU, segments)
- Chapter 5: Process Management (process structure)

## The Memory Model

UNIX v4 uses a simple model:

```
Physical Memory:
+------------------+ 0
|     Kernel       | (text, data, bss)
+------------------+
|   User Block     | (u. for current process)
+------------------+
|   Free Memory    | (managed by coremap)
|   Processes      |
|   Buffers        |
+------------------+ maxmem
|   (non-existent) |
+------------------+ 64KB limit

Swap Space:
+------------------+ swplo
|   Swapped procs  | (managed by swapmap)
|   ...            |
+------------------+ swplo+nswap
```

Key characteristics:
- **No paging** — Entire processes are swapped, not individual pages
- **No sharing** — Except for read-only text segments
- **Contiguous allocation** — Each process occupies a contiguous region
- **First-fit algorithm** — Simple but effective

## The Map Allocator

The core of memory management is a general-purpose allocator used for both core memory (`coremap`) and swap space (`swapmap`):

```c
/* malloc.c */
struct map {
    char *m_size;    /* Size of this free region */
    char *m_addr;    /* Starting address */
};
```

A map is an array of (size, address) pairs, sorted by address, terminated by a zero-size entry:

```
coremap:
+------+------+
| size | addr |  Free region 1
+------+------+
| size | addr |  Free region 2
+------+------+
|  0   |  -   |  End marker
+------+------+
```

### malloc() — Allocate from Map

```c
malloc(mp, size)
struct map *mp;
{
    register int a;
    register struct map *bp;

    for (bp = mp; bp->m_size; bp++) {
        if (bp->m_size >= size) {
            a = bp->m_addr;
            bp->m_addr =+ size;
            if ((bp->m_size =- size) == 0)
                /* Remove empty entry by shifting */
                do {
                    bp++;
                    (bp-1)->m_addr = bp->m_addr;
                } while ((bp-1)->m_size = bp->m_size);
            return(a);
        }
    }
    return(0);    /* No space */
}
```

Algorithm (**first-fit**):
1. Scan the map for a region ≥ requested size
2. If found, allocate from the *start* of the region
3. Shrink the region (or remove if empty)
4. Return the starting address (or 0 if no space)

Example — allocating 3 blocks:

```
Before:             After:
| 5 | 100 |         | 2 | 103 |
| 3 | 200 |    →    | 3 | 200 |
| 0 |     |         | 0 |     |

Returns: 100
```

### mfree() — Free to Map

```c
mfree(mp, size, aa)
struct map *mp;
{
    register struct map *bp;
    register int t;
    register int a;

    a = aa;
    for (bp = mp; bp->m_addr<=a && bp->m_size!=0; bp++);
```

Find where this block fits in the sorted list.

```c
    if (bp>mp && (bp-1)->m_addr+(bp-1)->m_size == a) {
        /* Coalesce with previous region */
        (bp-1)->m_size =+ size;
        if (a+size == bp->m_addr) {
            /* Also coalesce with next region */
            (bp-1)->m_size =+ bp->m_size;
            while (bp->m_size) {
                bp++;
                (bp-1)->m_addr = bp->m_addr;
                (bp-1)->m_size = bp->m_size;
            }
        }
    }
```

Try to merge with adjacent free regions.

```c
    } else {
        if (a+size == bp->m_addr && bp->m_size) {
            /* Coalesce with next region */
            bp->m_addr =- size;
            bp->m_size =+ size;
        } else if (size) do {
            /* Insert new entry (shift others down) */
            t = bp->m_addr;
            bp->m_addr = a;
            a = t;
            t = bp->m_size;
            bp->m_size = size;
            bp++;
        } while (size = t);
    }
}
```

If can't merge, insert a new entry (shifting subsequent entries).

Example — freeing 2 blocks at address 105:

```
Before:             After:
| 2 | 103 |         | 4 | 103 |    (merged!)
| 3 | 200 |    →    | 3 | 200 |
| 0 |     |         | 0 |     |
```

### Coalescing

The `mfree()` function handles four cases:

1. **Merge with previous**: freed block is adjacent to end of previous
2. **Merge with next**: freed block is adjacent to start of next
3. **Merge with both**: freed block bridges two regions
4. **No merge**: create new entry

This prevents fragmentation by keeping free regions as large as possible.

## Memory Discovery

At boot, `main()` discovers available memory:

```c
/* main.c */
main()
{
    updlock = 0;
    UISA->r[0] = KISA->r[6] + USIZE;
    UISD->r[0] = 077406;
    for(; fubyte(0) >= 0; UISA->r[0]++) {
        clearseg(UISA->r[0]);
        maxmem++;
        mfree(coremap, 1, UISA->r[0]);
    }
    printf("mem = %l\n", maxmem*10/32);
    maxmem = min(maxmem, MAXMEM);
    mfree(swapmap, nswap, swplo);
```

How it works:
1. Map user segment 0 to physical memory after the kernel
2. Try to read byte 0 of that segment with `fubyte()`
3. If successful, memory exists—clear it and add to `coremap`
4. Advance to next 64-byte block and repeat
5. When `fubyte()` fails (returns -1), we've hit non-existent memory

After the loop, `coremap` contains one large free region starting just after the kernel.

## Process Memory Layout

Each process has:

```
Process Memory:
+------------------+ p_addr
|   User Block     | USIZE blocks (1KB)
|   (u.)           |
+------------------+ p_addr + USIZE
|   Data Segment   | u_dsize blocks
|   (+ BSS)        |
+------------------+
|   (free space)   |
+------------------+
|   Stack Segment  | u_ssize blocks
+------------------+ p_addr + p_size

Text Segment:      (if shared, stored separately)
+------------------+ x_caddr
|   Code           | x_size blocks
+------------------+
```

The `p_size` field in `struct proc` is the total size in 64-byte blocks.

## Segment Register Management

### estabur() — Establish User Registers

```c
/* main.c */
estabur(nt, nd, ns)    /* text, data, stack sizes */
{
    register a, *ap, *dp;

    /* Check limits */
    if(nseg(nt)+nseg(nd)+nseg(ns) > 8 || nt+nd+ns+USIZE > maxmem) {
        u.u_error = ENOMEM;
        return(-1);
    }
```

First, verify the request is feasible:
- No more than 8 segments total
- Total memory ≤ available

```c
    /* Text segments (read-only) */
    a = 0;
    ap = &u.u_uisa[0];
    dp = &u.u_uisd[0];
    while(nt >= 128) {
        *dp++ = (127<<8) | RO;
        *ap++ = a;
        a =+ 128;
        nt =- 128;
    }
    if(nt) {
        *dp++ = ((nt-1)<<8) | RO;
        *ap++ = a;
    }
```

Text is read-only, starting at relative address 0.

```c
    /* Data segments (read-write) */
    a = USIZE;    /* After user block */
    while(nd >= 128) {
        *dp++ = (127<<8) | RW;
        *ap++ = a;
        a =+ 128;
        nd =- 128;
    }
    if(nd) {
        *dp++ = ((nd-1)<<8) | RW;
        *ap++ = a;
    }
```

Data is read-write, starting after the user block.

```c
    /* Clear unused segments */
    while(ap < &u.u_uisa[8]) {
        *dp++ = 0;
        *ap++ = 0;
    }

    /* Stack segment (expand down) */
    a =+ ns;
    while(ns >= 128) {
        a =- 128;
        ns =- 128;
        *--dp = (127<<8) | RW;
        *--ap = a;
    }
    if(ns) {
        *--dp = ((128-ns)<<8) | RW | ED;
        *--ap = a-128;
    }
    sureg();
    return(0);
}
```

Stack is at the end, with the `ED` (expand down) bit.

### sureg() — Set User Registers

```c
/* main.c */
sureg()
{
    register *up, *rp, a;

    a = u.u_procp->p_addr;
    up = &u.u_uisa[0];
    rp = &UISA->r[0];
    while(rp < &UISA->r[8])
        *rp++ = *up++ + a;
```

Copy user segment addresses to hardware, adding the process base address.

The user structure stores *relative* addresses; `sureg()` converts to *absolute* physical addresses.

## Swapping

When memory is tight, processes are **swapped** to disk:

### xswap() — Swap Out a Process

```c
/* slp.c */
xswap(p, ff, os)
struct proc *p;
{
    register a;

    if(os == 0)
        os = p->p_size;
    a = malloc(swapmap, (p->p_size+7)/8);
    if(a == NULL)
        panic("out of swap");
    xccdec(p->p_textp);
    swap(a, p->p_addr, os, B_WRITE);
    if(ff)
        mfree(coremap, os, p->p_addr);
    p->p_addr = a;
    p->p_flag =| SSWAP;
    p->p_flag =& ~SLOAD;
}
```

1. Allocate swap space
2. Decrement text reference count
3. Write process image to swap
4. Free core memory (if `ff` flag set)
5. Update `p_addr` to point to swap location
6. Clear SLOAD, set SSWAP flags

### Swap In

The scheduler (`sched()` in slp.c) swaps processes back in:

```c
/* From sched() */
found2:
    if((rp=p1->p_textp) != NULL) {
        if(rp->x_ccount == 0) {
            /* Swap in text if needed */
            if(swap(rp->x_daddr, a, rp->x_size, B_READ))
                goto swaper;
            rp->x_caddr = a;
            a =+ rp->x_size;
        }
        rp->x_ccount++;
    }
    rp = p1;
    if(swap(rp->p_addr, a, rp->p_size, B_READ))
        goto swaper;
    mfree(swapmap, (rp->p_size+7)/8, rp->p_addr);
    rp->p_addr = a;
    rp->p_flag =| SLOAD;
```

## expand() — Change Process Size

```c
/* slp.c */
expand(newsize)
{
    int i, n;
    register *p, a1, a2;

    p = u.u_procp;
    n = p->p_size;
    p->p_size = newsize;
    a1 = p->p_addr;

    if(n >= newsize) {
        /* Shrinking */
        mfree(coremap, n-newsize, a1+newsize);
        return;
    }
```

If shrinking, just free the excess.

```c
    /* Growing: try to allocate new space */
    savu(u.u_rsav);
    a2 = malloc(coremap, newsize);
    if(a2 == NULL) {
        /* No space: swap out, grow on swap */
        savu(u.u_ssav);
        xswap(p, 1, n);
        p->p_flag =| SSWAP;
        swtch();
        /* no return */
    }

    /* Copy to new location */
    p->p_addr = a2;
    for(i=0; i<n; i++)
        copyseg(a1+i, a2++);
    mfree(coremap, n, a1);
    retu(p->p_addr);
    sureg();
}
```

If growing:
1. Try to allocate larger region
2. If successful, copy process to new location
3. If not, swap out and let scheduler handle it

## Shared Text Segments

Executable programs with magic number `0410` have separate, read-only text segments that can be shared:

```c
/* text.h */
struct text {
    int  x_daddr;    /* Disk address of segment */
    int  x_caddr;    /* Core address (if in memory) */
    int  x_size;     /* Size in 64-byte blocks */
    int  *x_iptr;    /* Inode pointer */
    char x_count;    /* Reference count */
    char x_ccount;   /* In-core reference count */
} text[NTEXT];
```

When a process execs a shared-text program:
1. Look for existing text entry for this inode
2. If found, just increment reference count
3. If not, create new entry and load text from disk

When process exits:
1. Decrement reference counts
2. When `x_count` reaches 0, text can be freed

## Memory Limits

From `param.h`:

```c
#define MAXMEM   (32*32)   /* Max user memory: 1024 blocks = 64KB */
#define CMAPSIZ  100       /* Coremap entries */
#define SMAPSIZ  100       /* Swapmap entries */
```

The `MAXMEM` limit exists because:
- 64KB address space per process
- Kernel reserves some segments
- Practical limit on how much to allocate to one process

## Summary

- Memory is managed with a simple first-fit allocator (`malloc`/`mfree`)
- Two maps: `coremap` for physical memory, `swapmap` for swap space
- Processes are allocated contiguous memory regions
- `estabur()` sets up segment registers based on text/data/stack sizes
- `sureg()` loads segment registers into hardware
- Swapping moves entire processes between memory and disk
- Shared text segments reduce memory usage for common programs

## Key Insight: Simplicity

The UNIX v4 memory management is remarkably simple:
- No page tables
- No complex allocation algorithms
- No memory-mapped files
- Just contiguous regions, a free list, and swapping

This simplicity made UNIX portable and maintainable. The more complex virtual memory systems of later UNIX versions added capability but also complexity.

## Experiments

1. **Trace allocation**: Add printfs to `malloc()`/`mfree()` to watch memory allocation patterns.

2. **Fragmentation**: What happens to `coremap` as processes come and go? Does fragmentation occur?

3. **Swap thrashing**: What happens if memory is very tight and processes keep getting swapped in and out?

## Further Reading

- Chapter 5: Process Management — How `expand()` is used
- Chapter 8: Scheduling — How `sched()` decides what to swap
- Chapter 12: Buffer Cache — Another use of memory

---

**Next: Chapter 7 — Traps and System Calls**
