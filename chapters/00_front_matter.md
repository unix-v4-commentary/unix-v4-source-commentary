# The UNIX Fourth Edition Source Code Commentary {-}

**A Complete Guide to Understanding the UNIX v4 Operating System**

*Based on the original Bell Labs source code by Ken Thompson and Dennis Ritchie*[^tape-date]

[^tape-date]: UNIX Fourth Edition was released in November 1973. The source code in this book comes from a tape sent to the University of Utah in June 1974, containing the V4 distribution with minor updates. See Ken Thompson's letter to Martin Newell dated May 31, 1974.

---

## About This Book {-}

This book provides a comprehensive, line-by-line commentary on the UNIX Fourth Edition source code. UNIX v4 represents one of the most elegant and influential pieces of software ever written—an entire operating system in roughly 10,000 lines of code that you can actually understand.

Unlike modern operating systems with millions of lines of code, UNIX v4 is small enough for one person to comprehend completely. This book will guide you through every major component, explaining not just *what* the code does, but *why* it was designed that way.

### Why UNIX v4?

UNIX Fourth Edition (November 1973)[^v4-date] occupies a unique position in computing history:

[^v4-date]: The fourth edition was released in November 1973. The tape recovered from the University of Utah was sent in June 1974. See the [TUHS Wiki](https://wiki.tuhs.org/doku.php?id=systems:4th_edition) for edition timeline.

- **First C-based UNIX** — While earlier versions were written in assembly, v4 was rewritten in C, making it the ancestor of all modern UNIX systems
- **Complete and comprehensible** — The entire kernel fits in about 9,000 lines of C and assembly
- **Mature yet minimal** — It includes multiprocessing, a hierarchical filesystem, device drivers, and a shell, but without the complexity that accumulated in later versions
- **Influential design** — The concepts introduced here (everything is a file, small tools that compose, simple process model) became the foundation of modern operating systems

### Prerequisites

To get the most from this book, you should have:

- **Basic C programming knowledge** — You don't need to be an expert, but you should understand pointers, structures, and function calls
- **Understanding of fundamental OS concepts** — Processes, files, memory allocation, and the distinction between user and kernel mode
- **Familiarity with assembly language** — Helpful but not required; we explain the PDP-11 assembly as we encounter it

### What You Will Learn

By the end of this book, you will understand:

- How an operating system boots and initializes itself
- How processes are created, scheduled, and terminated
- How the filesystem stores and retrieves data
- How system calls transfer control between user programs and the kernel
- How device drivers interface hardware to the rest of the system
- How the shell parses and executes commands
- How the C compiler transforms source code into executables

### Source Files Location

All source code references are relative to the `unix_v4/` directory:

```
unix_v4/
├── usr/sys/             # Kernel source
│   ├── ken/             # Ken Thompson's kernel code
│   │   ├── main.c       # Kernel entry point
│   │   ├── slp.c        # Process scheduling, sleep/wakeup
│   │   ├── trap.c       # Trap and interrupt handling
│   │   ├── sys1.c       # fork, exec, exit, wait
│   │   ├── sys2.c       # open, read, write, close
│   │   ├── sys3.c       # seek, stat, dup
│   │   ├── sys4.c       # chmod, chown, time, etc.
│   │   ├── rdwri.c      # readi(), writei()
│   │   ├── fio.c        # File descriptor operations
│   │   ├── iget.c       # Inode operations
│   │   ├── nami.c       # Path name resolution (namei)
│   │   ├── alloc.c      # Disk block allocation
│   │   ├── clock.c      # Clock interrupt handler
│   │   └── sig.c        # Signal handling
│   ├── dmr/             # Dennis Ritchie's device drivers
│   │   ├── bio.c        # Buffer cache
│   │   ├── tty.c        # Terminal line discipline
│   │   ├── kl.c         # Console driver
│   │   ├── rk.c         # RK05 disk driver
│   │   ├── mem.c        # Memory devices (/dev/mem, /dev/null)
│   │   ├── malloc.c     # Core memory allocator
│   │   └── pipe.c       # Pipe implementation
│   ├── conf/            # Configuration and machine-dependent code
│   │   ├── low.s        # Interrupt vectors
│   │   └── mch.s        # Machine-dependent assembly
│   └── *.h              # Header files (proc.h, user.h, inode.h, etc.)
├── usr/source/          # User programs
│   ├── s1/              # Section 1 - User commands (cat, ls, echo)
│   ├── s2/              # Section 2 - System utilities (sh, login, init)
│   ├── s3/              # Section 3 - Libraries
│   └── s7/              # Section 7 - Miscellaneous
├── usr/c/               # C compiler source
│   ├── c0*.c            # Compiler pass 0 (lexer, parser)
│   └── c1*.c            # Compiler pass 1 (code generator)
├── bin/                 # Binary executables
├── lib/                 # Libraries and compiler passes
└── etc/                 # System configuration (init, passwd)
```

### Reading This Book

Each chapter follows a consistent structure:

1. **Overview** — What the chapter covers and why it matters
2. **Source Files** — Which files we'll examine
3. **Prerequisites** — What you should understand first
4. **Concepts** — Background needed to understand the code
5. **Code Walkthrough** — Line-by-line analysis of key functions
6. **Key Data Structures** — Annotated structure definitions
7. **How It All Fits Together** — Diagrams and explanations
8. **Experiments** — Things to try yourself
9. **Summary** — Key takeaways
10. **Further Reading** — Related chapters and external resources

### Notation Conventions

Throughout this book:

- `function()` — Function names appear in monospace with parentheses
- `variable` — Variable and structure names appear in monospace
- `file.c:123` — File references include line numbers where helpful
- `0177776` — Octal numbers (common in PDP-11 code) start with 0
- **Bold** — Key terms on first introduction
- *Italic* — Emphasis or book/paper titles

### A Note on the C Dialect

The C in UNIX v4 predates the 1978 K&R standard. You'll notice:

```c
/* Assignment operators are reversed */
x =+ 1;    /* Modern: x += 1 */
x =| 4;    /* Modern: x |= 4 */
x =- y;    /* Modern: x -= y (ambiguous with x = -y!) */

/* No void type - functions return int by default */
sleep(chan, pri)    /* No return type declaration */
{
    ...
}

/* Parameter types declared separately */
sleep(chan, pri)
int chan;           /* Parameter type declarations */
int pri;            /* after the parameter list */
{
    ...
}

/* =0 initializes to zero */
int x 0;            /* Modern: int x = 0; */
```

We'll point out these differences as they arise.

### Acknowledgments

**The Original Authors**

- **Ken Thompson and Dennis Ritchie** — For creating UNIX and making computing what it is today
- **Bell Labs** — For fostering an environment where this work could flourish

**The UNIX v4 Tape Recovery**

The source code studied in this book comes from a magnetic tape sent from Ken Thompson to Martin Newell at the University of Utah in June 1974. Newell was conducting pioneering computer graphics research (including the Utah Teapot). The tape survived because Jay Lepreau held onto it when it would have been discarded; it was rediscovered among his papers in July 2025.

Timeline of recovery (from Angelo Papenhoff's 39C3 presentation):

- **June 1974** — Tape sent from Ken Thompson to Martin Newell
- **Jay Lepreau** — Saved the tape from being discarded (found among his papers)
- **28 July 2025** — Found by Aleks Maricq (University of Utah)
- **Rob Ricci** (University of Utah) — Spread the word about the discovery
- **Thalia Archibald** (University of Utah) — Researched the tape's background and history
- **18 Dec 2025** — Driven to the Computer History Museum by Jon Duerig
- **19 Dec 2025** — Read and uploaded to archive.org by Al Kossow, Len Shustek, and Thalia Archibald
- **20 Dec 2025** — Booted on emulator by Angelo Papenhoff (squoze.net)
- **24 Dec 2025** — Booted on real PDP-11/45 by Jacob Ritorto
- **26 Dec 2025** — Booted on real PDP-11/40 by Ashlin Inwood

**Archives and Community**

- **The Computer History Museum** — For preserving this important history
- **The Internet Archive** — For hosting the recovered tape image ([utah_unix_v4_raw](https://archive.org/details/utah_unix_v4_raw))
- **The UNIX Heritage Society** — For maintaining archives of early UNIX
- **squoze.net** — For the UNIX v4 restoration and emulation documentation ([squoze.net/UNIX/v4](http://squoze.net/UNIX/v4/))

**This Book**

- **Thalia Archibald** — For historical corrections and feedback
- **Warren Toomey** — For technical corrections and feedback

---

*"UNIX is basically a simple operating system, but you have to be a genius to understand the simplicity."*
— Dennis Ritchie

---

## How to Use This Book {-}

### For Sequential Reading

If you're new to operating systems internals, read the chapters in order. Part I provides essential background, Part II covers the kernel core, and each subsequent part builds on what came before.

### For Reference

If you're already familiar with operating systems and want to understand specific subsystems, each chapter is relatively self-contained. Use the cross-references to fill in background as needed.

### With the Source Code

This book is meant to be read alongside the actual source code. Keep the `unix_v4/` directory open and follow along. The code is small enough that you can (and should) read all of it.

---

**Let's begin.**
