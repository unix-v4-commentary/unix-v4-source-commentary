# Chapter 5: Process Management

## Overview

Processes are the heart of UNIX. Every running program is a process, and every process except the first is created by another process through `fork()`. This chapter examines how UNIX v4 represents, creates, and manages processes—the fundamental abstraction that makes multitasking possible.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/proc.h` | Process structure definition |
| `usr/sys/user.h` | User structure (per-process kernel data) |
| `usr/sys/ken/slp.c` | `newproc()`, `expand()` |
| `usr/sys/ken/sys1.c` | `fork()`, `exec()`, `exit()`, `wait()` |

## Prerequisites

- Chapter 2: PDP-11 Architecture (memory segments)
- Chapter 4: Boot Sequence (process 0 and 1 creation)

## The Process Table

Every process has an entry in the global process table:

```c
/* proc.h */
struct proc {
    char p_stat;      /* Process state */
    char p_flag;      /* Flags */
    char p_pri;       /* Priority (lower = higher priority) */
    char p_sig;       /* Pending signal */
    char p_null;      /* Unused */
    char p_time;      /* Resident time for scheduling */
    int  p_ttyp;      /* Controlling terminal */
    int  p_pid;       /* Process ID */
    int  p_ppid;      /* Parent process ID */
    int  p_addr;      /* Address of swappable image */
    int  p_size;      /* Size of swappable image (64-byte blocks) */
    int  p_wchan;     /* Wait channel (sleeping on) */
    int  *p_textp;    /* Pointer to text structure */
} proc[NPROC];
```

With `NPROC=50`, the system supports at most 50 simultaneous processes.

### Process States (p_stat)

```c
#define SSLEEP  1    /* Sleeping at high priority */
#define SWAIT   2    /* Sleeping at low priority (interruptible) */
#define SRUN    3    /* Runnable */
#define SIDL    4    /* Being created */
#define SZOMB   5    /* Terminated, waiting for parent */
```

State transitions:

```
        fork()
          |
          v
       [SIDL] -----> [SRUN] <---+
                       |        |
                       | sleep()|
                       v        | wakeup()
                    [SSLEEP]----+
                    [SWAIT]-----+
                       |
                       | exit()
                       v
                    [SZOMB]
                       |
                       | parent wait()
                       v
                     [NULL] (slot free)
```

### Process Flags (p_flag)

```c
#define SLOAD   01   /* In memory (not swapped) */
#define SSYS    02   /* System process (process 0) */
#define SLOCK   04   /* Process cannot be swapped */
#define SSWAP   010  /* Being swapped out */
```

## The User Structure

While `proc` holds minimal info for all processes, `u` (the **user structure**) holds extensive per-process data for the *current* process:

```c
/* user.h */
struct user {
    int   u_rsav[2];        /* Saved r5, r6 for resume */
    int   u_fsav[25];       /* Floating point save area */
    char  u_segflg;         /* I/O to user/kernel space */
    char  u_error;          /* Error code from syscall */
    char  u_uid;            /* Effective user ID */
    char  u_gid;            /* Effective group ID */
    char  u_ruid;           /* Real user ID */
    char  u_rgid;           /* Real group ID */
    int   u_procp;          /* Pointer to proc entry */
    char  *u_base;          /* I/O base address */
    char  *u_count;         /* I/O byte count */
    char  *u_offset[2];     /* I/O file offset */
    int   *u_cdir;          /* Current directory inode */
    char  u_dbuf[DIRSIZ];   /* Current pathname component */
    char  *u_dirp;          /* Pathname pointer */
    struct {                /* Current directory entry */
        int  u_ino;
        char u_name[DIRSIZ];
    } u_dent;
    int   *u_pdir;          /* Parent directory inode */
    int   u_uisa[8];        /* User segment addresses */
    int   u_uisd[8];        /* User segment descriptors */
    int   u_ofile[NOFILE];  /* Open file table */
    int   u_arg[5];         /* Syscall arguments */
    int   u_tsize;          /* Text size (64-byte blocks) */
    int   u_dsize;          /* Data size */
    int   u_ssize;          /* Stack size */
    int   u_qsav[2];        /* Saved regs for signal return */
    int   u_ssav[2];        /* Saved regs for swap return */
    int   u_signal[NSIG];   /* Signal handlers */
    int   u_utime;          /* User time (ticks) */
    int   u_stime;          /* System time (ticks) */
    int   u_cutime[2];      /* Children's user time */
    int   u_cstime[2];      /* Children's system time */
    int   *u_ar0;           /* Pointer to saved r0 */
    int   u_prof[4];        /* Profiling parameters */
    char  u_nice;           /* Nice value */
    char  u_dsleep;         /* Deep sleep flag */
} u;    /* u = 140000 */
```

The magic comment `u = 140000` means the user structure is always at virtual address `0140000` (octal). This is segment 6, which the kernel remaps for each process.

## fork() — Creating a Process

The `fork()` system call creates a new process:

```c
/* sys1.c */
fork()
{
    register struct proc *p1, *p2;

    p1 = u.u_procp;            /* Parent */
    for(p2 = &proc[0]; p2 < &proc[NPROC]; p2++)
        if(p2->p_stat == NULL)
            goto found;
    u.u_error = EAGAIN;        /* No free slots */
    goto out;

found:
    if(newproc()) {
        /* Child: return parent's PID */
        u.u_ar0[R0] = p1->p_pid;
        u.u_cstime[0] = 0;
        u.u_cstime[1] = 0;
        u.u_stime = 0;
        u.u_cutime[0] = 0;
        u.u_cutime[1] = 0;
        u.u_utime = 0;
        return;
    }
    /* Parent: return child's PID */
    u.u_ar0[R0] = p2->p_pid;

out:
    u.u_ar0[R7] =+ 2;          /* Skip over sys fork instruction */
}
```

The key insight: `fork()` returns **twice**—once in the parent (returning child's PID) and once in the child (returning parent's PID). The actual work is in `newproc()`.

### newproc() — The Fork Implementation

```c
/* slp.c */
newproc()
{
    int a1, a2;
    struct proc *p, *up;
    register struct proc *rpp;
    register *rip, n;

    /* Find free proc slot */
    for(rpp = &proc[0]; rpp < &proc[NPROC]; rpp++)
        if(rpp->p_stat == NULL)
            goto found;
    panic("no procs");

found:
    /*
     * make proc entry for new proc
     */
    p = rpp;
    rip = u.u_procp;
    up = rip;
    rpp->p_stat = SRUN;
    rpp->p_flag = SLOAD;
    rpp->p_ttyp = rip->p_ttyp;      /* Inherit terminal */
    rpp->p_textp = rip->p_textp;    /* Share text segment */
    rpp->p_pid = ++mpid;            /* Assign new PID */
    rpp->p_ppid = rip->p_pid;       /* Record parent */
    rpp->p_time = 0;
```

The child inherits most fields from the parent, but gets a new PID.

```c
    /*
     * make duplicate entries
     * where needed
     */
    for(rip = &u.u_ofile[0]; rip < &u.u_ofile[NOFILE];)
        if((rpp = *rip++) != NULL)
            rpp->f_count++;         /* Bump file ref counts */
    if((rpp=up->p_textp) != NULL) {
        rpp->x_count++;             /* Bump text ref count */
        rpp->x_ccount++;
    }
    u.u_cdir->i_count++;            /* Bump cwd inode ref */
```

Shared resources (open files, text segment, current directory) have their reference counts incremented.

```c
    /*
     * swap out old process
     * to make image of new proc
     */
    savu(u.u_rsav);
    rpp = p;
    u.u_procp = rpp;
    rip = up;
    n = rip->p_size;
    a1 = rip->p_addr;
    rpp->p_size = n;
    a2 = malloc(coremap, n);
    if(a2 == NULL) {
        /* No memory: swap out child */
        rip->p_stat = SIDL;
        rpp->p_addr = a1;
        savu(u.u_ssav);
        xswap(rpp, 0, 0);
        rpp->p_flag =| SSWAP;
        rip->p_stat = SRUN;
    } else {
        /* Copy parent's memory to child */
        rpp->p_addr = a2;
        while(n--)
            copyseg(a1++, a2++);
    }
    u.u_procp = rip;
    return(0);                      /* Return 0 in parent */
}
```

If memory is available, the parent's image is copied block-by-block. If not, the child is created on swap. Either way, the parent returns 0.

The child's return happens later, when the scheduler runs the child and it resumes from the saved context.

## exec() — Running a Program

`exec()` replaces the current process's memory with a new program:

```c
/* sys1.c */
exec()
{
    int ap, na, nc, *bp;
    int ts, ds;
    register c, *ip;
    register char *cp;
    extern uchar;

    /*
     * pick up file names
     * and check various modes
     */
    ip = namei(&uchar, 0);      /* Look up pathname */
    if(ip == NULL)
        return;
    bp = getblk(NODEV);         /* Get buffer for args */
    if(access(ip, IEXEC))       /* Check execute permission */
        goto bad;
```

First, the executable file is located and checked for execute permission.

```c
    /*
     * pack up arguments into
     * allocated disk buffer
     */
    cp = bp->b_addr;
    na = 0;    /* Argument count */
    nc = 0;    /* Character count */
    while(ap = fuword(u.u_arg[1])) {
        na++;
        if(ap == -1)
            goto bad;
        u.u_arg[1] =+ 2;
        for(;;) {
            c = fubyte(ap++);
            if(c == -1)
                goto bad;
            *cp++ = c;
            nc++;
            if(nc > 510) {
                u.u_error = E2BIG;
                goto bad;
            }
            if(c == 0)
                break;
        }
    }
```

Arguments are copied from user space into a kernel buffer. There's a 510-byte limit on total argument length.

```c
    /*
     * read in first 8 bytes
     * of file for segment sizes:
     * w0 = 407/410 (410 implies RO text)
     * w1 = text size
     * w2 = data size
     * w3 = bss size
     */
    u.u_base = &u.u_arg[0];
    u.u_count = 8;
    u.u_offset[1] = 0;
    u.u_offset[0] = 0;
    u.u_segflg = 1;
    readi(ip);
```

The a.out header is read:
- `0407` — Executable with combined text+data (not shared)
- `0410` — Executable with separate, read-only text (sharable)

```c
    /*
     * find text and data sizes
     */
    ts = ((u.u_arg[1]+63)>>6) & 01777;
    ds = ((u.u_arg[2]+u.u_arg[3]+63)>>6) & 01777;
    if(estabur(ts, ds, SSIZE))
        goto bad;

    /*
     * allocate and clear core
     * at this point, committed to the new image
     */
    u.u_prof[3] = 0;
    xfree();                    /* Free old text segment */
    xalloc(ip);                 /* Allocate new text */
    c = USIZE+ds+SSIZE;
    expand(USIZE);
    expand(c);
    while(--c >= USIZE)
        clearseg(u.u_procp->p_addr+c);
```

Old memory is freed, new memory is allocated and cleared.

```c
    /*
     * read in data segment
     */
    estabur(0, ds, 0);
    u.u_base = 0;
    u.u_offset[1] = 020+u.u_arg[1];   /* Skip header + text */
    u.u_count = u.u_arg[2];
    readi(ip);

    /*
     * initialize stack segment
     */
    u.u_tsize = ts;
    u.u_dsize = ds;
    u.u_ssize = SSIZE;
    estabur(u.u_tsize, u.u_dsize, u.u_ssize);
```

The data segment is read from the file. For `0410` executables, the text segment is handled separately through shared text management.

```c
    /*
     * Copy arguments to user stack
     */
    cp = bp->b_addr;
    ap = -nc - na*2 - 4;        /* Stack grows down */
    u.u_ar0[R6] = ap;           /* Set stack pointer */
    suword(ap, na);             /* argc */
    c = -nc;
    while(na--) {
        suword(ap=+2, c);       /* argv[i] */
        do
            subyte(c++, *cp);   /* Copy string */
        while(*cp++);
    }
    suword(ap+2, -1);           /* argv terminator */
```

Arguments are copied to the user stack in the standard format:
```
sp → argc
     argv[0] → "program"
     argv[1] → "arg1"
     ...
     NULL
     "program\0arg1\0..."
```

```c
    /*
     * set SUID/SGID protections
     */
    if(ip->i_mode&ISUID)
        if(u.u_uid != 0)
            u.u_uid = ip->i_uid;
    if(ip->i_mode&ISGID)
        u.u_gid = ip->i_gid;

    /*
     * clear sigs, regs and return
     */
    for(ip = &u.u_signal[0]; ip < &u.u_signal[NSIG]; ip++)
        if((*ip & 1) == 0)
            *ip = 0;            /* Reset non-ignored signals */
    for(cp = &regloc[0]; cp < &regloc[6];)
        u.u_ar0[*cp++] = 0;     /* Clear registers */
    u.u_ar0[R7] = 0;            /* PC = 0 (entry point) */
```

Setuid/setgid is handled, signals are reset, and execution begins at address 0.

## exit() — Terminating a Process

```c
/* sys1.c */
exit()
{
    register int *q, a;
    register struct proc *p;

    /* Ignore all signals */
    for(q = &u.u_signal[0]; q < &u.u_signal[NSIG];)
        *q++ = 1;

    /* Close all open files */
    for(q = &u.u_ofile[0]; q < &u.u_ofile[NOFILE]; q++)
        if(a = *q) {
            *q = NULL;
            closef(a);
        }

    /* Release current directory */
    iput(u.u_cdir);

    /* Free text segment */
    xfree();
```

First, cleanup: ignore signals, close files, release directory.

```c
    /* Save exit status to swap */
    a = malloc(swapmap, 8);
    p = getblk(swapdev, a);
    bcopy(&u, p->b_addr, 256);
    bwrite(p);

    /* Free memory */
    q = u.u_procp;
    mfree(coremap, q->p_size, q->p_addr);
    q->p_addr = a;              /* Now points to swap */
    q->p_stat = SZOMB;          /* Zombie state */
```

The user structure (containing the exit status) is saved to swap, memory is freed, and the process becomes a zombie.

```c
loop:
    /* Find parent and wake it up */
    for(p = &proc[0]; p < &proc[NPROC]; p++)
    if(q->p_ppid == p->p_pid) {
        wakeup(&proc[1]);       /* Wake init (adopts orphans) */
        wakeup(p);              /* Wake parent */

        /* Orphan our children to init */
        for(p = &proc[0]; p < &proc[NPROC]; p++)
        if(q->p_pid == p->p_ppid)
            p->p_ppid = 1;

        swtch();                /* Switch away, never return */
    }
```

The parent is woken up, and orphaned children are adopted by init (PID 1). The process then switches away and never returns—it remains a zombie until the parent calls `wait()`.

## wait() — Reaping Children

```c
/* sys1.c */
wait()
{
    register f, *bp;
    register struct proc *p;

    f = 0;

loop:
    for(p = &proc[0]; p < &proc[NPROC]; p++)
    if(p->p_ppid == u.u_procp->p_pid) {
        f++;
        if(p->p_stat == SZOMB) {
            /* Found dead child */
            u.u_ar0[R0] = p->p_pid;

            /* Read exit status from swap */
            bp = bread(swapdev, f=p->p_addr);
            mfree(swapmap, 8, f);

            /* Clear proc slot */
            p->p_stat = NULL;
            p->p_pid = 0;
            p->p_ppid = 0;
            ...

            /* Accumulate child's CPU time */
            u.u_cstime[0] =+ p->u_cstime[0];
            ...

            /* Return exit status */
            u.u_ar0[R1] = p->u_arg[0];
            brelse(bp);
            return;
        }
    }
    if(f) {
        sleep(u.u_procp, PWAIT);    /* Wait for child to exit */
        goto loop;
    }
    u.u_error = ECHILD;             /* No children */
}
```

`wait()` searches for zombie children. If found, it:
1. Reads the exit status from swap
2. Frees the swap space
3. Clears the proc slot
4. Accumulates CPU time statistics
5. Returns PID and exit status

If there are living children but no zombies, it sleeps until one exits.

## sbreak() — Changing Memory Size

```c
/* sys1.c */
sbreak()
{
    register a, n, d;

    /*
     * Calculate new data size
     */
    n = (((u.u_arg[0]+63)>>6) & 01777) - nseg(u.u_tsize)*128;
    if(n < 0)
        n = 0;
    d = n - u.u_dsize;          /* Delta */
    n =+ USIZE+u.u_ssize;

    if(estabur(u.u_tsize, u.u_dsize+d, u.u_ssize))
        return;
    u.u_dsize =+ d;

    if(d > 0)
        goto bigger;

    /* Shrinking: move stack down, then shrink */
    a = u.u_procp->p_addr + n - u.u_ssize;
    n = u.u_ssize;
    while(n--) {
        copyseg(a-d, a);
        a++;
    }
    expand(i);
    return;

bigger:
    /* Growing: expand, then move stack up */
    expand(n);
    a = u.u_procp->p_addr + n;
    n = u.u_ssize;
    while(n--) {
        a--;
        copyseg(a-d, a);
    }
    while(d--)
        clearseg(--a);
}
```

`sbreak()` (break) changes the data segment size. The stack must be moved when the data segment grows or shrinks.

## expand() — Growing or Shrinking Process Memory

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
        /* Shrinking: just free excess */
        mfree(coremap, n-newsize, a1+newsize);
        return;
    }

    /* Growing: need to allocate new space */
    savu(u.u_rsav);
    a2 = malloc(coremap, newsize);
    if(a2 == NULL) {
        /* No memory: swap out and grow on swap */
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

If growing and memory is available, the process is copied to a new, larger location. If not, it's swapped out.

## Summary

- The **proc structure** holds minimal per-process info; **u** holds the rest
- `fork()` creates a new process by duplicating the parent
- `exec()` replaces a process's memory image with a new program
- `exit()` terminates a process, making it a zombie
- `wait()` reaps zombie children and retrieves their exit status
- `sbreak()` changes the data segment size
- `expand()` handles memory allocation/reallocation for processes

## Key Concepts

### Process Creation Pattern

```c
if(fork() == 0) {
    /* Child */
    exec("/bin/program", ...);
    exit(1);    /* exec failed */
}
/* Parent continues */
wait(&status);
```

### Reference Counting

When `fork()` copies a process, shared resources have their reference counts bumped:
- Open files (`f_count`)
- Text segments (`x_count`)
- Inodes (`i_count`)

When `exit()` cleans up, these counts are decremented.

### The Zombie State

A zombie is a process that has exited but hasn't been waited for:
- Uses minimal resources (just a proc slot and swap block)
- Contains exit status for parent
- Cleaned up by parent's `wait()`

## Experiments

1. **Count processes**: Add printfs to trace proc slot allocation in `fork()`.

2. **Argument limit**: Try to exec with more than 510 bytes of arguments.

3. **Fork bomb**: What happens if a process forks in a loop? (The NPROC limit saves you.)

## Further Reading

- Chapter 6: Memory Management — How memory is allocated
- Chapter 8: Scheduling — How processes are selected to run
- Chapter 7: Traps and System Calls — How fork/exec/exit are invoked

---

**Next: Chapter 6 — Memory Management**
