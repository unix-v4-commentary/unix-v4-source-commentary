# Appendix C: PDP-11 Quick Reference

This appendix provides a concise reference for the PDP-11 architecture as used by UNIX Fourth Edition. It covers registers, addressing modes, instruction set, and other essential details for understanding the source code.

---

## Registers

The PDP-11 has eight 16-bit general-purpose registers:

| Register | Name | UNIX Usage |
|----------|------|------------|
| r0 | General | Return value, temporary |
| r1 | General | Return value (high word), temporary |
| r2 | General | Temporary, preserved across calls |
| r3 | General | Temporary, preserved across calls |
| r4 | General | Temporary, preserved across calls |
| r5 | General | Frame pointer (fp), preserved |
| r6 | sp | Stack pointer |
| r7 | pc | Program counter |

**Calling Convention:**
- r0-r1: Used for return values, caller-saved
- r2-r4: Callee-saved (must be preserved by called function)
- r5: Frame pointer, callee-saved
- r6/sp: Stack pointer
- r7/pc: Program counter

### Processor Status Word (PSW)

Located at address 0177776:

```
Bit  15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |CM|PM|  |RS|  |  |  |  |PR|PR|PR| T| N| Z| V| C|
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

| Bits | Name | Description |
|------|------|-------------|
| 15-14 | CM | Current mode (00=kernel, 11=user) |
| 13-12 | PM | Previous mode |
| 11 | RS | Register set (not used in 11/40) |
| 7-5 | PR | Processor priority (0-7) |
| 4 | T | Trace trap |
| 3 | N | Negative (result < 0) |
| 2 | Z | Zero (result = 0) |
| 1 | V | Overflow |
| 0 | C | Carry |

---

## Addressing Modes

The PDP-11 uses a flexible addressing mode system. Each operand uses 6 bits: 3 for mode and 3 for register.

### Mode Encoding

| Mode | Syntax | Name | Description |
|------|--------|------|-------------|
| 0 | Rn | Register | Operand is in register |
| 1 | (Rn) | Register deferred | Register contains address |
| 2 | (Rn)+ | Autoincrement | Use address, then increment register |
| 3 | @(Rn)+ | Autoincrement deferred | Double indirection with increment |
| 4 | -(Rn) | Autodecrement | Decrement register, then use address |
| 5 | @-(Rn) | Autodecrement deferred | Double indirection with decrement |
| 6 | X(Rn) | Index | Address is register + offset X |
| 7 | @X(Rn) | Index deferred | Double indirection with index |

### PC-Relative Modes (using r7)

| Mode | Syntax | Name | Description |
|------|--------|------|-------------|
| 27 | #n | Immediate | Operand follows instruction |
| 37 | @#n | Absolute | Address follows instruction |
| 67 | n | Relative | PC-relative address |
| 77 | @n | Relative deferred | Indirect through PC-relative address |

### Examples

```assembly
mov  r0,r1        ; Register to register
mov  (r0),r1      ; Memory[r0] to r1
mov  (r0)+,r1     ; Memory[r0] to r1, r0 += 2
mov  -(sp),r1     ; Push: sp -= 2, Memory[sp] to r1
mov  4(r5),r1     ; Memory[r5+4] to r1
mov  $100,r0      ; Immediate: 100 to r0
mov  *$addr,r0    ; Absolute: Memory[addr] to r0
```

---

## Instruction Set

### Data Movement

| Instruction | Operation | Description |
|-------------|-----------|-------------|
| mov src,dst | dst = src | Move word |
| movb src,dst | dst = src | Move byte |
| clr dst | dst = 0 | Clear word |
| clrb dst | dst = 0 | Clear byte |
| com dst | dst = ~dst | Complement (bitwise NOT) |
| comb dst | dst = ~dst | Complement byte |
| neg dst | dst = -dst | Negate (two's complement) |
| negb dst | dst = -dst | Negate byte |
| inc dst | dst++ | Increment |
| incb dst | dst++ | Increment byte |
| dec dst | dst-- | Decrement |
| decb dst | dst-- | Decrement byte |
| swab dst | | Swap bytes in word |

### Arithmetic

| Instruction | Operation | Description |
|-------------|-----------|-------------|
| add src,dst | dst += src | Add |
| sub src,dst | dst -= src | Subtract |
| cmp src,dst | src - dst | Compare (set flags only) |
| cmpb src,dst | src - dst | Compare bytes |
| tst src | src - 0 | Test (set flags only) |
| tstb src | src - 0 | Test byte |
| adc dst | dst += C | Add carry |
| sbc dst | dst -= C | Subtract carry |
| mul src,reg | reg = reg * src | Multiply (result in reg:reg+1) |
| div src,reg | reg = reg:reg+1 / src | Divide |
| ash shift,reg | | Arithmetic shift |
| ashc shift,reg | | Arithmetic shift combined |

### Logical

| Instruction | Operation | Description |
|-------------|-----------|-------------|
| bit src,dst | src & dst | Bit test (set flags only) |
| bitb src,dst | src & dst | Bit test byte |
| bic src,dst | dst &= ~src | Bit clear |
| bicb src,dst | dst &= ~src | Bit clear byte |
| bis src,dst | dst |= src | Bit set (OR) |
| bisb src,dst | dst |= src | Bit set byte |
| xor reg,dst | dst ^= reg | Exclusive OR |

### Rotate/Shift

| Instruction | Operation | Description |
|-------------|-----------|-------------|
| asr dst | dst >>= 1 | Arithmetic shift right |
| asrb dst | dst >>= 1 | Arithmetic shift right byte |
| asl dst | dst <<= 1 | Arithmetic shift left |
| aslb dst | dst <<= 1 | Arithmetic shift left byte |
| ror dst | | Rotate right through carry |
| rorb dst | | Rotate right byte |
| rol dst | | Rotate left through carry |
| rolb dst | | Rotate left byte |

### Branches

All branches are PC-relative with an 8-bit signed offset (range: -128 to +127 words).

| Instruction | Condition | Description |
|-------------|-----------|-------------|
| br addr | Always | Branch always |
| bne addr | Z=0 | Branch if not equal |
| beq addr | Z=1 | Branch if equal |
| bpl addr | N=0 | Branch if plus |
| bmi addr | N=1 | Branch if minus |
| bvc addr | V=0 | Branch if overflow clear |
| bvs addr | V=1 | Branch if overflow set |
| bcc addr | C=0 | Branch if carry clear |
| bcs addr | C=1 | Branch if carry set |
| bge addr | N^V=0 | Branch if greater or equal (signed) |
| blt addr | N^V=1 | Branch if less than (signed) |
| bgt addr | Z|(N^V)=0 | Branch if greater than (signed) |
| ble addr | Z|(N^V)=1 | Branch if less or equal (signed) |
| bhi addr | C|Z=0 | Branch if higher (unsigned) |
| blos addr | C|Z=1 | Branch if lower or same (unsigned) |

### Jumps and Subroutines

| Instruction | Operation | Description |
|-------------|-----------|-------------|
| jmp dst | pc = dst | Jump |
| jsr reg,dst | tmp=dst; -(sp)=reg; reg=pc; pc=tmp | Jump to subroutine |
| rts reg | pc=reg; reg=(sp)+ | Return from subroutine |
| mark n | | Mark stack (for complex returns) |
| sob reg,addr | if (--reg) br addr | Subtract one and branch |

**Common calling patterns:**

```assembly
; Call function
jsr  pc,func      ; Push old PC, jump to func
; ... or ...
jsr  r5,func      ; Push old r5, jump (used with mark)

; Return
rts  pc           ; Pop return address into PC
; ... or ...
rts  r5           ; Restore r5, return
```

### Stack Operations

The stack grows downward (toward lower addresses). SP (r6) always points to the top item.

```assembly
; Push
mov  r0,-(sp)     ; Decrement SP, store r0

; Pop
mov  (sp)+,r0     ; Load r0, increment SP

; Push multiple
mov  r2,-(sp)
mov  r3,-(sp)
mov  r4,-(sp)

; Pop multiple
mov  (sp)+,r4
mov  (sp)+,r3
mov  (sp)+,r2
```

### Traps and Interrupts

| Instruction | Vector | Description |
|-------------|--------|-------------|
| trap n | 034 | Trap (n in low byte of instruction) |
| emt n | 030 | Emulator trap |
| bpt | 014 | Breakpoint trap |
| iot | 020 | I/O trap |
| rti | | Return from interrupt |
| rtt | | Return from trap (trace trap) |
| halt | | Halt processor |
| wait | | Wait for interrupt |
| reset | | Reset UNIBUS |

### System Calls (UNIX-specific)

```assembly
sys  n            ; System call number n
; Arguments in words following sys instruction
; or in registers depending on call
```

Example:
```assembly
sys  write        ; sys 4
fout              ; file descriptor
buf               ; buffer address
count             ; byte count
```

### Condition Code Operations

| Instruction | Description |
|-------------|-------------|
| clc | Clear C |
| clv | Clear V |
| clz | Clear Z |
| cln | Clear N |
| ccc | Clear all flags |
| sec | Set C |
| sev | Set V |
| sez | Set Z |
| sen | Set N |
| scc | Set all flags |
| nop | No operation |

---

## Memory Map

### PDP-11/40 with 28K words (56KB)

```
Address (octal)  Contents
000000-000377    Interrupt vectors
000400-037777    User text/data (when in user mode)
040000-157777    User text/data continued
160000-167777    Kernel/User stack or I/O page
170000-177777    I/O page and device registers
```

### I/O Page (160000-177777)

| Address | Device/Register |
|---------|-----------------|
| 177560 | Console receiver status |
| 177562 | Console receiver data |
| 177564 | Console transmitter status |
| 177566 | Console transmitter data |
| 177570 | Console switch register |
| 177572 | Memory management registers |
| 177776 | Processor status word (PSW) |

---

## Interrupt Vectors

| Vector (octal) | Interrupt Source |
|----------------|------------------|
| 000 | Reserved |
| 004 | Bus timeout, illegal instruction |
| 010 | Illegal instruction |
| 014 | BPT (breakpoint) |
| 020 | IOT |
| 024 | Power fail |
| 030 | EMT |
| 034 | TRAP |
| 060 | Console input |
| 064 | Console output |
| 100 | Line clock |
| 104 | Programmable clock |
| 200 | RK disk |

Each vector location contains two words:
- Vector + 0: New PC
- Vector + 2: New PSW

---

## Assembly Syntax (UNIX as)

### Directives

| Directive | Description |
|-----------|-------------|
| .text | Switch to text segment |
| .data | Switch to data segment |
| .bss | Switch to BSS segment |
| .globl name | Declare global symbol |
| .byte val,... | Emit bytes |
| .even | Align to word boundary |
| .comm name,size | Define common block |

### Expressions

```assembly
label:            ; Define label at current address
.               ; Current location counter
label + 4         ; Arithmetic on labels
<expr            ; Force 8-bit value
>expr            ; Force 16-bit value
```

### Numeric Constants

```assembly
10.               ; Decimal 10
10                ; Octal 10 (= decimal 8)
0x10              ; (not standard, use octal)
'a                ; Character constant (ASCII value)
"str              ; String (each char is a word)
```

### Common Patterns

```assembly
; Function prologue
func:
    mov  r5,-(sp)     ; Save frame pointer
    mov  sp,r5        ; Set new frame pointer
    ; ... function body ...
    mov  (sp)+,r5     ; Restore frame pointer
    rts  pc           ; Return

; Access argument (first arg at 4(r5) after prologue)
    mov  4(r5),r0     ; First argument
    mov  6(r5),r1     ; Second argument

; Local variables
    sub  $4,sp        ; Allocate 4 bytes
    ; -2(r5) is first local, -4(r5) is second
```

---

## PDP-11 Models Used with UNIX v4

| Model | Memory | Notes |
|-------|--------|-------|
| 11/20 | 28KB | Original UNIX development |
| 11/40 | 64KB | Memory management |
| 11/45 | 256KB | Separate I/D space |

UNIX v4 was primarily developed on the PDP-11/40 with memory management enabled.

---

## Quick Reference Card

### Most Common Instructions

```
mov  src,dst      ; Copy word
add  src,dst      ; dst += src
sub  src,dst      ; dst -= src
cmp  src,dst      ; Compare (set flags)
tst  src          ; Test (set flags)
beq  label        ; Branch if equal
bne  label        ; Branch if not equal
jsr  pc,func      ; Call function
rts  pc           ; Return from function
```

### Register Usage Summary

```
r0    Return value, scratch
r1    Return value (pair), scratch
r2-r4 Preserved across calls
r5    Frame pointer (preserved)
sp    Stack pointer
pc    Program counter
```

### Stack Frame Layout

```
        +----------------+
        | Argument n     |
        +----------------+
        | ...            |
        +----------------+
        | Argument 1     | 4(r5)
        +----------------+
        | Return address | 2(r5)
        +----------------+
r5 -->  | Old r5         | 0(r5)
        +----------------+
        | Local 1        | -2(r5)
        +----------------+
        | Local 2        | -4(r5)
        +----------------+
sp -->  | ...            |
        +----------------+
```

---

## See Also

- Chapter 2: PDP-11 Architecture
- Chapter 4: Boot Sequence
- Chapter 7: Traps and System Calls
- Appendix A: System Call Reference
