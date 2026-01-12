# Chapter 7: Traps and System Calls

## Overview

System calls are how user programs request kernel services. This chapter traces the complete path of a system call—from the user's `sys` instruction through the trap handler to the kernel function and back. Understanding this mechanism is key to understanding the user/kernel interface.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/ken/trap.c` | Trap handler |
| `usr/sys/ken/sysent.c` | System call table |
| `usr/sys/conf/mch.s` | Assembly trap entry |
| `usr/sys/conf/low.s` | Interrupt vectors |
| `usr/sys/reg.h` | Register offsets |

## Prerequisites

- Chapter 2: PDP-11 Architecture (traps, PS word)
- Chapter 5: Process Management (process structure)

## The Trap Mechanism

When a PDP-11 executes a `trap` instruction (or encounters an error), the hardware:

1. Pushes the current PS onto the kernel stack
2. Pushes the current PC onto the kernel stack
3. Loads new PS and PC from the trap vector
4. Execution continues at the new PC (in kernel mode)

### Trap Vectors

From `low.s`:

```assembly
. = 0^.
    br   1f
    4

/ trap vectors
    trap; br7+0.     / 4: bus error
    trap; br7+1.     / 10: illegal instruction
    trap; br7+2.     / 14: BPT (breakpoint)
    trap; br7+3.     / 20: IOT trap
    trap; br7+4.     / 24: power fail
    trap; br7+5.     / 30: EMT (emulator trap)
    trap; br7+6.     / 34: system call (TRAP instruction)
```

Each vector is two words:
- New PC: `trap` (the assembly routine)
- New PS: `br7+N` where N identifies the trap type

The `br7` (octal 340) sets IPL to 7 (block all interrupts) and kernel mode.

### Trap Types

| Vector | dev | Cause |
|--------|-----|-------|
| 4 | 0 | Bus error (invalid address) |
| 10 | 1 | Illegal instruction |
| 14 | 2 | BPT (breakpoint trap) |
| 20 | 3 | IOT trap |
| 24 | 4 | Power fail |
| 30 | 5 | EMT (emulator trap) |
| 34 | 6 | **TRAP (system call)** |
| 240 | 7 | Programmed interrupt |
| 244 | 8 | Floating point exception |
| 250 | 9 | Segmentation violation |

## Assembly Entry Point

From `mch.s`, the `trap` routine:

```assembly
trap:
    mov  PS,-4(sp)        / Save PS in unused stack slot
    tst  nofault
    bne  1f               / If nofault set, handle specially
    mov  SSR0,ssr         / Save MMU status registers
    mov  SSR2,ssr+4
    mov  $1,SSR0          / Re-enable MMU
    jsr  r0,call1; _trap  / Call C trap handler
1:
    mov  $1,SSR0
    mov  nofault,(sp)
    rti
```

The key line is `jsr r0,call1; _trap` which calls the C `trap()` function.

### The call1 Routine

```assembly
call1:
    tst  -(sp)            / Make room on stack
    spl  0                / Enable interrupts
    br   1f               / Fall into call

call:
    mov  PS,-(sp)         / Save PS
1:
    mov  r1,-(sp)         / Save r1
    mfpi sp               / Get user SP
    mov  4(sp),-(sp)      / Push dev number
    ...
    jsr  pc,*(r0)+        / Call the C function
    ...
    rti                   / Return from interrupt
```

This saves registers and calls the C function with arguments set up properly.

## The trap() Function

```c
/* trap.c */
trap(dev, sp, r1, nps, r0, pc, ps)
char *sp;
{
    register i, a;

    savfp();              /* Save floating point state */
    u.u_ar0 = &r0;        /* Point to saved registers */
```

The parameters are the saved registers, with `dev` being the trap type (0-9).

### Floating Point Exception (dev == 8)

```c
    if(dev == 8) {
        psignal(u.u_procp, SIGFPT);
        if((ps&UMODE) == UMODE)
            goto err;
        return;
    }
```

Floating point errors signal the process.

### SETD Instruction Trap (dev == 1)

```c
    if(dev==1 && fuword(pc-2)==SETD && u.u_signal[SIGINS]==0)
        return;
```

The SETD instruction (set double mode) traps on some PDP-11 models. If the user hasn't registered a handler, just ignore it.

### Kernel Mode Trap

```c
    if((ps&UMODE) != UMODE)
        goto bad;         /* Trap in kernel mode = panic */
```

Traps in kernel mode (except floating point) are fatal.

### Stack Growth (dev == 9)

```c
    if(dev==9 && sp<-u.u_ssize*64) {
        if(backup(&r0) == 0)
        if(!estabur(u.u_tsize, u.u_dsize, u.u_ssize+SINCR)) {
            u.u_ssize =+ SINCR;
            expand(u.u_procp->p_size+SINCR);
            /* Move stack up */
            a = u.u_procp->p_addr + u.u_procp->p_size;
            for(i=0; i<u.u_ssize; i++) {
                a--;
                copyseg(a-SINCR, a);
            }
            return;
        }
    }
```

A segmentation fault that's just past the stack can be handled by **automatic stack growth**:
1. Back up the instruction
2. Expand the stack segment by SINCR blocks
3. Copy stack to new location
4. Return and retry the instruction

### Signal Dispatch

```c
    u.u_error = 0;
    switch(dev) {
    case 0:
        i = SIGBUS;
        goto def;
    case 1:
        i = SIGINS;
        goto def;
    case 2:
        i = SIGTRC;
        goto def;
    case 3:
        i = SIGIOT;
        goto def;
    case 5:
        i = SIGEMT;
        goto def;
    case 9:
        i = SIGSEG;
        goto def;
    def:
        psignal(u.u_procp, i);
    default:
        u.u_error = dev+100;
    case 6:;              /* System call - fall through */
    }
```

Most traps cause a signal. Device 6 (system call) falls through to the system call handling code.

## System Call Handling

```c
    if(u.u_error)
        goto err;
    ps =& ~EBIT;          /* Clear error bit (optimistic) */
    dev = fuword(pc-2)&077;   /* Get syscall number from instruction */
```

The system call number is encoded in the low 6 bits of the `trap` instruction itself.

### Indirect System Calls

```c
    if(dev == 0) { /* indirect */
        a = fuword(pc);
        pc =+ 2;
        dev = fuword(a)&077;
        a =+ 2;
    } else {
        a = pc;
        pc =+ sysent[dev].count*2;
    }
```

System call 0 is "indirect"—the next word points to the actual syscall.

### Fetch Arguments

```c
    for(i=0; i<sysent[dev].count; i++) {
        u.u_arg[i] = fuword(a);
        a =+ 2;
    }
    u.u_dirp = u.u_arg[0];    /* First arg often is pathname */
    trap1(sysent[dev].call);   /* Call the handler */
```

Arguments follow the trap instruction in user memory. They're fetched into `u.u_arg[]`.

### Error Handling

```c
    if(u.u_error >= 100)
        psignal(u.u_procp, SIGSYS);
err:
    if(issig())
        psig();
    if(u.u_error != 0) {
        ps =| EBIT;           /* Set error bit in PS */
        r0 = u.u_error;       /* Return error code in r0 */
    }
```

If there's an error, the carry bit (EBIT) is set and the error code goes in r0.

### Priority and Reschedule

```c
    u.u_procp->p_pri = PUSER + u.u_nice;
    if(u.u_dsleep++ > 15) {
        u.u_dsleep = 0;
        u.u_procp->p_pri++;
        swtch();
    }
    return;
```

After handling the syscall, the process priority is recalculated. If the process has been running for a while (`u_dsleep`), it may be preempted.

## The System Call Table

```c
/* sysent.c */
int sysent[]
{
    0, &nullsys,      /*  0 = indir */
    0, &rexit,        /*  1 = exit */
    0, &fork,         /*  2 = fork */
    2, &read,         /*  3 = read */
    2, &write,        /*  4 = write */
    2, &open,         /*  5 = open */
    0, &close,        /*  6 = close */
    0, &wait,         /*  7 = wait */
    2, &creat,        /*  8 = creat */
    2, &link,         /*  9 = link */
    1, &unlink,       /* 10 = unlink */
    2, &exec,         /* 11 = exec */
    1, &chdir,        /* 12 = chdir */
    0, &gtime,        /* 13 = time */
    3, &mknod,        /* 14 = mknod */
    2, &chmod,        /* 15 = chmod */
    2, &chown,        /* 16 = chown */
    1, &sbreak,       /* 17 = break */
    2, &stat,         /* 18 = stat */
    2, &seek,         /* 19 = seek */
    ...
    0, &dup,          /* 41 = dup */
    0, &pipe,         /* 42 = pipe */
    1, &times,        /* 43 = times */
    4, &profil,       /* 44 = prof */
    ...
    2, &ssig,         /* 48 = sig */
    ...
};
```

Each entry is two words:
- **count** — Number of arguments
- **call** — Pointer to handler function

## Making a System Call (User Side)

From user code, a system call looks like:

```assembly
/ read(fd, buf, count)
    mov  fd,r0
    sys  read; buf; count
    bcs  error
    / r0 = bytes read
```

The `sys read` assembles to `trap 3` (read is syscall 3). Arguments follow inline.

The C library provides wrappers:

```c
read(fd, buf, count)
char *buf;
{
    return(syscall(3, fd, buf, count));
}
```

## Complete System Call Flow

```
User Program:
    sys write; buf; count
         |
         v
Hardware:
    Push PS, PC
    Load PS, PC from vector 034
         |
         v
mch.s trap:
    Save registers
    Call _trap(6, ...)
         |
         v
trap.c trap():
    dev = fuword(pc-2) & 077  → 4 (write)
    Fetch arguments
    trap1(sysent[4].call)  → write()
         |
         v
sys2.c write():
    Do the actual write
    Set u.u_error if failed
         |
         v
trap.c trap():
    If error, set EBIT and r0
    Return
         |
         v
mch.s:
    Restore registers
    rti
         |
         v
User Program:
    bcs error    / Check carry bit
    / r0 = return value
```

## Error Handling

System calls report errors by:
1. Setting `u.u_error` to an error code
2. Setting the carry bit (EBIT) in the saved PS
3. Returning the error code in r0

User programs check the carry bit:

```assembly
    sys open; file; 0
    bcs error        / Branch if carry set
    mov r0,fd        / r0 = file descriptor
    ...
error:
    / r0 = error code (ENOENT, EACCES, etc.)
```

## The trap1() Function

```c
trap1(f)
int (*f)();
{
    savu(u.u_qsav);
    (*f)();
}
```

`trap1()` saves the registers in `u.u_qsav` before calling the syscall handler. This allows signals to abort syscalls and return to user mode via `aretu(u.u_qsav)`.

## Summary

- System calls use the PDP-11 `trap` instruction (vector 034)
- The trap handler saves state and identifies the syscall number
- Arguments are fetched from user memory following the instruction
- The `sysent[]` table maps syscall numbers to handlers
- Errors are returned via carry bit and r0
- The PS word tracks user/kernel mode and error status

## System Call Reference

| # | Name | Args | Description |
|---|------|------|-------------|
| 1 | exit | 0 | Terminate process |
| 2 | fork | 0 | Create child process |
| 3 | read | 2 | Read from file |
| 4 | write | 2 | Write to file |
| 5 | open | 2 | Open file |
| 6 | close | 0 | Close file |
| 7 | wait | 0 | Wait for child |
| 8 | creat | 2 | Create file |
| 9 | link | 2 | Create hard link |
| 10 | unlink | 1 | Remove file |
| 11 | exec | 2 | Execute program |
| 12 | chdir | 1 | Change directory |
| 13 | time | 0 | Get time |
| 14 | mknod | 3 | Make device node |
| 15 | chmod | 2 | Change mode |
| 16 | chown | 2 | Change owner |
| 17 | break | 1 | Change memory size |
| 18 | stat | 2 | Get file status |
| 19 | seek | 2 | Seek in file |
| 41 | dup | 0 | Duplicate fd |
| 42 | pipe | 0 | Create pipe |
| 48 | signal | 2 | Set signal handler |

## Experiments

1. **Add a syscall**: Add a new syscall that returns a constant. Modify sysent.c and test it.

2. **Trace syscalls**: Add printf to trap() to log every syscall.

3. **Error injection**: Modify a syscall to always fail and watch programs break.

## Further Reading

- Chapter 5: Process Management — fork, exec, exit, wait
- Chapter 10: File I/O — read, write, open, close
- Appendix A: Complete syscall reference

---

**Next: Chapter 8 — Scheduling**
