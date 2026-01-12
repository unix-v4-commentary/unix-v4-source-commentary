# Chapter 4: Boot Sequence

## Overview

This chapter traces the path from power-on to a running UNIX system. We follow the code from the hardware reset through `main()`, watching as the kernel discovers memory, creates the first processes, and hands control to `/etc/init`. By the end, you'll understand how UNIX bootstraps itself from nothing.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/conf/mch.s` | `start:` entry point, MMU setup |
| `usr/sys/ken/main.c` | `main()`, memory init, process 0 & 1 |
| `usr/sys/ken/slp.c` | `newproc()`, `sched()` |
| `usr/sys/systm.h` | Global variables |
| `usr/sys/param.h` | System constants |

## Prerequisites

- Chapter 2: PDP-11 Architecture (MMU, segments, traps)
- Chapter 3: Building the System (kernel structure)

## The Bootstrap Process

Before `main()` can run, several things must happen:

```
Power On
    ↓
Bootstrap loader (in ROM or toggled in)
    ↓
Load kernel from disk to memory
    ↓
Jump to start: (in mch.s)
    ↓
Initialize MMU segments
    ↓
Enable memory management
    ↓
Clear BSS and user area
    ↓
Call main()
```

### The start: Entry Point

From `mch.s`, the first kernel code to execute:

```assembly
.globl  start, _end, _edata, _main
start:
    bit  $1,SSR0
    bne  start           / Loop if MMU already on (restart)
    reset                / Reset all devices
```

The first instruction checks if the MMU is already enabled—if so, this is a restart after a crash, and we loop forever (a deliberate hang to allow debugging).

### Initialize Kernel Segments

```assembly
/ initialize system segments
    mov  $KISA0,r0       / Kernel segment address registers
    mov  $KISD0,r1       / Kernel segment descriptor registers
    mov  $200,r4         / 8KB in 64-byte blocks
    clr  r2              / Start at physical 0
    mov  $6,r3           / 6 segments
1:
    mov  r2,(r0)+        / Set segment base address
    mov  $77406,(r1)+    / 4KB read-write
    add  r4,r2           / Next 8KB block
    sob  r3,1b           / Loop 6 times
```

This creates identity mapping for the first 48KB: virtual address X maps to physical address X. Segment descriptors `077406` means:
- Length = 127 blocks (8KB)
- Access = read-write

### Initialize User Segment (Segment 6)

```assembly
/ initialize user segment
    mov  $_end+63.,r2    / End of kernel + round up
    ash  $-6,r2          / Convert to 64-byte blocks
    bic  $!1777,r2       / Mask to valid range
    mov  r2,(r0)+        / ksr6 = address of u.
    mov  $usize-1\<8|6,(r1)+   / 16 blocks, read-write
```

Segment 6 holds the **user structure** (`u.`)—the per-process kernel data. It's placed just after the kernel's BSS.

### Initialize I/O Segment (Segment 7)

```assembly
/ initialize io segment
    mov  $7600,(r0)+     / ksr7 = 0760000 (I/O page)
    mov  $77406,(r1)+    / 4KB read-write
```

Segment 7 maps the I/O page where device registers live.

### Enable Memory Management

```assembly
/ get a sp and start segmentation
    mov  $_u+[usize*64.],sp    / Stack at top of u.
    inc  SSR0                   / Enable MMU!
```

The stack pointer is set to the top of the user structure, then `inc SSR0` turns on the MMU. From this point, all memory accesses go through address translation.

### Clear BSS and User Area

```assembly
/ clear bss
    mov  $_edata,r0
1:
    clr  (r0)+
    cmp  r0,$_end
    blo  1b

/ clear user block
    mov  $_u,r0
1:
    clr  (r0)+
    cmp  r0,$_u+[usize*64.]
    blo  1b
```

The BSS (uninitialized data) and user structure are zeroed. This is essential—C assumes uninitialized globals are zero.

### Enter C Code

```assembly
/ set up previous mode and call main
    mov  $30000,PS       / Previous mode = user
    jsr  pc,_main        / Call main()

/ on return, enter user mode at 0
    mov  $170000,-(sp)   / PS: user mode, IPL 0
    clr  -(sp)           / PC: address 0
    rti                  / "Return" to user mode
```

The previous mode is set to user (for later `mfpi`/`mtpi` instructions), then `main()` is called. When `main()` returns (in the child process), `rti` "returns" to user mode at address 0, executing the init code.

## The main() Function

Now we enter C code. Let's walk through `main()` section by section.

### Header and Data

```c
#include "../param.h"
#include "../user.h"
#include "../systm.h"
#include "../proc.h"
#include "../text.h"
#include "../inode.h"
#include "../seg.h"

int lksp[]
{
    0177546,    /* KW11-L clock */
    0172540,    /* KW11-P clock */
    0           /* End marker */
};
```

`lksp` is a list of possible clock device addresses. UNIX probes each to find which clock is present.

### The icode Array

```c
int icode[]
{
    0104413,    /* sys exec */
    0000014,    /* address of "/etc/init" */
    0000010,    /* address of argv */
    0000777,    /* (unused) */
    0000014,    /* argv[0] = "/etc/init" */
    0000000,    /* argv[1] = NULL */
    0062457,    /* "/et" */
    0061564,    /* "c/" */
    0064457,    /* "in" */
    0064556,    /* "it" */
    0000164,    /* "\0" (null terminator) */
};
```

This is machine code! It's the first program that process 1 executes:

```assembly
    sys exec           / System call: exec
    "/etc/init"        / Path argument
    argv               / Argument vector
```

Disassembled:
- `0104413` = `sys` instruction (exec is syscall 11, octal 013)
- The rest are the arguments: path string and argv pointers

This is how UNIX bootstraps user space—by hardcoding the first `exec()` call in machine language.

### Memory Discovery

```c
main()
{
    extern schar;
    register i1, *p;

    /*
     * zero and free all of core
     */
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

This discovers how much RAM the system has:

1. **Set up a probe segment** — UISA[0] points past the kernel, UISD[0] allows access
2. **Loop probing memory** — `fubyte(0)` tries to read address 0 of the current segment
3. **If successful** — Memory exists; clear it and add to free list
4. **If fails** — We've hit non-existent memory; stop

The `mfree()` calls add each 64-byte block to `coremap` (free memory list).

After the loop, `maxmem` contains the total memory in 64-byte blocks. The conversion `maxmem*10/32` prints kilobytes (64 bytes × 10/32 = 20 bytes... actually this prints in some odd unit).

Finally, swap space is added to `swapmap`.

### Clock Detection

```c
    /*
     * determine clock
     */
    UISA->r[7] = KISA->r[7];
    UISD->r[7] = 077406;
    for(p=lksp;; p++) {
        if(*p == 0)
            panic("no clock");
        if(fuword(*p) != -1) {
            lks = *p;
            break;
        }
    }
```

UNIX needs a clock for timekeeping and scheduling. This code:

1. Maps segment 7 to the I/O page
2. Probes each possible clock address
3. If `fuword()` succeeds (returns != -1), the clock exists
4. Saves the clock address in `lks`
5. If no clock found, `panic("no clock")` halts the system

### Process 0 Setup

```c
    /*
     * set up system process
     */
    proc[0].p_addr = KISA->r[6];
    proc[0].p_size = USIZE;
    proc[0].p_stat = SRUN;
    proc[0].p_flag =| SLOAD|SSYS;
    u.u_procp = &proc[0];
```

Process 0 is the **swapper** (scheduler). It's special:
- `p_addr` — Points to the user structure (segment 6)
- `p_size` — USIZE (16) blocks = 1024 bytes
- `p_stat` — SRUN (runnable)
- `p_flag` — SLOAD (in memory) | SSYS (system process)

The user structure pointer `u.u_procp` is set to point back to proc[0].

### Subsystem Initialization

```c
    /*
     * set up 'known' i-nodes
     */
    sureg();
    *lks = 0115;
    cinit();
    binit();
    iinit();
    rootdir = iget(rootdev, ROOTINO);
    rootdir->i_flag =& ~ILOCK;
    u.u_cdir = iget(rootdev, ROOTINO);
    u.u_cdir->i_flag =& ~ILOCK;
```

Now the kernel initializes its subsystems:

| Call | Purpose |
|------|---------|
| `sureg()` | Set up segment registers from u.u_uisa/u.u_uisd |
| `*lks = 0115` | Start the clock (magic value enables interrupts) |
| `cinit()` | Initialize character buffer freelists |
| `binit()` | Initialize buffer cache |
| `iinit()` | Read superblock, initialize inode table |
| `iget(rootdev, ROOTINO)` | Get root directory inode |

The root directory inode is retrieved twice:
- `rootdir` — Global pointer used by `namei()`
- `u.u_cdir` — Process 0's current directory

Both have `ILOCK` cleared so they can be used immediately.

### Creating Process 1 (init)

```c
    /*
     * make init process
     * enter scheduling loop
     * with system process
     */
    if(newproc()) {
        expand(USIZE+1);
        u.u_uisa[0] = USIZE;
        u.u_uisd[0] = 6;
        sureg();
        copyout(icode, 0, 30);
        return;
    }
    sched();
}
```

This is the magic moment—creating the first user process:

**In the parent (process 0):**
- `newproc()` creates process 1 and returns 0
- Falls through to `sched()`, entering the scheduler loop forever

**In the child (process 1):**
- `newproc()` returns 1 (non-zero)
- `expand(USIZE+1)` — Grow to 17 blocks (1 block for user code)
- Set up segment 0 to map user memory
- `copyout(icode, 0, 30)` — Copy the init code to user address 0
- `return` — Returns from main(), hitting the `rti` in mch.s

The `rti` at the end of `start:` pops a user-mode PS and PC=0, causing process 1 to start executing `icode` at address 0. This code does `exec("/etc/init", ...)`, replacing itself with the init program.

## The sureg() Function

```c
sureg()
{
    register *up, *rp, a;

    a = u.u_procp->p_addr;
    up = &u.u_uisa[0];
    rp = &UISA->r[0];
    while(rp < &UISA->r[8])
        *rp++ = *up++ + a;
```

`sureg()` copies the segment register values from the user structure to the actual hardware registers, adjusting by the process's physical base address.

The user structure stores *relative* segment addresses (relative to the process's memory). `sureg()` converts these to *absolute* physical addresses by adding `p_addr`.

## The estabur() Function

```c
estabur(nt, nd, ns)    /* text, data, stack sizes (in 64-byte blocks) */
{
    register a, *ap, *dp;

    /* Check if it fits */
    if(nseg(nt)+nseg(nd)+nseg(ns) > 8 || nt+nd+ns+USIZE > maxmem) {
        u.u_error = ENOMEM;
        return(-1);
    }
```

`estabur()` (establish user registers) sets up the memory map for a process. It takes three sizes in 64-byte blocks:
- `nt` — Text (code) size
- `nd` — Data size
- `ns` — Stack size

First it checks:
1. Total segments needed ≤ 8
2. Total memory needed ≤ available

```c
    /* Set up text segments (read-only) */
    a = 0;
    ap = &u.u_uisa[0];
    dp = &u.u_uisd[0];
    while(nt >= 128) {          /* Full 8KB segments */
        *dp++ = (127<<8) | RO;  /* Max length, read-only */
        *ap++ = a;
        a =+ 128;
        nt =- 128;
    }
    if(nt) {                    /* Partial segment */
        *dp++ = ((nt-1)<<8) | RO;
        *ap++ = a;
        a =+ nt;
    }
```

Text segments are read-only (RO). Each full segment is 128 blocks (8KB).

```c
    /* Set up data segments (read-write) */
    a = USIZE;                  /* Data starts after user struct */
    while(nd >= 128) {
        *dp++ = (127<<8) | RW;
        *ap++ = a;
        a =+ 128;
        nd =- 128;
    }
    if(nd) {
        *dp++ = ((nd-1)<<8) | RW;
        *ap++ = a;
        a =+ nd;
    }
```

Data segments are read-write (RW), starting at offset USIZE (after the user structure).

```c
    /* Clear unused middle segments */
    while(ap < &u.u_uisa[8]) {
        *dp++ = 0;
        *ap++ = 0;
    }

    /* Set up stack (grows downward from top) */
    a =+ ns;
    while(ns >= 128) {
        a =- 128;
        ns =- 128;
        *--dp = (127<<8) | RW;
        *--ap = a;
    }
    if(ns) {
        *--dp = ((128-ns)<<8) | RW | ED;  /* ED = expand down */
        *--ap = a-128;
    }
    sureg();
    return(0);
}
```

The stack is set up from the top of the address space, growing downward. The `ED` (expand down) bit tells the MMU that valid addresses are at the *top* of the segment.

## Key Data Structures

### Global Variables (systm.h)

```c
int  coremap[CMAPSIZ];   /* Free memory map */
int  swapmap[SMAPSIZ];   /* Free swap map */
int  *rootdir;           /* Root directory inode */
int  time[2];            /* System time */
int  maxmem;             /* Max memory available */
int  *lks;               /* Clock address */
int  rootdev;            /* Root device number */
int  swapdev;            /* Swap device number */
int  swplo;              /* Swap starting block */
int  nswap;              /* Swap size */
char runrun;             /* Reschedule flag */
```

### Process Table Entry (proc.h)

```c
struct proc {
    char p_stat;     /* Process state */
    char p_flag;     /* Flags */
    char p_pri;      /* Priority */
    char p_sig;      /* Pending signal */
    char p_time;     /* Time in memory/swap */
    int  p_ttyp;     /* Controlling terminal */
    int  p_pid;      /* Process ID */
    int  p_ppid;     /* Parent process ID */
    int  p_addr;     /* Address of user struct */
    int  p_size;     /* Size in blocks */
    int  p_wchan;    /* Wait channel */
    int  *p_textp;   /* Text segment pointer */
};
```

## Boot Timeline

```
t=0     Power on, bootstrap runs
t=?     Kernel loaded, start: executes
        - MMU initialized
        - Segments set up
        - BSS cleared
        - main() called

t=?     main() runs
        - Memory discovered
        - Clock found
        - Process 0 created
        - cinit(), binit(), iinit()
        - Root filesystem mounted
        - Process 1 forked

t=?     Process 0: enters sched()
        Process 1: returns from main()
                   rti to user mode
                   executes icode
                   exec("/etc/init")

t=?     /etc/init runs
        - Opens console
        - Spawns getty on terminals
        - System ready for login
```

## Summary

- The bootstrap loads the kernel and jumps to `start:`
- `start:` in mch.s initializes the MMU and calls `main()`
- `main()` discovers memory by probing with `fubyte()`
- Process 0 (swapper) is created by filling in `proc[0]`
- Subsystems are initialized: buffers, inodes, root filesystem
- Process 1 is forked and runs `icode`, which execs `/etc/init`
- Process 0 enters `sched()` and never returns
- Process 1 becomes `/etc/init`, the ancestor of all user processes

## Experiments

1. **Trace memory discovery**: Add a printf inside the memory probe loop to see each block being found.

2. **Decode icode**: Disassemble the `icode` array by hand. Verify it does `exec("/etc/init", argv)`.

3. **Boot without clock**: What happens if you remove clock detection? (Hint: `panic`)

## Further Reading

- Chapter 5: Process Management — How `newproc()` works
- Chapter 8: Scheduling — The `sched()` function
- Chapter 9: Inodes and Superblock — What `iinit()` does

---

**Next: Chapter 5 — Process Management**
