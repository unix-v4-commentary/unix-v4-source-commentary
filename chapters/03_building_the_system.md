# Chapter 3: Building the System

## Overview

This chapter explains how UNIX v4 is compiled and linked into a bootable kernel. Understanding the build process reveals the structure of the system—which pieces are written in C, which require assembly, and how device drivers are configured. It also introduces the toolchain that UNIX uses to build itself.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/conf/mkconf.c` | Configuration generator |
| `usr/sys/conf/rc` | Build script |
| `usr/sys/conf/mch.s` | Machine-dependent assembly |
| `usr/sys/conf/low.s` | Generated interrupt vectors |
| `usr/sys/lib1` | Ken's compiled kernel objects |
| `usr/sys/lib2` | DMR's compiled driver objects |
| `lib/c0`, `lib/c1` | C compiler passes |
| `lib/crt0.o` | C runtime startup |
| `lib/libc.a` | C library |
| `bin/as` | Assembler |
| `bin/ld` | Linker |

## Prerequisites

- Chapter 2: PDP-11 Architecture (understanding of address space and segments)

## The UNIX Toolchain

UNIX v4 includes a complete, self-hosting toolchain:

### The C Compiler

The C compiler is a **two-pass** system:

```
source.c -> [c0] -> intermediate -> [c1] -> source.s
```

- **c0** (`lib/c0`) — Lexer and parser; produces intermediate code
- **c1** (`lib/c1`) — Code generator; produces PDP-11 assembly
- **c2** (`lib/c2`, optional) — Peephole optimizer

The `cc` command orchestrates these passes:

```
cc source.c
```

This runs:

1. `c0 source.c /tmp/ctm1` — Parse, produce intermediate
2. `c1 /tmp/ctm1 /tmp/ctm2` — Generate assembly
3. `as /tmp/ctm2` — Assemble to object
4. `ld crt0.o source.o -lc` — Link with runtime and library

### The Assembler

The assembler (`as`) translates PDP-11 assembly into object files:

```
as source.s        # Produces a.out
as -o output.o source.s
```

The assembler is itself written in assembly (`usr/source/s1/as*.s`)—a remarkable piece of bootstrapping.

### The Linker

The linker (`ld`) combines object files and resolves symbols:

```
ld -x file1.o file2.o -lc    # -x strips local symbols
```

The linker produces **a.out** format executables:

```
a.out header:
    magic number (0407, 0410, 0411)
    text size
    data size
    bss size
    symbol table size
    entry point
    unused
    relocation suppression flag
```

## Building the Kernel

The kernel build process has three main steps:

1. Configure devices (generate `l.s` and `c.c`)
2. Assemble machine-dependent code
3. Link everything together

### Directory Structure

```
usr/sys/
├── ken/          # Thompson's C source
├── dmr/          # Ritchie's C source
├── conf/         # Configuration
│   ├── mkconf.c  # Config generator source
│   ├── mkconf    # Config generator binary
│   ├── mch.s     # Machine code
│   └── rc        # Build script
├── lib1          # Compiled ken/*.c
├── lib2          # Compiled dmr/*.c
└── *.h           # Header files
```

### Step 1: Configure Devices

The `mkconf` program generates device configuration. You run it interactively:

```
$ mkconf
rk        # Include RK05 disk driver
tm        # Include TM11 tape driver
console   # Console (required, always present)
mem       # Memory device
clock     # System clock (required)
^D        # End of input
```

`mkconf` produces two files:

**l.s** — Interrupt vector table:

```assembly
/ low core
br4 = 200
br5 = 240
br6 = 300
br7 = 340

. = 0^.
    br   1f
    4

/ trap vectors
    trap; br7+0.     / bus error
    trap; br7+1.     / illegal instruction
    trap; br7+2.     / bpt-trace trap
    trap; br7+3.     / iot trap
    trap; br7+4.     / power fail
    trap; br7+5.     / emulator trap
    trap; br7+6.     / system entry (system call!)

. = 40^.
.globl  start
1:  jmp  start

. = 60^.
    klin; br4        / console input
    klou; br4        / console output

. = 100^.
    kwlp; br6        / clock interrupt
    kwlp; br6

. = 220^.
    rkio; br5        / RK disk interrupt

/ interface code to C
.globl  call, trap
.globl  _klrint
klin:   jsr  r0,call; _klrint
.globl  _klxint
klou:   jsr  r0,call; _klxint
.globl  _clock
kwlp:   jsr  r0,call; _clock
.globl  _rkintr
rkio:   jsr  r0,call; _rkintr
```

**c.c** — Device switch tables:

```c
/*
 * Copyright 1974 Bell Telephone Laboratories Inc
 */

int (*bdevsw[])()       /* Block device switch */
{
    &nulldev, &nulldev, &rkstrategy, &rktab,
    0
};

int (*cdevsw[])()       /* Character device switch */
{
    &klopen,  &klclose,  &klread,  &klwrite,  &klsgtty,
    &nulldev, &nulldev,  &mmread,  &mmwrite,  &nodev,
    &nulldev, &nulldev,  &rkread,  &rkwrite,  &nodev,
    0
};

int rootdev  {(0<<8)|0};   /* Root device: rk0 */
int swapdev  {(0<<8)|0};   /* Swap device: rk0 */
int swplo    4000;         /* Swap starting block */
int nswap    872;          /* Swap size in blocks */
```

### mkconf Internals

Looking at `mkconf.c`, we see how it works:

```c
struct tab {
    char *name;        /* Device name */
    int count;         /* Number configured */
    int address;       /* Interrupt vector address */
    int key;           /* CHAR, BLOCK, INTR flags */
    char *codea;       /* Vector table code */
    char *codeb;       /* Interrupt glue (part 1) */
    char *codec;       /* Interrupt glue (part 2) */
    char *coded;       /* Block switch entry */
    char *codee;       /* Char switch entry */
} table[] {
    "console",
    -1, 60, CHAR+INTR,
    "\tklin; br4\n\tklou; br4\n",
    ".globl\t_klrint\nklin:\tjsr\tr0,call; _klrint\n",
    ".globl\t_klxint\nklou:\tjsr\tr0,call; _klxint\n",
    "",
    "\t&klopen, &klclose, &klread, &klwrite, &klsgtty,",

    "rk",
    0, 220, BLOCK+CHAR+INTR,
    "\trkio; br5\n",
    ".globl\t_rkintr\n",
    "rkio:\tjsr\tr0,call; _rkintr\n",
    "\t&nulldev,\t&nulldev,\t&rkstrategy,\t&rktab,",
    "\t&nulldev, &nulldev, &rkread, &rkwrite, &nodev,",
    ...
};
```

The device table encodes everything needed to generate both assembly and C code for each device.

### Step 2: Build Script

The `rc` build script ties everything together:

```sh
if ! -r l.s -o ! -r c.c goto bad
as l.s                    # Assemble interrupt vectors
mv a.out ../low.o
as mch.s                  # Assemble machine code
mv a.out ../mch.o
cc -c c.c                 # Compile configuration
mv c.o ../conf.o
mv l.s low.s
mv c.c conf.c
ld -x ../low.o ../mch.o ../conf.o ../lib1 ../lib2
mv a.out ../../../unix    # Final kernel
chmod 644 low.s conf.c ../low.o ../mch.o ../conf.o ../../../unix
echo rm mkconf.c and rc when done
exit
: bad
echo l.s or c.c not found
```

### Step 3: Understanding lib1 and lib2

The kernel C code is pre-compiled into two libraries:

**lib1** (~47KB) — Ken Thompson's kernel code:

- `main.c` — Kernel initialization
- `slp.c` — Scheduler, context switch
- `trap.c` — Trap handler
- `sys1.c` - `sys4.c` — System calls
- `fio.c`, `rdwri.c` — File I/O
- `iget.c`, `nami.c` — Inode operations
- `alloc.c` — Block allocation
- `clock.c` — Clock handler
- `sig.c` — Signals
- And more...

**lib2** (~40KB) — Dennis Ritchie's driver code:

- `bio.c` — Buffer cache
- `tty.c` — Terminal handling
- `kl.c` — Console driver
- `rk.c` — RK05 disk driver
- `malloc.c` — Memory allocation
- `mem.c` — Memory device
- And device drivers...

### The Link Order Matters

```
ld -x ../low.o ../mch.o ../conf.o ../lib1 ../lib2
```

- `low.o` — Must be first (contains vectors at address 0)
- `mch.o` — Machine code, includes `start:` entry point
- `conf.o` — Device configuration
- `lib1` — Core kernel
- `lib2` — Drivers (depend on kernel functions)

## The Boot Process Overview

When the kernel is loaded:

1. **Bootstrap loader** reads kernel from disk into memory
2. Execution starts at `start:` in `mch.s`
3. `start:` initializes the MMU segments
4. `start:` calls `main()` in C
5. `main()` initializes memory, creates process 0 and 1
6. Process 1 execs `/etc/init`

From `mch.s`:

```assembly
.globl  start, _end, _edata, _main
start:
    bit  $1,SSR0
    bne  start           / loop if restart
    reset

/ initialize system segments
    mov  $KISA0,r0
    mov  $KISD0,r1
    mov  $200,r4
    clr  r2
    mov  $6,r3
1:
    mov  r2,(r0)+
    mov  $77406,(r1)+    / 4k rw
    add  r4,r2
    sob  r3,1b

/ initialize user segment (segment 6)
    mov  $_end+63.,r2
    ash  $-6,r2
    bic  $!1777,r2
    mov  r2,(r0)+        / ksr6 = sysu
    mov  $usize-1\<8|6,(r1)+

/ initialize io segment (segment 7)
    mov  $7600,(r0)+     / ksr7 = IO
    mov  $77406,(r1)+    / rw 4k

/ get a sp and start segmentation
    mov  $_u+[usize*64.],sp
    inc  SSR0            / Enable MMU!

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

/ set up previous mode and call main
    mov  $30000,PS
    jsr  pc,_main

/ on return, enter user mode at 0
    mov  $170000,-(sp)
    clr  -(sp)
    rti
```

## Compiling User Programs

User programs use the standard toolchain:

```sh
cc program.c           # Compile and link
cc -c module.c         # Compile only
cc -o prog a.o b.o -lc # Link with C library
```

The C library (`lib/libc.a`) provides:

- System call wrappers (`open`, `read`, `write`, etc.)
- String functions (`strlen`, `strcmp`, etc.)
- I/O functions (`printf`, `getchar`, etc.)
- Memory functions (`alloc`, etc.)

The C runtime (`lib/crt0.o`) provides the entry point that calls `main()` and exits properly.

## Rebuilding the Kernel

To modify and rebuild the kernel:

1. **Edit source files** in `ken/` or `dmr/`

2. **Recompile changed files**:
   ```sh
   cc -c -O slp.c    # Compile with optimization
   ```

3. **Update the library**:
   ```sh
   ar r ../lib1 slp.o
   ```

4. **Reconfigure if devices changed**:
   ```sh
   chdir ../conf
   mkconf < config   # config file has device list
   ```

5. **Relink**:
   ```sh
   sh rc
   ```

6. **Install new kernel**:
   ```sh
   cp /unix /ounix       # Save old kernel
   cp unix /unix         # Install new
   sync
   ```

7. **Reboot** to test the new kernel

## The Complete Picture

```
Source Files:
ken/*.c, dmr/*.c --> [cc] --> lib1, lib2 (pre-compiled)

Configuration:
mkconf --> l.s (vectors)
       --> c.c (device switches)

Assembly:
mch.s --> [as] --> mch.o
l.s   --> [as] --> low.o

Compilation:
c.c --> [cc] --> conf.o

Linking:
low.o + mch.o + conf.o + lib1 + lib2 --> [ld] --> unix

Boot:
bootstrap --> load unix --> start: --> main() --> init
```

## Summary

- The UNIX kernel is built from pre-compiled libraries plus generated configuration
- `mkconf` generates interrupt vectors (`l.s`) and device switch tables (`c.c`)
- The toolchain (cc, as, ld) is self-hosting—UNIX builds itself
- Machine-dependent code in `mch.s` initializes the MMU and calls `main()`
- The link order places interrupt vectors at address 0
- Modifying the kernel requires recompiling, updating libraries, and relinking

## Experiments

1. **Trace mkconf**: Read through `mkconf.c` and trace what happens when you add an "rk" device. What code gets generated?

2. **Examine a.out**: Use `nm` and `size` on the unix binary to see symbol layout and section sizes.

3. **Startup sequence**: Follow the code path from `start:` in `mch.s` to `main()` in `main.c`. What must happen before C code can run?

## Further Reading

- Chapter 4: Boot Sequence — Detailed walkthrough of `main()`
- Chapter 18: The C Compiler — How cc, c0, c1 work
- Chapter 19: The Assembler — The as implementation

---

**Next: Part II — The Kernel**

**Chapter 4: Boot Sequence**
