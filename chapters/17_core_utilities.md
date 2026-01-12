# Chapter 17: Core Utilities

## Overview

UNIX comes with dozens of small, focused utilities that work together through pipes and files. This chapter examines four representative programs spanning the spectrum from tiny assembly routines to substantial C applications. Together they demonstrate the UNIX philosophy: simple tools that do one thing well.

## Source Files

| File | Lines | Language | Purpose |
|------|-------|----------|---------|
| `usr/source/s1/echo.c` | 10 | C | Print arguments |
| `usr/source/s1/cat.s` | 65 | Assembly | Concatenate files |
| `usr/source/s1/cp.c` | 80 | C | Copy files |
| `usr/source/s1/ls.c` | 428 | C | List directory |

## Prerequisites

- Chapter 2: PDP-11 Architecture (for assembly)
- Chapter 7: System Calls (`open`, `read`, `write`, `stat`)

## echo — The Simplest Utility

```c
main(argc, argv)
int argc;
char *argv[];
{
    int i;

    argc--;
    for(i=1; i<=argc; i++)
        printf("%s%c", argv[i], i==argc? '\n': ' ');
}
```

Ten lines. Print each argument separated by spaces, end with newline. This is the essence of UNIX utilities—do exactly one thing.

**Usage:**
```
$ echo hello world
hello world
```

## cat — Concatenate Files (Assembly)

`cat` is written in assembly for efficiency—it's used constantly:

```assembly
/ cat -- concatenate files

    mov  (sp)+,r5        / r5 = argc
    tst  (sp)+           / skip argv[0]
    mov  $obuf,r2        / r2 = output buffer pointer
    cmp  r5,$1
    beq  3f              / no args: read stdin

loop:
    dec  r5
    ble  done            / no more files
    mov  (sp)+,r0        / r0 = next filename
    cmpb (r0),$'-
    bne  2f
    clr  fin             / "-" means stdin
    br   3f
2:
    mov  r0,0f
    sys  open; 0:..; 0   / open file
    bes  loop            / error: skip file
    mov  r0,fin
```

The main loop opens each file argument (or uses stdin for "-").

```assembly
3:
    mov  fin,r0
    sys  read; ibuf; 512.  / read up to 512 bytes
    bes  3f                / error or EOF
    mov  r0,r4             / r4 = bytes read
    beq  3f                / EOF
    mov  $ibuf,r3
4:
    movb (r3)+,r0          / get byte
    jsr  pc,putc           / output it
    dec  r4
    bne  4b                / loop until done
    br   3b                / read more
3:
    mov  fin,r0
    beq  loop              / stdin: don't close
    sys  close
    br   loop
```

Read 512 bytes at a time, output byte by byte through `putc`.

```assembly
putc:
    movb r0,(r2)+          / store in output buffer
    cmp  r2,$obuf+512.
    blo  1f                / buffer not full
    mov  $1,r0
    sys  write; obuf; 512. / flush buffer
    mov  $obuf,r2
1:
    rts  pc
```

Output is buffered—write 512 bytes at a time for efficiency.

```assembly
done:
    sub  $obuf,r2
    beq  1f                / nothing to flush
    mov  r2,0f
    mov  $1,r0
    sys  write; obuf; 0:.. / flush remaining
1:
    sys  exit

    .bss
ibuf: .=.+512.             / input buffer
obuf: .=.+512.             / output buffer
fin:  .=.+2                / current input fd
```

**Key points:**
- Buffered I/O for performance
- Handles multiple files
- "-" means stdin
- ~65 lines of tight assembly

## cp — Copy Files

```c
main(argc,argv)
char **argv;
{
    int buf[256];
    int fold, fnew, n, ct;
    char *p1, *p2, *bp;
    int mode;

    if(argc != 3) {
        write(1, "Usage: cp oldfile newfile\n", 26);
        exit(1);
    }
```

Basic argument checking.

```c
    if((fold = open(argv[1], 0)) < 0) {
        write(1, "Cannot open old file.\n", 22);
        exit(1);
    }
    fstat(fold, buf);
    mode = buf[2];          /* Preserve file mode */
```

Open source file and get its mode (permissions).

```c
    if((fnew = creat(argv[2], mode)) < 0){
        stat(argv[2], buf);
        if((buf[2] & 060000) == 040000) {
            /* Destination is a directory */
            p1 = argv[1];
            p2 = argv[2];
            bp = buf;
            while(*bp++ = *p2++);
            bp[-1] = '/';
            p2 = bp;
            while(*bp = *p1++)
                if(*bp++ == '/')
                    bp = p2;
            /* Now buf = "dir/basename" */
            if((fnew = creat(buf, mode)) < 0) {
                write(1, "Cannot creat new file.\n", 23);
                exit(1);
            }
        } else {
            write(1, "Cannot creat new file.\n", 23);
            exit(1);
        }
    }
```

Create destination. If it's a directory, append the source filename.

```c
    while(n = read(fold, buf, 512)) {
        if(n < 0) {
            write(1, "Read error\n", 11);
            exit(1);
        }
        if(write(fnew, buf, n) != n){
            write(1, "Write error.\n", 13);
            exit(1);
        }
    }
    exit(0);
}
```

Copy loop: read 512 bytes, write them, repeat until EOF.

**Key points:**
- Preserves file permissions
- Handles "cp file dir/" case
- 512-byte block copies
- Error checking at each step

## ls — List Directory

`ls` is the most complex utility here at 428 lines. It demonstrates:
- Option parsing
- Directory reading
- stat() for file info
- Sorting
- Formatted output

### Option Parsing

```c
main(argc, argv)
char **argv;
{
    if (--argc > 0 && *argv[1] == '-') {
        argv++;
        while (*++*argv) switch (**argv) {
        case 'a':
            aflg++;         /* Show hidden files */
            continue;
        case 's':
            sflg++;         /* Show sizes */
            statreq++;
            continue;
        case 'l':
            lflg++;         /* Long format */
            statreq++;
            uidfil = open("/etc/passwd", 0);
            continue;
        case 'r':
            rflg = -1;      /* Reverse sort */
            continue;
        case 't':
            tflg++;         /* Sort by time */
            statreq++;
            continue;
        /* ... more options ... */
        }
    }
```

Classic UNIX option style: single dash, single letters, can be combined (`ls -la`).

### Reading Directories

```c
readdir(dir)
char *dir;
{
    static struct {
        int   dinode;
        char  dname[14];
    } dentry;

    if (fopen(dir, &inf) < 0) {
        printf("%s unreadable\n", dir);
        return;
    }
    for(;;) {
        p = &dentry;
        for (j=0; j<16; j++)
            *p++ = getc(&inf);     /* Read 16-byte entry */
        if (dentry.dinode==0       /* Empty slot */
         || aflg==0 && dentry.dname[0]=='.')
            continue;              /* Skip hidden */
        if (dentry.dinode == -1)
            break;                 /* End of directory */
        ep = gstat(makename(dir, dentry.dname), 0);
        /* ... store entry ... */
    }
}
```

Directories are just files with 16-byte entries (2-byte inode + 14-byte name).

### Getting File Information

```c
gstat(file, argfl)
char *file;
{
    struct ibuf statb;
    register struct lbuf *rep;

    if (stat(file, &statb)<0) {
        printf("%s not found\n", file);
        return(0);
    }
    rep->lnum = statb.inum;
    rep->lflags = statb.iflags;
    rep->luid = statb.iuid;
    rep->lsize = statb.isize;
    rep->lmtime[0] = statb.imtime[0];
    rep->lmtime[1] = statb.imtime[1];
    /* ... */
}
```

The `stat()` system call fills in file metadata: type, permissions, owner, size, times.

### Formatting Output

```c
pentry(ap)
struct lbuf *ap;
{
    if (iflg)
        printf("%5d ", p->lnum);       /* Inode number */
    if (lflg) {
        pmode(p->lflags);              /* -rwxr-xr-x */
        printf("%2d ", p->lnl);        /* Link count */
        /* ... owner, size, date ... */
    }
    printf("%.14s\n", p->lname);       /* Filename */
}
```

### Permission Display

```c
int m0[] { 3, DIR, 'd', BLK, 'b', CHR, 'c', '-'};
int m1[] { 1, ROWN, 'r', '-' };
int m2[] { 1, WOWN, 'w', '-' };
int m3[] { 2, SUID, 's', XOWN, 'x', '-' };
/* ... */

pmode(aflag)
{
    register int **mp;
    flags = aflag;
    for (mp = &m[0]; mp < &m[10];)
        select(*mp++);
}
```

Clever table-driven approach to print `-rwxr-xr-x` style permissions.

## System Call Patterns

### Error Handling

```c
/* Typical pattern */
if((fd = open(file, 0)) < 0) {
    write(2, "error message\n", n);
    exit(1);
}
```

### Reading Files

```c
/* Block-at-a-time */
while((n = read(fd, buf, 512)) > 0) {
    /* process n bytes in buf */
}
```

### Writing Output

```c
/* Direct write */
write(1, string, length);

/* Using printf (links with library) */
printf("%s\n", string);
```

## Assembly vs C Trade-offs

| Aspect | Assembly (cat) | C (ls) |
|--------|----------------|--------|
| Size | ~300 bytes | ~4KB |
| Speed | Optimal | Good |
| Maintenance | Difficult | Easy |
| Portability | PDP-11 only | Somewhat portable |

Assembly was used for:
- Frequently-used utilities (cat, echo)
- Performance-critical code
- Tiny programs where every byte mattered

C was used for:
- Complex logic (ls, cp with directory handling)
- Maintainability requirements
- Less performance-critical utilities

## The UNIX Philosophy

These utilities embody key principles:

1. **Do one thing well**: `cat` concatenates, `cp` copies, `echo` echoes
2. **Text streams**: Programs read/write text, enabling pipes
3. **Composability**: `cat file | grep pattern | wc -l`
4. **No unnecessary output**: Silent on success
5. **Meaningful exit codes**: 0 for success, non-zero for error

## Summary

- **echo**: 10 lines—print arguments
- **cat**: 65 lines assembly—buffered file concatenation
- **cp**: 80 lines—copy with directory handling
- **ls**: 428 lines—full-featured directory listing

## Experiments

1. **Add an option**: Add `-n` to `cat` to number lines.

2. **Trace system calls**: Count `read`/`write` calls in `cat` for various file sizes.

3. **Benchmark**: Compare `cat` performance with a C version.

4. **Extend ls**: Add color coding for file types.

## Further Reading

- Chapter 16: The Shell — How utilities are invoked
- Chapter 7: System Calls — The `open`/`read`/`write` interface
- Chapter 11: Path Resolution — How files are found

---

**Next: Chapter 18 — The C Compiler**
