# Chapter 18: The C Compiler

## Overview

The C compiler that compiled UNIX was itself written in C—a bootstrapping achievement that demonstrated the language's power. In roughly 4,000 lines across two passes, it translates C source code into PDP-11 assembly language. This chapter examines the compiler's architecture, showing how a complete language implementation fits in such compact form.

## Source Files

| File | Lines | Purpose |
|------|-------|---------|
| `usr/c/c00.c` | 744 | Lexer, symbol table, expression parser |
| `usr/c/c01.c` | ~600 | Statements, declarations |
| `usr/c/c02.c` | ~400 | Expression building |
| `usr/c/c03.c` | ~300 | Type checking |
| `usr/c/c04.c` | ~200 | Output utilities |
| `usr/c/c10.c` | 942 | Code generator main |
| `usr/c/c11.c` | ~500 | Code generation helpers |
| `usr/c/c12.c` | ~400 | More code generation |

## Prerequisites

- Chapter 2: PDP-11 Architecture (target machine)
- Understanding of basic compiler concepts

## Two-Pass Architecture

```
Source (.c)
    │
    ▼
┌─────────────────────┐
│   Pass 0 (c0)       │
│   - Lexer           │
│   - Parser          │
│   - Symbol table    │
│   - Type checking   │
└─────────────────────┘
    │
    │  Intermediate form
    │  (trees + text)
    ▼
┌─────────────────────┐
│   Pass 1 (c1)       │
│   - Tree optimizer  │
│   - Code generator  │
│   - Peephole opt    │
└─────────────────────┘
    │
    ▼
Assembly (.s)
    │
    ▼
┌─────────────────────┐
│   Assembler (as)    │
└─────────────────────┘
    │
    ▼
Object (.o)
    │
    ▼
┌─────────────────────┐
│   Linker (ld)       │
└─────────────────────┘
    │
    ▼
Executable (a.out)
```

## Pass 0: Lexical Analysis

### Keyword Table

```c
struct kwtab {
    char *kwname;
    int  kwval;
} kwtab[] {
    "int",      INT,
    "char",     CHAR,
    "float",    FLOAT,
    "double",   DOUBLE,
    "struct",   STRUCT,
    "auto",     AUTO,
    "extern",   EXTERN,
    "static",   STATIC,
    "register", REG,
    "goto",     GOTO,
    "return",   RETURN,
    "if",       IF,
    "while",    WHILE,
    "else",     ELSE,
    "switch",   SWITCH,
    "case",     CASE,
    "break",    BREAK,
    "continue", CONTIN,
    "do",       DO,
    "default",  DEFAULT,
    "for",      FOR,
    "sizeof",   SIZEOF,
    0,          0,
};
```

All 22 C keywords in one table. Keywords are installed in the symbol table at startup with class `KEYWC`.

### The Lexer: symbol()

```c
symbol() {
    register c;
    register char *sp;

    if (peeksym>=0) {
        c = peeksym;
        peeksym = -1;
        return(c);
    }
    /* ... get character ... */
loop:
    switch(ctab[c]) {

    case SPACE:
        c = getchar();
        goto loop;

    case NEWLN:
        line++;
        c = getchar();
        goto loop;

    case PLUS:
        return(subseq(c,PLUS,INCBEF));  /* + or ++ */

    case MINUS:
        return(subseq(c,subseq('>',MINUS,ARROW),DECBEF));

    case ASSIGN:
        /* Handle =, ==, +=, etc. */
        ...

    case DIVIDE:
        if (subseq('*',1,0))
            return(DIVIDE);
        /* Skip comment */
        ...

    case LETTER:
        /* Collect identifier */
        while(ctab[c]==LETTER || ctab[c]==DIGIT) {
            if (sp<symbuf+ncps) *sp++ = c;
            c = getchar();
        }
        csym = lookup();
        if (csym->hclass==KEYWC)
            return(KEYW);
        return(NAME);
    }
}
```

The lexer uses a character classification table (`ctab[]`) for fast dispatch. Multi-character tokens like `++`, `->`, and `==` are handled by `subseq()`.

### Symbol Table

```c
struct hshtab {
    char  name[ncps];    /* Symbol name (8 chars) */
    char  hclass;        /* Storage class */
    char  htype;         /* Type encoding */
    int   hoffset;       /* Offset or value */
    int   dimp;          /* Dimension pointer */
};

struct hshtab *lookup()
{
    int ihash;
    register struct hshtab *rp;

    /* Hash the symbol name */
    ihash = 0;
    for (sp=symbuf; sp<symbuf+ncps;)
        ihash =+ *sp++ & 0177;
    rp = &hshtab[ihash%hshsiz];

    /* Linear probe for match or empty slot */
    while (*(np = rp->name)) {
        for (sp=symbuf; sp<symbuf+ncps;)
            if ((*np++&0177) != *sp++)
                goto no;
        return(rp);        /* Found */
    no:
        if (++rp >= &hshtab[hshsiz])
            rp = hshtab;   /* Wrap around */
    }
    /* Install new symbol */
    ...
    return(rp);
}
```

Simple hash table with linear probing. Symbol names limited to 8 characters.

## Pass 0: Parsing

### Expression Parser

The expression parser uses operator precedence parsing:

```c
tree() {
    int *op, opst[SSIZE], *pp, prst[SSIZE];
    register int andflg, o;

    op = opst;
    pp = prst;
    *op = SEOF;
    *pp = 06;        /* Lowest precedence */
    andflg = 0;      /* Expecting operand? */

advanc:
    switch (o=symbol()) {

    case NAME:
        /* Push operand */
        *cp++ = block(2,NAME,cs->htype,...);
        goto tand;

    case CON:
        *cp++ = block(1,CON,INT,0,cval);
        goto tand;

tand:
        if (andflg)
            goto syntax;    /* Two operands in a row */
        andflg = 1;
        goto advanc;

    case PLUS:
    case MINUS:
        if (!andflg) {
            o = NEG;        /* Unary minus */
        }
        andflg = 0;
        goto oponst;
    }

oponst:
    p = (opdope[o]>>9) & 077;    /* Get precedence */
    /* Reduce higher-precedence operators on stack */
    while (p <= *pp) {
        /* Pop and build tree node */
        build(*op--);
        --pp;
    }
    /* Push this operator */
    *++op = o;
    *++pp = p;
    goto advanc;
}
```

The `opdope[]` table encodes operator properties: precedence, associativity, whether binary or unary.

### Tree Building

```c
build(op) {
    register struct tnode *p1, *p2;

    p2 = *--cp;
    if (opdope[op] & BINARY)
        p1 = *--cp;
    /* Type check and convert */
    ...
    /* Build node */
    *cp++ = block(2, op, type, 0, p1, p2);
}
```

## Pass 1: Code Generation

### Main Loop

```c
main(argc, argv)
char *argv[];
{
    while ((c=getc(ascbuf)) > 0) {
        if(c=='#') {
            /* Expression tree follows */
            tree = getw(binbuf);
            table = tabtab[getw(binbuf)];
            tree = optim(tree);     /* Optimize */
            rcexpr(tree, table, 0); /* Generate code */
        } else
            putchar(c);             /* Copy through */
    }
}
```

Pass 1 reads the intermediate file, optimizes expression trees, and generates code.

### Table-Driven Code Generation

```c
char *match(tree, table, nrleft)
struct tnode *tree;
struct table *table;
{
    op = tree->op;
    d1 = dcalc(tree->tr1, nrleft);  /* Difficulty of left */
    d2 = dcalc(tree->tr2, nrleft);  /* Difficulty of right */

    /* Find matching table entry */
    for (; table->op==op; table++)
        for (opt = table->tabp; opt->tabdeg1!=0; opt++) {
            if (d1 > (opt->tabdeg1&077))
                continue;
            if (d2 > (opt->tabdeg2&077))
                continue;
            /* Check type compatibility */
            if (notcompat(tree->tr1, opt->tabtyp1))
                continue;
            return(opt);    /* Match found */
        }
    return(0);
}
```

Code templates are stored in tables. The generator matches tree patterns against templates and emits the corresponding code.

### Code Template Example

A template might specify:
```
ADD instruction:
  Operand 1: register (difficulty ≤ 12)
  Operand 2: any (difficulty ≤ 12)
  Output: "add A2,R\n"
```

The `cexpr()` function interprets template strings:
- `A` — address of operand 1
- `B` — address of operand 2
- `R` — result register
- `M` — instruction mnemonic

### Optimization

```c
optim(tree) {
    if ((dope&COMMUTE)!=0) {
        /* Reorder commutative operations */
        tree = acommute(tree);
    }
    if (tree->tr2->op==CON && op==MINUS) {
        /* Convert x-c to x+(-c) */
        tree->op = PLUS;
        tree->tr2->value = -tree->tr2->value;
    }
    if (tree->tr1->op==CON && tree->tr2->op==CON) {
        /* Fold constants */
        const(op, &tree->tr1->value, tree->tr2->value);
        return(tree->tr1);
    }
    ...
}
```

Optimizations include:
- Constant folding
- Strength reduction (multiply by power of 2 → shift)
- Common subexpression handling
- Register allocation

## Type System

Types are encoded in a small integer:

```c
/* Base types */
#define INT     0
#define CHAR    1
#define FLOAT   2
#define DOUBLE  3
#define STRUCT  4

/* Type modifiers (in higher bits) */
#define PTR     010     /* Pointer to */
#define FUNC    020     /* Function returning */
#define ARRAY   030     /* Array of */
```

So `int *x` has type `PTR|INT`, and `int (*f)()` has type `PTR|FUNC|INT`.

## Generated Code Example

Source:
```c
int x, y;
x = y + 1;
```

Generated assembly:
```assembly
.globl _x
.globl _y
.comm _x,2
.comm _y,2
        mov     _y,r0
        inc     r0
        mov     r0,_x
```

## Compilation Flow

```
$ cc foo.c

1. Preprocessor (cpp)
   foo.c → /tmp/ctm1

2. Pass 0 (c0)
   /tmp/ctm1 → /tmp/ctm2 (text) + /tmp/ctm3 (trees)

3. Pass 1 (c1)
   /tmp/ctm2 + /tmp/ctm3 → /tmp/ctm4.s

4. Assembler (as)
   /tmp/ctm4.s → foo.o

5. Linker (ld)
   foo.o + libc.a → a.out
```

## Summary

The C compiler in ~4,000 lines:

- **Lexer**: Character classification, symbol table with hashing
- **Parser**: Operator precedence for expressions, recursive descent for statements
- **Type system**: Compact encoding of C's type hierarchy
- **Code generator**: Table-driven pattern matching
- **Optimizer**: Constant folding, strength reduction

## Key Design Points

1. **Two passes**: Separates analysis from code generation cleanly.

2. **Table-driven**: Code templates make the generator compact and maintainable.

3. **Bootstrapped**: The compiler compiles itself—proving the language works.

4. **PDP-11 targeted**: Code generation exploits the architecture's features.

5. **No preprocessor**: `#include` handled by a separate `cpp` program.

## Experiments

1. **Trace compilation**: Add printf to see token stream and parse trees.

2. **New operator**: Add a simple operator and trace through both passes.

3. **Optimization effect**: Compare generated code with/without optimization.

4. **Type encoding**: Decode type integers to understand the encoding.

## Further Reading

- Chapter 2: PDP-11 Architecture — Target instruction set
- Chapter 19: The Assembler — Next stage in compilation
- Original C Reference Manual by Dennis Ritchie

---

**Next: Chapter 19 — The Assembler**
