# Chapter 1: Introduction

## Overview

Before we dive into the source code, we need to understand the world that created UNIX. The design decisions in UNIX v4 weren't made in a vacuum—they were shaped by the hardware constraints of 1973, the culture of Bell Labs, and the hard lessons learned from Multics. Understanding this context transforms the code from a historical artifact into a masterclass in pragmatic engineering.

This chapter covers the history and philosophy behind UNIX, setting the stage for everything that follows.

## Prerequisites

None—this is where we begin.

## The Birth of UNIX

### From Multics to UNIX

In 1964, MIT, General Electric, and Bell Labs began an ambitious project called **Multics** (Multiplexed Information and Computing Service). The goal was to create a computing utility—a system that would provide computing power like a utility company provides electricity, serving hundreds of users simultaneously.

Multics was revolutionary in concept but troubled in execution. It aimed to do everything: security, reliability, hierarchical filesystems, dynamic linking, and more. By 1969, Bell Labs withdrew from the project. It was over budget, behind schedule, and growing increasingly complex.

But two researchers who had worked on Multics—**Ken Thompson** and **Dennis Ritchie**—had tasted what a good operating system could be. They wanted something simpler.

### Space Travel and the PDP-7

Ken Thompson had written a game called "Space Travel" that simulated the solar system. Running it on the GE-635 mainframe cost $75 per game in computer time. Thompson found a little-used **PDP-7** minicomputer and decided to port his game to it.

To make development easier, he needed an operating system. Over a few weeks in 1969, Thompson wrote a simple filesystem, a process model, a command interpreter, and a few utilities. His wife took the kids to visit her parents for a month; Thompson allocated one week each to the kernel, the shell, the editor, and the assembler.

This was UNIX—though it wasn't called that yet. The name came from Brian Kernighan as a pun on Multics: where Multics was "multiplexed," UNIX was "uniplexed," doing one thing well.

### The PDP-11 and the Rewrite

In 1970, the Computing Science Research Center at Bell Labs acquired a **PDP-11/20**. The PDP-11 was a revolutionary machine—clean architecture, orthogonal design, and a memory management unit that could support multiple users.

Thompson rewrote UNIX for the PDP-11. But assembly language was tedious, and the system was hard to modify. Thompson wanted a high-level language.

He tried FORTRAN first—it was a disaster. Then he created a language called **B**, based on BCPL. B was typeless, which worked fine on word-addressed machines but poorly on the byte-addressed PDP-11.

Dennis Ritchie extended B into **C**, adding types, structures, and other features. In 1973, Thompson and Ritchie rewrote UNIX in C—the system we're studying in this book.

### Why This Version Matters

UNIX v4 (November 1973)[^v4-release] is special:

[^v4-release]: UNIX v4 was released November 1973. The source code studied in this book comes from a tape sent to Martin Newell at the University of Utah in June 1974. See Thalia Archibald's research at [unix-history](https://github.com/thaliaarchi/unix-history/blob/main/users/utah/v4.md).

1. **First C version** — This is where UNIX became portable and where C proved itself as a systems programming language

2. **Minimal but complete** — It has multiprocessing, a hierarchical filesystem, device drivers, pipes, and a shell. Yet the kernel is under 9,000 lines of C.

3. **Before the accretion** — Later versions added networking, virtual memory, and hundreds of other features. v4 has the core ideas without the cruft.

4. **The design crystallized** — The fundamental architecture that would influence all future UNIX systems was established by v4.

## The Bell Labs Environment

Understanding UNIX requires understanding Bell Labs in the early 1970s.

### The Research Culture

Bell Labs was a unique institution. AT&T's telephone monopoly generated enormous profits, a portion of which funded fundamental research with no expectation of immediate commercial return. Researchers had freedom to pursue interesting problems.

The Computing Science Research Center (Department 1127) was particularly unusual. It had about a dozen researchers, no hierarchy to speak of, and no product deadlines. Thompson, Ritchie, and their colleagues could spend years on work that might never ship.

This freedom produced remarkable results: the transistor, information theory, the laser, and UNIX all came from Bell Labs.

### Constraints and Creativity

But freedom didn't mean unlimited resources. The PDP-11/20 had:

- **24KB of memory** (later systems had more, but not much)
- **A 2.5MB RK05 disk pack**
- **No memory protection** initially (MMU came with PDP-11/40 and /45)
- **No virtual memory** — What you had was what you got

These constraints forced elegant solutions. When you can't add more code, you make the code you have work harder. Every data structure in UNIX v4 is minimal. Every algorithm is simple. There's no room for bloat.

### The Users

UNIX was used for real work at Bell Labs. The first killer app was text processing—Thompson and Ritchie convinced management to buy a PDP-11 by promising to develop a document preparation system for the patents department.

The users were sophisticated programmers who could (and did) read the source code. When something was wrong, they fixed it. This tight feedback loop between developers and users produced a system refined through daily use.

## Design Philosophy

UNIX embodies a coherent design philosophy that emerged from Thompson and Ritchie's Multics experience and the constraints they worked within.

### Simplicity

The overriding principle is simplicity. When in doubt, leave it out. When forced to add something, add the simplest thing that could possibly work.

Consider the process model. A process has a process ID, a parent process ID, memory, open files, and not much else. There's no process priority inheritance, no real-time scheduling, no mandatory access control. Just the basics.

Or consider the filesystem. Files are byte streams—the system doesn't know or care about record formats. Directories are files that contain names and inode numbers. That's it.

### Everything is a File

In UNIX, almost everything is accessed through the file interface: open, read, write, close. This includes:

- Regular files on disk
- Directories
- Devices (terminals, disks, printers)
- Inter-process communication (pipes)

This unification means programs don't need special cases for different kinds of I/O. `cat` doesn't know if it's reading from a file or a terminal or a pipe—and it doesn't need to.

### Small, Sharp Tools

UNIX encourages small programs that do one thing well. Instead of one large program that does everything, you have many small programs that can be combined.

This is made possible by two innovations:

1. **Text streams** — Programs communicate through streams of text, not binary formats
2. **Pipes** — The output of one program can be connected to the input of another

```
who | wc -l      # Count logged-in users
ls | grep foo    # Find files matching "foo"
```

### Worse is Better

Richard Gabriel later characterized the UNIX philosophy as "worse is better"—a design that is simpler but less complete will often be more successful than one that is more complex but more correct.

Consider error handling. In UNIX, system calls that fail return -1 and set a global error code. The caller must check every return value. This is inconvenient, error-prone, and not at all elegant.

But it's simple. The kernel doesn't need complex exception handling. User programs can ignore errors if they want. And in practice, it works well enough.

This philosophy runs throughout UNIX:

- The shell is simple (no job control in v4)
- The filesystem is simple (no permissions more complex than read/write/execute)
- The process model is simple (no threads, just processes)

Is this worse? In some sense, yes. Is it better? In practice, often yes—because simple systems are easier to understand, implement, debug, and extend.

## The Cast of Characters

UNIX was created primarily by two people, with significant contributions from others.

### Ken Thompson

Thompson wrote the first UNIX on the PDP-7, then rewrote it for the PDP-11. He created the B programming language, the first UNIX shell, and many core utilities. In the source code, files in `usr/sys/ken/` contain Thompson's kernel code.

Thompson's code is characterized by extreme brevity. Functions are short, variable names are terse, and there's no wasted motion. Looking at `slp.c` (sleep/wakeup and scheduling), you'll see algorithms so tight they border on cryptic—until you understand them, and then they seem inevitable.

### Dennis Ritchie

Ritchie created the C programming language and rewrote much of UNIX in it. His code lives in `usr/sys/dmr/` and includes the device drivers and buffer cache. Ritchie also wrote the definitive documentation for C and for UNIX.

Ritchie's code tends to be slightly more expansive than Thompson's, with more comments and clearer structure. The buffer cache (`bio.c`) is a model of clarity.

### Others

- **Brian Kernighan** — Named UNIX, contributed utilities, co-authored "The C Programming Language"
- **Doug McIlroy** — Invented pipes, led the research group
- **Joe Ossanna** — Created troff, the text formatter
- **Lorinda Cherry** — Statistical tools and document analysis

## What We'll Study

The UNIX v4 source code breaks down as follows:

### The Kernel (~9,000 lines)

```
usr/sys/ken/     # Thompson's kernel code
    main.c       # Boot and initialization
    slp.c        # Scheduling, context switch, sleep/wakeup
    trap.c       # Trap and interrupt handling
    sysent.c     # System call table
    sys1.c       # Process syscalls: fork, exec, exit, wait
    sys2.c       # File syscalls: open, read, write, close
    sys3.c       # More file: seek, dup, pipe
    sys4.c       # Misc: time, signal, stat
    fio.c        # File descriptor layer
    rdwri.c      # Inode read/write
    iget.c       # Inode cache
    nami.c       # Path resolution (namei)
    alloc.c      # Disk block allocation
    clock.c      # Clock interrupt handler
    sig.c        # Signals
    text.c       # Shared text segments
    subr.c       # bmap and other utilities
    prf.c        # printf for kernel

usr/sys/dmr/     # Ritchie's drivers and buffer cache
    bio.c        # Buffer cache
    tty.c        # Terminal handling
    kl.c         # Console driver
    rk.c         # RK05 disk driver
    mem.c        # /dev/mem, /dev/null
    malloc.c     # Core memory allocator
    pipe.c       # Pipe implementation
    ...          # Other device drivers
```

### User Programs

```
usr/source/s2/sh.c       # The shell
usr/source/s1/cat.s      # cat in assembly
usr/source/s1/ls.s       # ls in assembly
usr/c/                   # The C compiler
```

### Header Files

```
usr/sys/param.h    # System parameters
usr/sys/proc.h     # Process structure
usr/sys/user.h     # User structure (u.)
usr/sys/inode.h    # Inode structure
usr/sys/buf.h      # Buffer structure
usr/sys/file.h     # Open file table
usr/sys/filsys.h   # Superblock structure
usr/sys/tty.h      # Terminal structure
```

## Summary

- UNIX emerged from the Multics project, preserving the good ideas while discarding the complexity
- Ken Thompson created UNIX in 1969 on a PDP-7; it was rewritten in C for the PDP-11 in 1973
- UNIX v4 is the first C-based version—complete, minimal, and comprehensible
- The Bell Labs environment provided freedom and constraints that shaped the design
- The UNIX philosophy emphasizes simplicity, the file abstraction, and composable tools
- The source code we'll study is about 9,000 lines of kernel code plus user programs

## Further Reading

- Ritchie, D.M. and Thompson, K., "The UNIX Time-Sharing System," Communications of the ACM, July 1974
- Ritchie, D.M., "The Evolution of the Unix Time-sharing System," AT&T Bell Laboratories Technical Journal, October 1984
- Kernighan, B. and Pike, R., "The Unix Programming Environment," Prentice-Hall, 1984
- Salus, P., "A Quarter Century of UNIX," Addison-Wesley, 1994

---

**Next: Chapter 2 — The PDP-11 Architecture**
