# Chapter 13: The TTY Subsystem

## Overview

In 1973, users interacted with UNIX through **teletypes**—electromechanical terminals that typed characters on paper. The TTY subsystem handles all this terminal I/O: echoing characters, processing backspace and line-kill, converting between uppercase and lowercase, expanding tabs, generating signals for interrupt and quit, and managing output flow control.

This is surprisingly complex code because it must handle the mismatch between human typing speeds and computer processing, while providing a pleasant interactive experience.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/tty.h` | TTY structure and constants |
| `usr/sys/dmr/tty.c` | Common TTY routines |
| `usr/sys/dmr/kl.c` | KL-11 console driver |

## Prerequisites

- Chapter 10: File I/O (`passc`, `cpass`)
- Character device interface basics

## The TTY Structure

```c
/* tty.h */
struct tty {
    struct clist t_rawq;    /* Raw input queue */
    struct clist t_canq;    /* Canonical input queue */
    struct clist t_outq;    /* Output queue */
    int    t_flags;         /* Mode flags */
    int    *t_addr;         /* Device register address */
    char   t_delct;         /* Delimiter count (completed lines) */
    char   t_col;           /* Current column position */
    char   t_intrup;        /* Interrupt character */
    char   t_quit;          /* Quit character */
    char   t_state;         /* State flags */
    char   t_char;          /* (unused) */
    int    t_speeds;        /* Baud rate encoding */
};
```

### The Three Queues

```
Keyboard
   │
   ▼
┌────────────┐    canon()    ┌────────────┐    read()    User
│  t_rawq    │──────────────►│  t_canq    │────────────► Process
│ (raw input)│               │ (canonical)│
└────────────┘               └────────────┘

User                         ┌────────────┐    interrupt   Terminal
Process ────────────────────►│  t_outq    │─────────────► Screen
         write()             │  (output)  │
                             └────────────┘
```

**t_rawq** (raw queue): Characters as they arrive from the keyboard, before any editing.

**t_canq** (canonical queue): Completed, edited lines ready for the application.

**t_outq** (output queue): Characters waiting to be displayed.

### Character Lists (clist)

```c
struct clist {
    int c_cc;       /* Character count */
    int c_cf;       /* First cblock pointer */
    int c_cl;       /* Last cblock pointer */
};

struct cblock {
    struct cblock *c_next;
    char info[6];   /* 6 characters per block */
};
```

Characters are stored in linked lists of 6-character blocks. This allows queues to grow and shrink dynamically without large fixed buffers.

## Mode Flags

```c
/* tty.h */
#define RAW     040     /* No processing, raw I/O */
#define ECHO    010     /* Echo input characters */
#define LCASE   04      /* Map uppercase to lowercase */
#define CRMOD   020     /* Map CR to NL on input, NL to CR+NL on output */
#define XTABS   02      /* Expand tabs to spaces */
#define NODELAY 01      /* No output delays */
```

**RAW mode**: Characters pass through unprocessed—no line editing, no signals, no echo. Used by screen editors and games.

**Cooked mode** (default): Full line editing with backspace (#) and line-kill (@), signal generation, and echo.

## State Flags

```c
#define ISOPEN   04     /* Device is open */
#define WOPEN    02     /* Waiting for open (modem) */
#define CARR_ON  020    /* Carrier present (modem connected) */
#define BUSY     040    /* Output in progress */
#define TIMEOUT  01     /* Delay in progress */
#define SSTART   010    /* Use special start routine */
```

## Special Characters

```c
#define CERASE  '#'     /* Erase one character */
#define CKILL   '@'     /* Kill entire line */
#define CEOT    004     /* End of file (Ctrl-D) */
```

The quit character (Ctrl-\) and interrupt character (DEL) are stored in the tty structure and can be changed per-terminal.

## cinit() — Initialize Character Lists

```c
/* tty.c */
cinit()
{
    register int ccp;
    register struct cblock *cp;
    register struct cdevsw *cdp;

    ccp = cfree;
    for (cp=(ccp+07)&~07; cp <= &cfree[NCLIST-1]; cp++) {
        cp->c_next = cfreelist;
        cfreelist = cp;
    }
    ccp = 0;
    for(cdp = cdevsw; cdp->d_open; cdp++)
        ccp++;
    nchrdev = ccp;
}
```

Links all cblocks into the free list and counts character devices.

## Input Path

### ttyinput() — Receive a Character

Called from the device interrupt handler when a character arrives:

```c
/* tty.c */
ttyinput(ac, atp)
struct tty *atp;
{
    register int t_flags, c;
    register struct tty *tp;

    tp = atp;
    c = ac;
    t_flags = tp->t_flags;
```

```c
    if ((c =& 0177) == '\r' && t_flags&CRMOD)
        c = '\n';
```

Strip to 7 bits. If CRMOD is set, convert carriage return to newline.

```c
    if ((t_flags&RAW)==0 && (c==tp->t_quit || c==tp->t_intrup)) {
        signal(tp, c==tp->t_intrup? SIGINT:SIGQIT);
        flushtty(tp);
        return;
    }
```

In cooked mode, check for interrupt (DEL) or quit (Ctrl-\). Send the appropriate signal and flush all queues.

```c
    if (tp->t_rawq.c_cc>=TTYHOG) {
        flushtty(tp);
        return;
    }
```

Prevent buffer overflow—if raw queue exceeds TTYHOG (256), flush everything.

```c
    if (t_flags&LCASE && c>='A' && c<='Z')
        c =+ 'a'-'A';
    putc(c, &tp->t_rawq);
```

Convert uppercase to lowercase if LCASE mode. Add character to raw queue.

```c
    if (t_flags&RAW || c=='\n' || c==004) {
        wakeup(&tp->t_rawq);
        if (putc(0377, &tp->t_rawq)==0)
            tp->t_delct++;
    }
```

In RAW mode, or when a line delimiter arrives (newline or Ctrl-D), wake up any process waiting for input. The 0377 character marks the end of a line; `t_delct` counts complete lines.

```c
    if (t_flags&ECHO) {
        ttyoutput(c, tp);
        ttstart(tp);
    }
}
```

If ECHO is enabled, send the character to output.

### canon() — Canonicalize Input

Converts raw input to edited, canonical form:

```c
/* tty.c */
canon(atp)
struct tty *atp;
{
    register char *bp;
    char *bp1;
    register struct tty *tp;
    register int c;

    tp = atp;
    spl5();
    while (tp->t_delct==0) {
        if ((tp->t_state&CARR_ON)==0)
            return(0);          /* Carrier lost */
        sleep(&tp->t_rawq, TTIPRI);
    }
    spl0();
```

Wait until at least one complete line is available (`t_delct > 0`).

```c
loop:
    bp = &canonb[2];
    while ((c=getc(&tp->t_rawq)) >= 0) {
        if (c==0377) {
            tp->t_delct--;
            break;              /* End of line */
        }
```

Read characters from raw queue until the delimiter (0377).

```c
        if ((tp->t_flags&RAW)==0) {
            if (bp[-1]!='\\') {
                if (c==CERASE) {
                    if (bp > &canonb[2])
                        bp--;
                    continue;
                }
                if (c==CKILL)
                    goto loop;  /* Start over */
                if (c==CEOT)
                    continue;   /* Ignore Ctrl-D itself */
            }
```

Process editing characters:
- **#** (CERASE): Back up one character
- **@** (CKILL): Discard entire line, start over
- **Ctrl-D** (CEOT): Mark end of file but don't include in output

```c
            } else
            if (maptab[c] && (maptab[c]==c || (tp->t_flags&LCASE))) {
                if (bp[-2] != '\\')
                    c = maptab[c];
                bp--;
            }
        }
        *bp++ = c;
        if (bp>=canonb+CANBSIZ)
            break;
    }
```

Handle escape sequences: `\{` becomes `{`, `\|` becomes `|`, etc. This allows typing special characters on terminals that lack them.

```c
    bp1 = bp;
    bp = &canonb[2];
    c = &tp->t_canq;
    while (bp<bp1)
        putc(*bp++, c);
    return(1);
}
```

Copy the edited line to the canonical queue.

### ttread() — Read from TTY

```c
/* tty.c */
ttread(atp)
struct tty *atp;
{
    register struct tty *tp;

    tp = atp;
    if (tp->t_canq.c_cc || canon(tp))
        while (tp->t_canq.c_cc && passc(getc(&tp->t_canq))>=0);
}
```

If the canonical queue has characters, or `canon()` can produce some, transfer them to the user's buffer via `passc()`.

## Output Path

### ttyoutput() — Process Output Character

```c
/* tty.c */
ttyoutput(ac, tp)
struct tty *tp;
{
    register int c;
    register struct tty *rtp;
    register char *colp;
    int ctype;

    rtp = tp;
    c = ac&0177;
```

```c
    if (c==004 && (rtp->t_flags&RAW)==0)
        return;                 /* Suppress Ctrl-D in cooked mode */
```

```c
    if (c=='\t' && rtp->t_flags&XTABS) {
        do
            ttyoutput(' ', rtp);
        while (rtp->t_col&07);
        return;
    }
```

Expand tabs to spaces if XTABS is set.

```c
    if (rtp->t_flags&LCASE) {
        switch (c) {
        case '{':
            c = '(';
            goto esc;
        case '}':
            c = ')';
            goto esc;
        case '|':
            c = '!';
            goto esc;
        case '~':
            c = '^';
            goto esc;
        case '`':
            c = '\'';
        esc:
            ttyoutput('\\', rtp);
        }
        if ('a'<=c && c<='z')
            c =+ 'A' - 'a';     /* Convert to uppercase */
    }
```

For uppercase-only terminals (LCASE), convert lowercase to uppercase and escape special characters.

```c
    if (c=='\n' && rtp->t_flags&CRMOD)
        ttyoutput('\r', rtp);
    if (putc(c, &rtp->t_outq))
        return;
```

Add carriage return before newline if CRMOD. Put character on output queue.

```c
    colp = &rtp->t_col;
    ctype = partab[c];
    c = 0;
    switch (ctype&077) {

    case 0:                     /* ordinary */
        (*colp)++;
        break;

    case 1:                     /* non-printing */
        break;

    case 2:                     /* backspace */
        if (*colp)
            (*colp)--;
        break;

    case 3:                     /* newline */
        if (*colp)
            c = max((*colp>>4) + 3, 6);
        *colp = 0;
        break;

    case 4:                     /* tab */
        *colp =| 07;
        (*colp)++;
        break;

    case 6:                     /* carriage return */
        c = 6;
        *colp = 0;
    }
    if (c && (rtp->t_flags&NODELAY)==0)
        putc(c|0200, &rtp->t_outq);
}
```

Track column position and insert delays. Mechanical terminals need time for:
- Carriage return (6 character times)
- Newline (depends on column position)
- Tab (depends on position)

Delay characters have bit 0200 set.

### ttwrite() — Write to TTY

```c
/* tty.c */
ttwrite(atp)
struct tty *atp;
{
    register struct tty *tp;
    register int c;

    tp = atp;
    while ((c=cpass())>=0) {
        spl5();
        while (tp->t_outq.c_cc > TTHIWAT) {
            ttstart(tp);
            sleep(&tp->t_outq, TTOPRI);
        }
        spl0();
        ttyoutput(c, tp);
    }
    ttstart(tp);
}
```

Get characters from user space via `cpass()`. If the output queue exceeds TTHIWAT (50 chars), sleep until it drains to TTLOWAT (30). This provides flow control.

### ttstart() — Start Output

```c
/* tty.c */
ttstart(atp)
struct tty *atp;
{
    register int *addr, c;
    register struct tty *tp;

    tp = atp;
    addr = tp->t_addr;
    if (tp->t_state&SSTART) {
        (*addr.func)(tp);       /* Special start routine */
        return;
    }
    if ((addr->tttcsr&DONE)==0 || tp->t_state&TIMEOUT)
        return;                 /* Device busy or delay pending */
```

```c
    if ((c=getc(&tp->t_outq)) >= 0) {
        if (c<=0177)
            addr->tttbuf = c | (partab[c]&0200);
        else {
            timeout(ttrstrt, tp, c&0177);
            tp->t_state =| TIMEOUT;
        }
    }
}
```

Get a character from the output queue. If it's a real character (≤0177), send it to the device with parity. If it's a delay (>0177), set a timeout.

## The KL-11 Console Driver

The KL-11 is the console terminal interface:

### klopen() — Open Console

```c
/* kl.c */
klopen(dev, flag)
{
    register *addr;
    register struct tty *tp;

    if(dev.d_minor >= NKL11) {
        u.u_error = ENXIO;
        return;
    }
    tp = &kl11[dev.d_minor];
    tp->t_quit = 034;           /* Ctrl-\ */
    tp->t_intrup = 0177;        /* DEL */
```

Set default control characters.

```c
    if (u.u_procp->p_ttyp == 0)
        u.u_procp->p_ttyp = tp;
```

If process has no controlling terminal, this becomes it.

```c
    addr = KLADDR;
    if(dev.d_minor)
        addr = KLBASE-8 + 8*dev.d_minor;
    tp->t_addr = addr;
    tp->t_flags = XTABS|LCASE|ECHO|CRMOD;
    tp->t_state = CARR_ON;
    addr->klrcsr =| IENABLE|DSRDY|RDRENB;
    addr->kltcsr =| IENABLE;
}
```

Set device address, default flags, and enable interrupts.

### klrint() — Receive Interrupt

```c
/* kl.c */
klrint(dev)
{
    register int c, *addr;
    register struct tty *tp;

    tp = &kl11[dev.d_minor];
    addr = tp->t_addr;
    c = addr->klrbuf;
    addr->klrcsr =| RDRENB;     /* Re-enable receiver */
    if ((c&0177)==0)
        addr->kltbuf = c;       /* Hardware botch workaround */
    ttyinput(c, tp);
}
```

Read character from device, re-enable receiver, pass to `ttyinput()`.

### klxint() — Transmit Interrupt

```c
/* kl.c */
klxint(dev)
{
    register struct tty *tp;

    tp = &kl11[dev.d_minor];
    ttstart(tp);
    if (tp->t_outq.c_cc == 0 || tp->t_outq.c_cc == TTLOWAT)
        wakeup(&tp->t_outq);
}
```

Transmit complete—start next character and wake writers if queue has drained.

### klsgtty() — Get/Set TTY Parameters

```c
/* kl.c */
klsgtty(dev, v)
int *v;
{
    register struct tty *tp;

    tp = &kl11[dev.d_minor];
    if (v)
        v[2] = tp->t_flags;     /* Get: return flags */
    else {
        wflushtty(tp);
        tp->t_flags = u.u_arg[2]; /* Set: change flags */
    }
}
```

Used by `stty` and `gtty` system calls.

## Flow Control

```
                    TTHIWAT (50)
                        │
Output Queue ──────────┼──────────── ttwrite() sleeps
                        │
                    TTLOWAT (30)
                        │
                   ─────┼──────────── klxint() wakes writers
                        │
                        0
```

When the output queue exceeds 50 characters, writers sleep. When it drops to 30 or below, they're awakened. This prevents fast writers from flooding slow terminals.

## Uppercase-Only Terminals

Many early terminals only had uppercase letters. LCASE mode provides bidirectional mapping:

**Input**: `HELLO` → `hello`

**Output**: `hello` → `HELLO`, `{` → `\(`, `}` → `)`, etc.

The `maptab[]` array handles escape sequences like `\{` → `{`.

## Signal Generation

```c
if ((t_flags&RAW)==0 && (c==tp->t_quit || c==tp->t_intrup)) {
    signal(tp, c==tp->t_intrup? SIGINT:SIGQIT);
    flushtty(tp);
    return;
}
```

In cooked mode:
- **DEL** (0177) → SIGINT (interrupt)
- **Ctrl-\** (034) → SIGQIT (quit with core dump)

The `signal()` function sends the signal to all processes with this controlling terminal.

## Summary

- **Three queues**: raw (unedited), canonical (edited), output
- **Cooked mode**: Line editing, echo, signal generation
- **Raw mode**: Unprocessed I/O for special applications
- **Flow control**: TTHIWAT/TTLOWAT prevent output flooding
- **Delays**: Mechanical timing for print head movement
- **LCASE**: Support for uppercase-only terminals

## Key Design Points

1. **Interrupt-driven**: Characters processed in interrupt handlers, minimal latency.

2. **Queue-based**: Decouples user processes from hardware timing.

3. **Modal**: RAW vs cooked mode serves different application needs.

4. **Device-independent**: Common code in tty.c, device-specific in kl.c.

5. **Character blocks**: Dynamic allocation avoids fixed buffer sizes.

## Experiments

1. **RAW mode**: Write a program that reads single characters without echo.

2. **Change control characters**: Use `stty` to change erase from # to backspace.

3. **Overflow behavior**: Send more than TTYHOG characters without newlines.

4. **Flow control**: Write rapidly to a slow terminal and observe sleeping.

## Further Reading

- Chapter 14: Block Devices — Contrasts with character device model
- Chapter 7: Traps and System Calls — Signal delivery mechanism

---

**Next: Chapter 14 — Block Devices**
