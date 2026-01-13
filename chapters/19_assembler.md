# Chapter 19: The Assembler

## Overview

The UNIX assembler translates PDP-11 assembly language into executable object code. Written in assembly language itself, it demonstrates a classic two-pass design: pass 1 builds the symbol table, pass 2 generates code. The assembler is the final stage in the compilation pipeline before linking.

## Source Files

| File | Purpose |
|------|---------|
| `usr/source/s1/as11.s` - `as19.s` | Pass 1 (lexer, parser, symbol table) |
| `usr/source/s1/as21.s` - `as29.s` | Pass 2 (code generation) |

## Prerequisites

- Chapter 2: PDP-11 Architecture (instruction set)
- Chapter 18: C Compiler (produces assembly input)

\newpage

## Two-Pass Architecture

```
Source (.s)
    │
    ▼
┌─────────────────────┐
│   Pass 1 (as1)      │
│   - Lexical scan    │
│   - Build symbols   │
│   - Compute sizes   │
└─────────────────────┘
    │
    │  Symbol table
    │  + intermediate
    ▼
┌─────────────────────┐
│   Pass 2 (as2)      │
│   - Generate code   │
│   - Resolve refs    │
│   - Output object   │
└─────────────────────┘
    │
    ▼
Object (.o)
```

### Why Two Passes?

Forward references are the problem:
```assembly
        jmp     later       / Can't know address yet
        ...
later:  mov     r0,r1       / Defined here
```

Pass 1 computes the address of `later`. Pass 2 uses it.

## Pass 1 Structure

```assembly
/ as11.s - Main entry

start:
    jsr     pc,assem        / Main assembly loop
    movb    pof,r0
    sys     write; outbuf; 512.
    ...
    sys     exec; fpass2; ...   / Chain to pass 2
```

Pass 1 processes the source, building the symbol table, then exec's pass 2.

### Assembly Loop

```assembly
assem:
    jsr     pc,readop       / Get next token
    cmp     r4,$5           / End of file?
    beq     1f
    jsr     pc,checkeos     / End of statement?
    br      assem

1:  rts     pc
```

### Symbol Table

Symbols are stored in a simple table:

```
Entry format:
  Bytes 0-7: Symbol name (8 chars, null-padded)
  Byte 8:    Type/flags
  Bytes 9-10: Value (address or constant)
```

Types include:

- Undefined (forward reference)
- Absolute (constant)
- Text segment
- Data segment
- BSS segment
- External

### Location Counter

The assembler tracks the current address with `.` (dot):

```assembly
.text               / Switch to text segment
        mov r0,r1   / . = 0, instruction at 0
        add r2,r3   / . = 2, instruction at 2
.data               / Switch to data segment
foo:    .word 42    / . = 0 in data, foo = 0
```

\newpage

## Instruction Encoding

PDP-11 instructions are encoded in 16-bit words:

**Single Operand** (CLR, INC, TST, etc.):

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|        opcode         |  mode  |     reg     |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

**Double Operand** (MOV, ADD, CMP, etc.):

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|  opcode   | src mode  |src reg| dst mode  |dst|
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

**Branch** (BEQ, BNE, BR, etc.):

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|        opcode         |        offset         |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

**Jump/Subroutine** (JSR, JMP):

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|     opcode      | reg |  mode  |   dst reg   |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

### Addressing Modes

```
Mode  Syntax          Meaning
0     Rn              Register
1     (Rn)            Register indirect
2     (Rn)+           Autoincrement
3     @(Rn)+          Autoincrement indirect
4     -(Rn)           Autodecrement
5     @-(Rn)          Autodecrement indirect
6     X(Rn)           Index
7     @X(Rn)          Index indirect
```

Special cases with PC (R7):
```
Mode 2: #n      Immediate (literal follows)
Mode 3: @#n     Absolute
Mode 6: n       Relative
Mode 7: @n      Relative indirect
```

\newpage

## Pass 2 Structure

Pass 2 reads the intermediate output and symbol table from pass 1:

```assembly
/ as21.s - Pass 2 main

start2:
    / Read symbol table from temp file
    mov     $usymtab,r1
    sys     read; ...

loop2:
    jsr     pc,readop       / Get opcode
    jsr     pc,opline       / Process operands
    jsr     pc,outw         / Output word
    br      loop2
```

### Code Generation

For each instruction:

1. Look up opcode in table
2. Parse operands
3. Encode addressing modes
4. Output instruction word(s)

```assembly
opline:
    mov     optab(r0),r1    / Get opcode template
    jsr     pc,addres       / Parse first operand
    swab    r3              / Shift to source field
    bis     r3,r1
    jsr     pc,addres       / Parse second operand
    bis     r3,r1           / Add to destination field
    mov     r1,outbuf       / Store result
    rts     pc
```

### Relocation

The assembler generates relocation information for the linker:

```
Object file format:
  Header:
    - Magic number
    - Text size
    - Data size
    - BSS size
    - Symbol table size
    - Entry point
    - Relocation size

  Text segment
  Data segment
  Text relocation
  Data relocation
  Symbol table
```

Relocation entries indicate which words need adjustment when the program is loaded at a different address.

## Directives

```assembly
.globl  sym         / Make symbol global
.text               / Switch to text segment
.data               / Switch to data segment
.bss                / Switch to BSS segment
.byte   1,2,3       / Output bytes
.word   1,2,3       / Output words
.even               / Align to word boundary
.=.+n               / Advance location counter
```

## Assembly Language Features

### Labels

```assembly
foo:    mov     r0,r1       / Define label
        jmp     foo         / Reference label
```

### Local Labels

```assembly
1:      mov     r0,r1
        bne     1b          / Back to 1:
        br      1f          / Forward to next 1:
1:      clr     r0
```

`1b` means "label 1, searching backward"; `1f` means forward.

### Expressions

```assembly
        mov     $foo+4,r0
        .word   bar-baz
        .=.+100
```

The assembler evaluates expressions involving `+`, `-`, `*`, `/`, `&`, `|`, symbols, and constants.

## Example Assembly

Source:
```assembly
.globl  _main
.text
_main:
        mov     $1,r0
        sys     write; 1f; 2f-1f
        clr     r0
        sys     exit
.data
1:      <hello\n>
2:
```

Object code (hex):
```
15c0 0001       mov $1,r0
8904 000c 0006  sys write; L1; 6
0a00            clr r0
8901            sys exit
6865 6c6c 6f0a  "hello\n"
```

## Error Handling

```assembly
filerr:
    mov     (r5)+,r4        / Get filename
    mov     $1,r0
    sys     write; ...      / Print filename
    sys     write; "?\n"; 2 / Print "?"
```

Errors are terse: typically just the filename and "?". Debug by examining the source line.

## Summary

The UNIX assembler:

- **Two passes**: Build symbols, then generate code
- **Self-hosting**: Written in the assembly language it processes
- **PDP-11 specific**: Encodes all addressing modes and instructions
- **Relocation**: Generates position-independent code for linker
- **Minimal**: No macros, simple expression evaluation

## Key Design Points

1. **Simplicity**: No macro processor—that's separate (`m4`).

2. **Two passes**: Clean separation of symbol resolution from code generation.

3. **Tables**: Instruction encodings stored in lookup tables.

4. **Temp files**: Pass 1 writes intermediate data for pass 2.

5. **exec chain**: Pass 1 directly exec's pass 2, avoiding shell overhead.

## Experiments

1. **Trace assembly**: Add print statements to see symbol table construction.

2. **New instruction**: Add a pseudo-instruction like `.ascii`.

3. **Object dump**: Write a program to decode a.out format.

4. **Forward reference**: Trace how a forward branch is resolved.

## Further Reading

- Chapter 2: PDP-11 Architecture — Target instruction set
- Chapter 18: C Compiler — Producer of assembly input
- PDP-11 Processor Handbook — Instruction encoding details
