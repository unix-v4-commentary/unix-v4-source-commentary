# Chapter 2: The PDP-11 Architecture

## Overview

You cannot understand UNIX v4 without understanding the PDP-11. The hardware shapes the software at every level—from the way system calls work to why there are exactly 8 memory segments per process. This chapter covers the PDP-11 architecture as it relates to UNIX, focusing on what you need to know to read the source code.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/seg.h` | Memory management register definitions |
| `usr/sys/reg.h` | Register save area offsets |
| `usr/sys/conf/mch.s` | Machine-dependent assembly routines |
| `usr/sys/conf/low.s` | Interrupt vector table |

## Prerequisites

- Basic understanding of computer architecture (registers, memory, addresses)
- Familiarity with any assembly language (concepts transfer)

## The PDP-11 Family

The PDP-11 was Digital Equipment Corporation's most successful minicomputer line, introduced in 1970. UNIX v4 ran primarily on the **PDP-11/45**, though it supported the /40 as well.

Key characteristics:

- **16-bit architecture** — Words are 16 bits, addresses are 16 bits
- **64KB address space** — 2^16 = 65,536 bytes maximum
- **Byte-addressable** — Can access individual bytes, not just words
- **Memory-mapped I/O** — Devices accessed through memory addresses
- **Orthogonal instruction set** — Most instructions work with any addressing mode

The 64KB address space was the crucial constraint. An entire UNIX system—kernel, user processes, and I/O devices—had to fit in this space. The Memory Management Unit (MMU) made this possible by providing virtual address translation.

## Registers

The PDP-11 has eight 16-bit general-purpose registers:

```
r0      General purpose, also function return value
r1      General purpose
r2      General purpose
r3      General purpose
r4      General purpose
r5      General purpose, frame pointer by convention
r6 (sp) Stack pointer
r7 (pc) Program counter
```

All registers are equivalent for most operations, but convention and some instructions treat them specially:

- **r0** — Return value from functions; first argument in some calling conventions
- **r5** — Frame pointer by C compiler convention
- **r6/sp** — Stack pointer; push/pop operations use this implicitly
- **r7/pc** — Program counter; can be used as a general register for tricks

The register save area in the kernel (from `reg.h`) shows how registers are stored on the stack during a trap:

```c
/* reg.h - offsets from saved r0 */
#define R0   (0)
#define R1   (-2)
#define R2   (-9)
#define R3   (-8)
#define R4   (-7)
#define R5   (-6)
#define R6   (-3)
#define R7   (1)
#define RPS  (2)    /* Processor Status word */
```

## The Processor Status Word (PS)

The PS register at address `0177776` contains the processor state:

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|CM|PM|  RS |        |  IPL  | T| N| Z| V| C|
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+

CM    - Current Mode (00=kernel, 11=user)
PM    - Previous Mode
RS    - Register Set (PDP-11/45 has two register sets)
IPL   - Interrupt Priority Level (0-7)
T     - Trace bit
N,Z,V,C - Condition codes (negative, zero, overflow, carry)
```

The key fields for UNIX:

### Current/Previous Mode (bits 14-15, 12-13)

The PDP-11 has two modes:
- **Kernel mode (00)** — Full access to all memory and instructions
- **User mode (11)** — Restricted access, memory mapped through MMU

When a trap occurs, the hardware saves the current PS and sets the new mode to kernel. The **Previous Mode** field records where we came from, so we know whether to access user or kernel space.

### Interrupt Priority Level (bits 5-7)

The IPL controls which interrupts are blocked:

```c
/* From mch.s */
spl0()  /* IPL = 0, all interrupts enabled */
spl1()  /* IPL = 1, block level 0 */
spl4()  /* IPL = 4, block disk interrupts */
spl5()  /* IPL = 5, block most device interrupts */
spl6()  /* IPL = 6, block clock interrupts */
spl7()  /* IPL = 7, block all interrupts */
```

The kernel raises the IPL to protect critical sections:

```c
/* Typical pattern in the kernel */
spl6();           /* Block interrupts */
/* ... critical section ... */
spl0();           /* Re-enable interrupts */
```

## Memory Layout

With only 64KB of address space, UNIX uses the MMU to multiplex physical memory among:
- The kernel
- User processes (one at a time in memory)
- I/O device registers

### Physical Address Space

```
000000 - 157777   RAM (up to 56KB, varies by system)
160000 - 177777   I/O Page (device registers)
```

The top 8KB is always reserved for device registers, limiting usable RAM to 56KB in a basic configuration. Systems with extended memory used the MMU to access more.

### Virtual Address Space (per process)

Each process sees:

```
000000 - 017777   Segment 0 (8KB)
020000 - 037777   Segment 1 (8KB)
040000 - 057777   Segment 2 (8KB)
060000 - 077777   Segment 3 (8KB)
100000 - 117777   Segment 4 (8KB)
120000 - 137777   Segment 5 (8KB)
140000 - 157777   Segment 6 (8KB) - User structure in kernel
160000 - 177777   Segment 7 (8KB) - I/O Page
```

## The Memory Management Unit (MMU)

The MMU (KT-11 option on PDP-11/45) translates virtual addresses to physical addresses using **8 segment registers** per mode.

### Segmentation Registers

From `seg.h`:

```c
/* KT-11 registers */
#define KISA    0172340    /* Kernel I-space Address registers */
#define UISD    0177600    /* User I-space Descriptor registers */
#define UISA    0177640    /* User I-space Address registers */

#define RO      02         /* Read-only */
#define RW      06         /* Read-write */
#define WO      04         /* Write-only (not used) */
#define ED      010        /* Expand downward (for stack) */

struct { int r[8]; };      /* 8 registers per set */
```

Each segment has two registers:

**Page Address Register (PAR)** — Base physical address (in 64-byte blocks)

**Page Descriptor Register (PDR)** — Access control and length:

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|       PLF        |    |ED|ACF|  |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+

PLF - Page Length Field (in 64-byte blocks)
ED  - Expand Downward (1 for stack segments)
ACF - Access Control Field (RO=2, RW=6)
```

### Address Translation

Virtual address → Physical address:

```
Virtual: | Segment (3 bits) | Block (7 bits) | Byte (6 bits) |
         |     0-7          |    0-127       |    0-63       |

Physical = PAR[segment] * 64 + block * 64 + byte
         = (PAR[segment] + block) * 64 + byte
```

Example: Virtual address `0037777` (octal)
- Segment: `0037777 >> 13` = 0 (segment 0)
- Offset: `0037777 & 017777` = 017777 (8191 decimal)
- If PAR[0] = 0100, physical = 0100 * 64 + 8191 = 4096 + 8191 = 12287

### How UNIX Uses Segments

In UNIX v4, a typical user process layout:

```
Segment 0-2: Text (code) - Read-only, shared
Segment 3-5: Data + BSS + Heap - Read-write
Segment 6:   (not used by user)
Segment 7:   Stack - Read-write, expands downward

Kernel sees:
Segment 0-5: Kernel code and data
Segment 6:   User structure (u.) for current process
Segment 7:   I/O page
```

The function `estabur()` in `main.c` sets up user segments:

```c
estabur(nt, nd, ns)    /* text, data, stack sizes */
{
    /* Set up text segments (read-only) */
    while(nt >= 128) {
        *dp++ = (127<<8) | RO;    /* 8KB read-only */
        ...
    }

    /* Set up data segments (read-write) */
    while(nd >= 128) {
        *dp++ = (127<<8) | RW;    /* 8KB read-write */
        ...
    }

    /* Set up stack segment (expand down) */
    *--dp = ((128-ns)<<8) | RW | ED;
}
```

## Trap and Interrupt Mechanism

### Vector Table

The PDP-11 uses a **vector table** in low memory. Each vector is two words: new PC and new PS.

From `low.s`:

```assembly
. = 0^.
    br    1f        / Reset: branch to start
    4

/ trap vectors (addresses 4-36)
    trap; br7+0.    / 4: bus error
    trap; br7+1.    / 10: illegal instruction
    trap; br7+2.    / 14: BPT (breakpoint)
    trap; br7+3.    / 20: IOT trap
    trap; br7+4.    / 24: power fail
    trap; br7+5.    / 30: EMT (emulator trap)
    trap; br7+6.    / 34: TRAP (system call!)
```

When a trap occurs:
1. Hardware pushes PC and PS onto the kernel stack
2. Hardware loads new PC and PS from the vector
3. Execution continues at the new PC (the `trap` routine)

### The System Call Trap

UNIX uses the **TRAP** instruction (vector at address 034) for system calls:

```assembly
/ User code to make a system call
sys  write        / This is really: trap #4
```

The trap handler (`trap` in `mch.s`) saves registers and calls the C function `_trap()`:

```assembly
trap:
    mov  PS,-4(sp)
    ...
    jsr  r0,call1; _trap    / Call C trap handler
```

### Interrupt Handling

Device interrupts work similarly but have their own vectors:

```assembly
. = 60^.
    klin; br4       / Console keyboard input, priority 4
    klou; br4       / Console keyboard output

. = 100^.
    kwlp; br6       / Clock interrupt, priority 6

. = 220^.
    rkio; br5       / RK disk interrupt, priority 5
```

Each device interrupt calls a C function:

```assembly
klin:  jsr  r0,call; _klrint   / Call klrint() in C
kwlp:  jsr  r0,call; _clock    / Call clock() in C
rkio:  jsr  r0,call; _rkintr   / Call rkintr() in C
```

## Key Machine Instructions

### Data Movement

```assembly
mov   src,dst     / Move word
movb  src,dst     / Move byte
clr   dst         / Clear (set to 0)
```

### Arithmetic

```assembly
add   src,dst     / dst = dst + src
sub   src,dst     / dst = dst - src
inc   dst         / dst++
dec   dst         / dst--
cmp   src,dst     / Compare (set condition codes)
tst   src         / Test (compare with 0)
```

### Logical

```assembly
bic   src,dst     / Bit clear: dst &= ~src
bis   src,dst     / Bit set: dst |= src
bit   src,dst     / Bit test: src & dst (set flags only)
```

### Branching

```assembly
br    addr        / Branch always
beq   addr        / Branch if equal (Z=1)
bne   addr        / Branch if not equal (Z=0)
bge   addr        / Branch if >= (signed)
blt   addr        / Branch if < (signed)
bhi   addr        / Branch if > (unsigned)
blos  addr        / Branch if <= (unsigned)
```

### Subroutines

```assembly
jsr   r5,addr     / Jump to subroutine, save return in r5
                  / Actually: push r5, r5=pc, pc=addr
rts   r5          / Return: pc=r5, pop r5
```

### Stack Operations

```assembly
mov   r0,-(sp)    / Push r0
mov   (sp)+,r0    / Pop into r0
```

### Special

```assembly
sys   n           / System call (trap instruction)
rti               / Return from interrupt
wait              / Wait for interrupt
reset             / Reset all devices
```

## Addressing Modes

The PDP-11's power comes from its **orthogonal addressing modes**. Any instruction can use any mode for source and destination:

| Mode | Syntax | Name | Meaning |
|------|--------|------|---------|
| 0 | Rn | Register | Use register directly |
| 1 | (Rn) | Deferred | Memory at address in Rn |
| 2 | (Rn)+ | Autoincrement | Use (Rn), then Rn += 2 |
| 3 | @(Rn)+ | Autoincr Deferred | Pointer at (Rn), then Rn += 2 |
| 4 | -(Rn) | Autodecrement | Rn -= 2, then use (Rn) |
| 5 | @-(Rn) | Autodecr Deferred | Rn -= 2, use pointer at (Rn) |
| 6 | X(Rn) | Index | Memory at Rn + X |
| 7 | @X(Rn) | Index Deferred | Pointer at Rn + X |

Since PC is r7, modes 2, 3, 6, 7 with PC create additional modes:

| Mode | Syntax | Name | Meaning |
|------|--------|------|---------|
| 27 | #n | Immediate | Literal value n |
| 37 | @#addr | Absolute | Memory at address |
| 67 | addr | Relative | Memory at PC + offset |
| 77 | @addr | Relative Deferred | Pointer at PC + offset |

Examples from UNIX source:

```assembly
mov   r0,r1           / Register to register
mov   (r0),r1         / Memory[r0] to r1
mov   (r0)+,r1        / Memory[r0] to r1, r0 += 2
mov   -(sp),r0        / Push r0 onto stack
mov   (sp)+,r0        / Pop stack into r0
mov   4(sp),r0        / Stack[sp+4] to r0
mov   $100,r0         / Immediate 100 to r0
mov   _variable,r0    / Global variable to r0
```

## The User Structure Address

A critical constant in UNIX:

```assembly
/ From mch.s
_u    = 140000
```

The user structure (`u.`) is always mapped at virtual address `0140000` (octal) in the kernel. This is segment 6 of kernel space. When the kernel switches processes, it changes the segment 6 mapping to point to the new process's user structure.

This allows code like:

```c
u.u_error = EINVAL;    /* Always refers to current process */
```

## Key Machine-Dependent Functions

From `mch.s`, functions the kernel calls:

### Save and Restore Context

```c
savu(u.u_rsav)    /* Save sp and r5 */
retu(addr)        /* Restore sp and r5, change segment 6 */
aretu(u.u_qsav)   /* Restore for signal/longjmp */
```

### Memory Access

```c
fubyte(addr)      /* Fetch byte from user space */
fuword(addr)      /* Fetch word from user space */
subyte(addr, v)   /* Store byte to user space */
suword(addr, v)   /* Store word to user space */
```

### Memory Operations

```c
copyin(src, dst, n)   /* Copy from user to kernel */
copyout(src, dst, n)  /* Copy from kernel to user */
copyseg(src, dst)     /* Copy 64-byte segment */
clearseg(seg)         /* Zero a 64-byte segment */
```

### Interrupt Priority

```c
spl0()    /* Enable all interrupts */
spl5()    /* Block most device interrupts */
spl6()    /* Block clock */
spl7()    /* Block all interrupts */
```

## Summary

- The PDP-11 is a 16-bit architecture with 64KB address space
- 8 general-purpose registers (r0-r7), with r6=sp and r7=pc
- The PS register controls mode (kernel/user) and interrupt priority
- The MMU provides 8 segments per mode, each up to 8KB
- UNIX uses segments for text, data, stack, user structure, and I/O
- Traps and interrupts use a vector table at low memory
- The orthogonal instruction set allows any addressing mode with any instruction
- Machine-dependent assembly in `mch.s` provides context switch and memory access primitives

## Experiments

1. **Examine vectors**: In the source, trace what happens when a bus error (vector 4) occurs vs. a system call (vector 034).

2. **Segment calculation**: Given a user program with 4KB text, 2KB data, and 1KB stack, calculate what values `estabur()` would put in the segment registers.

3. **Mode tracing**: Follow the PS word through a system call: What mode are we in at each step?

## Further Reading

- PDP-11 Processor Handbook, Digital Equipment Corporation
- Chapter 4: Boot Sequence — See how the MMU is initialized
- Chapter 7: Traps and System Calls — Detailed walkthrough of trap handling

---

**Next: Chapter 3 — Building the System**
