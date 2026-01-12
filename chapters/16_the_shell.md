# Chapter 16: The Shell

## Overview

The shell is the user's interface to UNIX—a program that reads commands, parses them, and executes them. In about 800 lines of C, it implements command execution, I/O redirection, pipes, background processes, and shell scripts. The shell's elegance comes from its simplicity: it's just another user program that happens to orchestrate other programs.

## Source Files

| File | Purpose |
|------|---------|
| `usr/source/s2/sh.c` | The complete shell |

## Prerequisites

- Chapter 5: Process Management (`fork`, `exec`, `wait`)
- Chapter 7: Traps and System Calls (signals)
- Chapter 10: File I/O (file descriptors, `dup`)

## Shell Overview

The shell is a loop:
1. Print prompt
2. Read a line
3. Parse into a syntax tree
4. Execute the tree
5. Repeat

```c
loop:
    if(promp != 0)
        prs(promp);
    peekc = getc();
    main1();
    goto loop;
```

## Data Structures

### Global State

```c
char *dolp;          /* Dollar expansion pointer */
char **dolv;         /* Argument vector ($1, $2...) */
int  dolc;           /* Argument count */
char *promp;         /* Prompt string (% or #) */
char *linep;         /* Current position in line buffer */
char **argp;         /* Current position in args array */
int  *treep;         /* Current position in tree buffer */
char peekc;          /* Lookahead character */
char error;          /* Syntax error flag */
char uid;            /* User ID (0 = root) */
char setintr;        /* Interactive mode flag */
```

### Syntax Tree Nodes

```c
/* Tree node layout */
#define dtyp 0       /* Node type */
#define dlef 1       /* Left child or input file */
#define drit 2       /* Right child or output file */
#define dflg 3       /* Flags */
#define dspr 4       /* Subshell pointer */
#define dcom 5       /* Command and arguments start here */

/* Node types */
#define tcom 1       /* Simple command */
#define tpar 2       /* Parenthesized subshell */
#define tfil 3       /* Pipeline */
#define tlst 4       /* List (cmd; cmd) */
```

## main() — Shell Startup

```c
main(c, av)
int c;
char **av;
{
    register f;
    register char *acname, **v;

    close(2);
    if((f=dup(1)) != 2)
        close(f);
```

Ensure stderr (fd 2) goes to the same place as stdout.

```c
    v = av;
    acname = "/usr/adm/sh_acct";
    promp = "% ";
    if(((uid = getuid())&0377) == 0) {
        promp = "# ";
        acname = "/usr/adm/su_acct";
    }
```

Set prompt: `%` for normal users, `#` for root.

```c
    if(c > 1) {
        promp = 0;              /* No prompt for scripts */
        close(0);
        f = open(v[1], 0);     /* Open script as stdin */
        if(f < 0) {
            prs(v[1]);
            err(": cannot open");
        }
    }
```

If given a filename argument, run it as a script.

```c
    if(**v == '-') {
        setintr++;
        signal(quit, 1);       /* Ignore quit */
        signal(intr, 1);       /* Ignore interrupt */
    }
    dolv = v+1;
    dolc = c-1;
```

Login shells (name starts with `-`) ignore signals. Set up `$1`, `$2`, etc.

## Lexical Analysis: word()

```c
word()
{
    register char c, c1;

    *argp++ = linep;

loop:
    switch(c = getc()) {

    case ' ':
    case '\t':
        goto loop;             /* Skip whitespace */

    case '\'':
    case '"':
        c1 = c;
        while((c=readc()) != c1) {
            if(c == '\n') {
                error++;
                peekc = c;
                return;
            }
            *linep++ = c|quote;  /* Mark as quoted */
        }
        goto pack;
```

Quoted strings: characters inside quotes are marked with the `quote` bit (0200) so metacharacters aren't treated specially.

```c
    case '&':
    case ';':
    case '<':
    case '>':
    case '(':
    case ')':
    case '|':
    case '^':
    case '\n':
        *linep++ = c;
        *linep++ = '\0';
        return;
    }
```

Metacharacters are returned as single-character tokens.

```c
    peekc = c;

pack:
    for(;;) {
        c = getc();
        if(any(c, " '\"\t;&<>()|^\n")) {
            peekc = c;
            if(any(c, "\"'"))
                goto loop;
            *linep++ = '\0';
            return;
        }
        *linep++ = c;
    }
}
```

Regular words: collect characters until a metacharacter or whitespace.

## getc() — Character Input with Expansion

```c
getc()
{
    register char c;

    if(peekc) {
        c = peekc;
        peekc = 0;
        return(c);
    }
```

Handle lookahead character.

```c
getd:
    if(dolp) {
        c = *dolp++;
        if(c != '\0')
            return(c);
        dolp = 0;
    }
```

If expanding a `$n` variable, return characters from it.

```c
    c = readc();
    if(c == '\\') {
        c = readc();
        if(c == '\n')
            return(' ');       /* Line continuation */
        return(c|quote);       /* Escaped character */
    }
    if(c == '$') {
        c = getc();
        if(c>='0' && c<='9') {
            if(c-'0' < dolc)
                dolp = dolv[c-'0'];
            goto getd;         /* Expand $n */
        }
    }
    return(c&0177);
}
```

Handle `\` escapes and `$1`, `$2`, etc. parameter expansion.

## Parsing: Recursive Descent

The parser builds a syntax tree using recursive descent:

### syntax() — Top Level

```c
syntax(p1, p2)
char **p1, **p2;
{
    while(p1 != p2) {
        if(any(**p1, ";&\n"))
            p1++;
        else
            return(syn1(p1, p2));
    }
    return(0);
}
```

Skip separators, parse command list.

### syn1() — Command Lists

```c
/*
 * syn1
 *    syn2
 *    syn2 & syntax
 *    syn2 ; syntax
 */
syn1(p1, p2)
char **p1, **p2;
{
    register char **p;
    register *t, *t1;
    int l;

    l = 0;
    for(p=p1; p!=p2; p++)
    switch(**p) {

    case '(':
        l++;
        continue;

    case ')':
        l--;
        continue;

    case '&':
    case ';':
    case '\n':
        if(l == 0) {
            t = tree(4);
            t[dtyp] = tlst;
            t[dlef] = syn2(p1, p);
            t[dflg] = 0;
            if(**p == '&') {
                t1 = t[dlef];
                t1[dflg] =| fand|fint;  /* Background */
            }
            t[drit] = syntax(p+1, p2);
            return(t);
        }
    }
    return(syn2(p1, p2));
}
```

Handle `;` (sequential) and `&` (background). Track parentheses depth.

### syn2() — Pipelines

```c
/*
 * syn2
 *    syn3
 *    syn3 | syn2
 */
syn2(p1, p2)
char **p1, **p2;
{
    char **p;
    int l, *t;

    l = 0;
    for(p=p1; p!=p2; p++)
    switch(**p) {

    case '(':
        l++;
        continue;

    case ')':
        l--;
        continue;

    case '|':
    case '^':
        if(l == 0) {
            t = tree(4);
            t[dtyp] = tfil;
            t[dlef] = syn3(p1, p);
            t[drit] = syn2(p+1, p2);
            return(t);
        }
    }
    return(syn3(p1, p2));
}
```

Handle `|` (pipe). Note `^` is also pipe (older syntax).

### syn3() — Simple Commands

```c
/*
 * syn3
 *    ( syn1 ) [ < in ] [ > out ]
 *    word word* [ < in ] [ > out ]
 */
syn3(p1, p2)
char **p1, **p2;
{
    /* ... parse redirections and command words ... */

    if(lp != 0) {
        /* Parenthesized subshell */
        t = tree(5);
        t[dtyp] = tpar;
        t[dspr] = syn1(lp, rp);
        goto out;
    }
    /* Simple command */
    t = tree(n+5);
    t[dtyp] = tcom;
    for(l=0; l<n; l++)
        t[l+dcom] = b[l];
out:
    t[dflg] = flg;
    t[dlef] = i;           /* Input redirect */
    t[drit] = o;           /* Output redirect */
    return(t);
}
```

Parse I/O redirections (`<`, `>`, `>>`) and collect command words.

## Execution: execute()

```c
execute(t, pf1, pf2)
int *t, *pf1, *pf2;
{
    int i, f, pv[2];
    register *t1;

    if(t != 0)
    switch(t[dtyp]) {

    case tcom:
        /* Simple command */
```

### Built-in Commands

```c
        cp1 = t[dcom];
        if(equal(cp1, "chdir")) {
            if(t[dcom+1] != 0) {
                if(chdir(t[dcom+1]) < 0)
                    err("chdir: bad directory");
            }
            return;
        }
        if(equal(cp1, "shift")) {
            dolv[1] = dolv[0];
            dolv++;
            dolc--;
            return;
        }
        if(equal(cp1, "login")) {
            execv("/bin/login", t+dcom);
            return;
        }
        if(equal(cp1, "wait")) {
            pwait(-1, 0);
            return;
        }
        if(equal(cp1, ":"))
            return;
```

Built-ins execute in the shell process itself (no fork).

### External Commands

```c
    case tpar:
        f = t[dflg];
        i = 0;
        if((f&fpar) == 0)
            i = fork();
        if(i == -1) {
            err("try again");
            return;
        }
        if(i != 0) {
            /* Parent */
            if((f&fand) != 0) {
                prn(i);
                prs("\n");
                return;
            }
            if((f&fpou) == 0)
                pwait(i, t);
            return;
        }
```

Fork a child process. Parent waits (unless `&`).

```c
        /* Child process */
        if(t[dlef] != 0) {
            close(0);
            i = open(t[dlef], 0);   /* Input redirect */
        }
        if(t[drit] != 0) {
            if((f&fcat) != 0) {
                i = open(t[drit], 1);
                seek(i, 0, 2);       /* Append */
            } else
                i = creat(t[drit], 0666);
            close(1);
            dup(i);
            close(i);
        }
```

Handle input/output redirection by manipulating file descriptors before exec.

```c
        execv(t[dcom], t+dcom);
        /* Try /bin/ and /usr/bin/ */
        cp1 = linep;
        cp2 = "/usr/bin/";
        while(*cp1 = *cp2++)
            cp1++;
        cp2 = t[dcom];
        while(*cp1++ = *cp2++);
        execv(linep+4, t+dcom);  /* /bin/cmd */
        execv(linep, t+dcom);    /* /usr/bin/cmd */
```

Try to execute the command. If not found, try `/bin/` and `/usr/bin/` prefixes.

### Pipelines

```c
    case tfil:
        f = t[dflg];
        pipe(pv);
        t1 = t[dlef];
        t1[dflg] =| fpou | (f&(fpin|fint));
        execute(t1, pf1, pv);
        t1 = t[drit];
        t1[dflg] =| fpin | (f&(fpou|fint|fand));
        execute(t1, pv, pf2);
        return;
```

Create a pipe, execute left side with output to pipe, right side with input from pipe.

### Command Lists

```c
    case tlst:
        f = t[dflg]&fint;
        if(t1 = t[dlef])
            t1[dflg] =| f;
        execute(t1);
        if(t1 = t[drit])
            t1[dflg] =| f;
        execute(t1);
        return;
```

Execute left side, then right side.

## I/O Redirection

The shell implements redirection by manipulating file descriptors:

```c
/* Input: cmd < file */
close(0);
open(t[dlef], 0);     /* Opens as fd 0 */

/* Output: cmd > file */
i = creat(t[drit], 0666);
close(1);
dup(i);               /* Duplicates to fd 1 */
close(i);

/* Append: cmd >> file */
i = open(t[drit], 1);
seek(i, 0, 2);        /* Seek to end */
close(1);
dup(i);
```

## Pipes

```c
/* cmd1 | cmd2 */
pipe(pv);             /* Create pipe: pv[0]=read, pv[1]=write */

/* Execute cmd1 with stdout → pipe */
t1[dflg] =| fpou;
execute(t1, pf1, pv);

/* Execute cmd2 with stdin ← pipe */
t1[dflg] =| fpin;
execute(t1, pv, pf2);
```

In the child processes:
```c
/* Writer (cmd1) */
close(1);
dup(pv[1]);           /* stdout → pipe write end */
close(pv[0]);
close(pv[1]);

/* Reader (cmd2) */
close(0);
dup(pv[0]);           /* stdin ← pipe read end */
close(pv[0]);
close(pv[1]);
```

## Background Processes

```c
if(**p == '&') {
    t1[dflg] =| fand|fint;
}

/* In execute(): */
if((f&fand) != 0) {
    prn(i);
    prs("\n");        /* Print PID */
    return;           /* Don't wait */
}
```

Background processes:
- Print PID and return immediately
- Have stdin redirected from `/dev/null`
- Ignore interrupt signals (`fint` flag)

## Glob (Wildcard Expansion)

```c
scan(t, &tglob);
if(gflg) {
    t[dspr] = "/etc/glob";
    execv(t[dspr], t+dspr);
}
```

If wildcards (`*`, `?`, `[`) are found, the shell execs `/etc/glob` to expand them. Glob is a separate program that does pattern matching.

## Signal Handling

```c
/* In main(): Login shells ignore signals */
if(**v == '-') {
    signal(quit, 1);
    signal(intr, 1);
}

/* In execute(): Restore signals for children */
if((f&fint) == 0 && setintr) {
    signal(intr, 0);
    signal(quit, 0);
}
```

Interactive shells ignore interrupt/quit so they survive Ctrl-C. Child processes have signals restored unless running in background.

## Summary

The shell in ~800 lines:

- **Lexer** (`word`): Tokenizes input, handles quotes and escapes
- **Parser** (`syntax`, `syn1`, `syn2`, `syn3`): Builds syntax tree
- **Executor** (`execute`): Runs commands via fork/exec
- **Built-ins**: `chdir`, `shift`, `wait`, `login`, `:`
- **Redirection**: Via file descriptor manipulation
- **Pipes**: Via `pipe()` system call
- **Background**: Fork without wait, print PID
- **Glob**: Delegated to `/etc/glob`

## Key Design Points

1. **Simplicity**: No complex features—just the essentials.

2. **Fork/exec model**: Every external command is a new process.

3. **File descriptors**: Redirection works because children inherit fds.

4. **Recursive descent**: Clean, readable parser structure.

5. **External glob**: Pattern matching is a separate program.

## Experiments

1. **Add a built-in**: Implement `pwd` as a built-in command.

2. **Trace execution**: Add printf to see the syntax tree structure.

3. **Pipeline depth**: Create long pipelines and observe process creation.

4. **Signal behavior**: Compare Ctrl-C handling in foreground vs background.

## Further Reading

- Chapter 5: Process Management — `fork`, `exec`, `wait` internals
- Chapter 7: Traps and System Calls — Signal mechanism
- Chapter 10: File I/O — File descriptor operations

---

**Next: Chapter 17 — Core Utilities**
