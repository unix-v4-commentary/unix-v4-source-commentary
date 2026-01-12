# Chapter 8: Scheduling

## Overview

UNIX v4 uses a simple but effective scheduling algorithm: priority-based preemptive scheduling with aging. This chapter examines how the scheduler decides which process runs, how priorities are calculated, and how context switching works. The elegance is in the simplicity—about 200 lines of code manage all process scheduling.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/ken/slp.c` | `sched()`, `swtch()`, `sleep()`, `wakeup()` |
| `usr/sys/ken/clock.c` | Clock interrupt, priority aging |
| `usr/sys/param.h` | Priority constants |
| `usr/sys/proc.h` | Process state definitions |

## Prerequisites

- Chapter 5: Process Management (process structure)
- Chapter 6: Memory Management (swapping)
- Chapter 7: Traps and System Calls (interrupt handling)

## The Scheduling Model

UNIX v4 scheduling has two levels:

1. **Swapper (process 0)** — Decides which processes are in memory
2. **swtch()** — Chooses among in-memory runnable processes

The swapper runs `sched()` in an infinite loop, swapping processes in and out. The `swtch()` function is called when a process blocks or when the clock decides it's time for preemption.

## Priority Basics

Lower numbers = higher priority:

```c
/* param.h */
#define PSWP    -100    /* Swapper */
#define PINOD   -90     /* Waiting for inode */
#define PRIBIO  -50     /* Waiting for buffer I/O */
#define PPIPE   1       /* Waiting for pipe */
#define PWAIT   40      /* Waiting for child (wait syscall) */
#define PSLEP   90      /* Sleeping (sleep syscall) */
#define PUSER   100     /* Base user priority */
```

Negative priorities are for kernel waits and cannot be interrupted by signals. Positive priorities are interruptible.

## The sleep() Function

```c
/* slp.c */
sleep(chan, pri)
{
    register *rp, s;

    u.u_dsleep = 0;
    s = PS->integ;
    rp = u.u_procp;
```

`sleep()` puts the current process to sleep waiting for an event (identified by `chan`).

```c
    if(pri >= 0) {
        /* Interruptible sleep */
        if(issig())
            goto psig;
        rp->p_wchan = chan;
        rp->p_stat = SWAIT;
        rp->p_pri = pri;
        spl0();
        if(runin != 0) {
            runin = 0;
            wakeup(&runin);
        }
        swtch();
        if(issig()) {
        psig:
            aretu(u.u_qsav);
            return;
        }
```

For interruptible sleeps (pri >= 0):
1. Check for pending signals first
2. Set wait channel and state SWAIT
3. Context switch away
4. On wakeup, check for signals again

```c
    } else {
        /* Uninterruptible sleep */
        rp->p_wchan = chan;
        rp->p_stat = SSLEEP;
        rp->p_pri = pri;
        spl0();
        swtch();
    }
    PS->integ = s;
}
```

For uninterruptible sleeps (pri < 0), the process sleeps until explicitly awakened.

## The wakeup() Function

```c
/* slp.c */
wakeup(chan)
{
    register struct proc *p;
    register n, c;

loop:
    c = chan;
    n = 0;
    for(p = &proc[0]; p < &proc[NPROC]; p++)
        if(p->p_wchan == c) {
            if(runout!=0 && (p->p_flag&SLOAD)==0) {
                runout = 0;
                n++;
            }
            p->p_wchan = 0;
            p->p_stat = SRUN;
            runrun++;
        }
    if(n) {
        chan = &runout;
        goto loop;
    }
}
```

`wakeup()` marks all processes sleeping on `chan` as runnable:
1. Scan the process table for matching `p_wchan`
2. Clear `p_wchan`, set `p_stat = SRUN`
3. Increment `runrun` to trigger rescheduling
4. If any swapped processes were awakened, wake the swapper too

## The swtch() Function

```c
/* slp.c */
swtch()
{
    static int *p;
    register i, n;
    register struct proc *rp;

    if(p == NULL)
        p = &proc[0];
    savu(u.u_rsav);           /* Save current context */
    retu(proc[0].p_addr);     /* Switch to process 0's context */
```

First, save the current process's registers and switch to process 0's address space (so we can access the proc table).

```c
loop:
    rp = p;
    p = NULL;
    n = 127;                  /* Start with lowest priority */
    for(i=0; i<NPROC; i++) {
        rp++;
        if(rp >= &proc[NPROC])
            rp = &proc[0];
        if(rp->p_stat==SRUN && (rp->p_flag&SLOAD)==SLOAD) {
            if(rp->p_pri < n) {
                p = rp;
                n = rp->p_pri;
            }
        }
    }
```

Search for the highest-priority runnable, in-memory process. The search starts from where we left off (round-robin among equal priorities).

```c
    if(p == NULL) {
        p = rp;
        idle();               /* No runnable process - wait */
        goto loop;
    }
```

If nothing is runnable, call `idle()` to wait for an interrupt.

```c
    rp = p;
    retu(rp->p_addr);         /* Switch to new process */
    sureg();                  /* Set up segment registers */
    if(rp->p_flag&SSWAP) {
        rp->p_flag =& ~SSWAP;
        aretu(u.u_ssav);      /* Return from swap */
    }
    return(1);
}
```

Switch to the selected process's address space and return.

## The sched() Function (Swapper)

Process 0 runs `sched()` forever:

```c
/* slp.c */
sched()
{
    struct proc *p1;
    register struct proc *rp;
    register a, n;

    /*
     * find user to swap in
     * of users ready, select one out longest
     */
    goto loop;

sloop:
    runin++;
    sleep(&runin, PSWP);

loop:
    spl6();
    n = -1;
    for(rp = &proc[0]; rp < &proc[NPROC]; rp++)
    if(rp->p_stat==SRUN && (rp->p_flag&SLOAD)==0 &&
        rp->p_time > n) {
        p1 = rp;
        n = rp->p_time;
    }
    if(n == -1) {
        runout++;
        sleep(&runout, PSWP);
        goto loop;
    }
```

Find a swapped-out process that's been waiting longest (`p_time`).

```c
    /*
     * see if there is core for that process
     */
    spl0();
    rp = p1;
    a = rp->p_size;
    if((rp=rp->p_textp) != NULL)
        if(rp->x_ccount == 0)
            a =+ rp->x_size;
    if((a=malloc(coremap, a)) != NULL)
        goto found2;
```

Try to allocate memory for it.

```c
    /*
     * none found,
     * look around for easy core
     */
    spl6();
    for(rp = &proc[0]; rp < &proc[NPROC]; rp++)
    if((rp->p_flag&(SSYS|SLOCK|SLOAD))==SLOAD &&
        rp->p_stat == SWAIT)
        goto found1;
```

If no memory, look for an easy victim—a process that's sleeping.

```c
    /*
     * no easy core,
     * if this process is deserving,
     * look around for
     * oldest process in core
     */
    if(n < 3)
        goto sloop;
    n = -1;
    for(rp = &proc[0]; rp < &proc[NPROC]; rp++)
    if((rp->p_flag&(SSYS|SLOCK|SLOAD))==SLOAD &&
       (rp->p_stat==SRUN || rp->p_stat==SSLEEP) &&
        rp->p_time > n) {
        p1 = rp;
        n = rp->p_time;
    }
    if(n < 2)
        goto sloop;
    rp = p1;
```

If no sleeping process, find the oldest in-memory process. But don't swap out a process that's only been in memory briefly (`n < 3` and `n < 2` checks).

```c
    /*
     * swap user out
     */
found1:
    spl0();
    rp->p_flag =& ~SLOAD;
    xswap(rp, 1, 0);
    goto loop;

    /*
     * swap user in
     */
found2:
    /* ... swap in code ... */
    goto loop;
}
```

The swapper either swaps out a victim or swaps in the waiting process, then loops.

## The Clock Interrupt

The clock ticks 60 times per second:

```c
/* clock.c */
clock(dev, sp, r1, nps, r0, pc, ps)
{
    register struct callo *p1, *p2;
    register struct proc *pp;

    *lks = 0115;              /* Restart clock */
    display();                /* Update console display */
```

### Callouts

```c
    /*
     * callouts - decrement timers
     */
    if(callout[0].c_func == 0)
        goto out;
    p2 = &callout[0];
    while(p2->c_time<=0 && p2->c_func!=0)
        p2++;
    p2->c_time--;

    if((ps&0340) != 0)        /* If IPL high, don't run callouts */
        goto out;

    spl5();
    if(callout[0].c_time <= 0) {
        /* Run expired callouts */
        p1 = &callout[0];
        while(p1->c_func != 0 && p1->c_time <= 0) {
            (*p1->c_func)(p1->c_arg);
            p1++;
        }
        /* Compact the callout table */
        ...
    }
```

Callouts are timed callbacks. Each tick decrements the first non-zero timer.

### Time Accounting

```c
out:
    if((ps&UMODE) == UMODE) {
        u.u_utime++;          /* User mode: charge user time */
        if(u.u_prof[3])
            incupc(pc, u.u_prof);   /* Profiling */
    } else
        u.u_stime++;          /* Kernel mode: charge system time */
```

### Every Second (60 ticks)

```c
    if(++lbolt >= 60) {
        if((ps&0340) != 0)
            return;
        lbolt =- 60;
        if(++time[1] == 0)
            ++time[0];        /* Increment time of day */

        spl1();
        if(time[1]==tout[1] && time[0]==tout[0])
            wakeup(tout);     /* Wake alarm sleepers */
        if((time[1]&03) == 0)
            wakeup(&lbolt);   /* Wake every 4 seconds */
```

### Priority Aging

```c
        for(pp = &proc[0]; pp < &proc[NPROC]; pp++)
        if(pp->p_time != 127)
            pp->p_time++;     /* Age all processes */
```

`p_time` counts how long a process has been in its current location (memory or swap).

### Preemption

```c
        if((ps&UMODE) == UMODE) {
            u.u_ar0 = &r0;
            pp = u.u_procp;
            if(issig())
                psig();
            if(pp->p_pri < 105)
                pp->p_pri++;  /* Lower priority (higher number) */
            savfp();
            swtch();          /* Preempt! */
        }
    }
}
```

Once per second, if we're in user mode:
1. Check for signals
2. Decay the process's priority
3. Call `swtch()` to potentially run another process

## Priority Calculation

Priorities in UNIX v4 are simple:

1. **Initial priority**: Set by `sleep()` based on what the process is waiting for
2. **User processes**: Start at `PUSER + u.u_nice` (100 + nice value)
3. **Aging**: Once per second, increment priority (lower priority)
4. **Recalculation**: After a syscall, reset to `PUSER + u.u_nice`

From `trap.c`:

```c
    u.u_procp->p_pri = PUSER + u.u_nice;
```

This creates a simple feedback loop:
- Processes that use CPU time get lower priority
- Processes that sleep get reset to high priority when they wake
- I/O-bound processes naturally get better priority than CPU-bound

## Context Switching

The actual context switch uses three assembly functions:

```c
savu(u.u_rsav)     /* Save current sp and r5 */
retu(p->p_addr)    /* Switch to process p's memory, restore sp/r5 */
aretu(u.u_qsav)    /* Return to saved context (for signals) */
```

From `mch.s`:

```assembly
_savu:
    spl  7                    / Disable interrupts
    mov  (sp)+,r1             / Return address
    mov  (sp),r0              / Save area pointer
    mov  sp,(r0)+             / Save sp
    mov  r5,(r0)+             / Save r5
    spl  0                    / Enable interrupts
    jmp  (r1)                 / Return

_retu:
    spl  7
    mov  (sp)+,r1
    mov  (sp),KISA6           / Set segment 6 to new process
    mov  $_u,r0
    mov  (r0)+,sp             / Restore sp
    mov  (r0)+,r5             / Restore r5
    spl  0
    jmp  (r1)
```

The key is changing `KISA6`—segment 6 points to the user structure, so changing it switches to a different process's context.

## Scheduling Flags

Three flags coordinate scheduling:

- **runrun** — Set when a higher-priority process becomes runnable
- **runin** — Set when swapper should look for something to swap in
- **runout** — Set when swapper should look for something to swap out

When `runrun` is set, `swtch()` is called at the next opportunity.

## Summary

- Scheduling is priority-based: lower number = higher priority
- `sleep()` blocks a process on a "wait channel"
- `wakeup()` makes all processes on a channel runnable
- `swtch()` picks the highest-priority runnable process
- `sched()` (process 0) handles swapping
- The clock provides preemption and priority aging
- Context switching changes segment 6 to point to a different user structure

## The Beauty of Simplicity

The entire scheduler fits in about 200 lines:
- No run queues (just scan the proc table)
- No complex priority inheritance
- No real-time scheduling
- Just: find highest priority, run it, age priorities

This works because:
- Only 50 processes maximum
- Clock provides regular preemption
- I/O-bound processes naturally get good priority

## Experiments

1. **Watch scheduling**: Add printf to `swtch()` to see process switches.

2. **Change priorities**: Modify the priority constants and observe behavior.

3. **Disable preemption**: Remove the `swtch()` call from `clock()` and see what happens.

## Further Reading

- Chapter 5: Process Management — Process states and transitions
- Chapter 6: Memory Management — How swapping interacts with scheduling
- Chapter 7: Traps and System Calls — How syscalls trigger rescheduling

---

**End of Part II: The Kernel**

**Next: Part III — The File System**
