# Chapter 15: Character Devices

## Overview

Character devices transfer data byte-by-byte without buffering through the block cache. They include terminals (Chapter 13), but also pseudo-devices like `/dev/null` and `/dev/mem`. Unlike block devices that hide behind the buffer cache, character devices interact directly with user processes through their read and write routines.

This chapter examines the memory pseudo-devices—elegant examples of the character device model.

## Source Files

| File | Purpose |
|------|---------|
| `usr/sys/conf.h` | Device switch tables |
| `usr/sys/dmr/mem.c` | Memory devices |

## Prerequisites

- Chapter 10: File I/O (`passc`, `cpass`, `u.u_offset`)
- Chapter 13: TTY Subsystem (character device example)

## The Character Device Switch

```c
/* conf.h */
struct cdevsw {
    int (*d_open)();     /* Open device */
    int (*d_close)();    /* Close device */
    int (*d_read)();     /* Read from device */
    int (*d_write)();    /* Write to device */
    int (*d_sgtty)();    /* Get/set TTY parameters */
} cdevsw[];
```

Character devices provide five entry points. The `d_sgtty` routine is optional—only terminals use it.

Example configuration:
```c
/* conf/c.c */
struct cdevsw cdevsw[] {
    &klopen, &klclose, &klread, &klwrite, &klsgtty,  /* 0 = console */
    &nulldev,&nulldev, &mmread, &mmwrite, &nodev,    /* 1 = mem */
    0
};
```

## Block vs Character Devices

| Aspect | Block Device | Character Device |
|--------|--------------|------------------|
| Data unit | 512-byte blocks | Bytes |
| Buffering | Through buffer cache | Direct or driver-managed |
| Access | Random (any block) | Sequential typical |
| Interface | `strategy()` | `read()`, `write()` |
| Examples | Disks, tapes | Terminals, /dev/null |

Many devices have both interfaces:
- `/dev/rk0` — Block device (buffered)
- `/dev/rrk0` — Character device (raw, unbuffered)

## The Memory Devices

```c
/*
 * Memory special file
 * minor device 0 is physical memory
 * minor device 1 is kernel memory
 * minor device 2 is EOF/RATHOLE
 */
```

Three pseudo-devices in one driver:
- `/dev/mem` (minor 0) — Physical memory
- `/dev/kmem` (minor 1) — Kernel virtual memory
- `/dev/null` (minor 2) — Data sink/source

## mmread() — Read Memory

```c
/* mem.c */
mmread(dev)
{
    register c, bn, on;
    int a;

    if(dev.d_minor == 2)
        return;                 /* /dev/null: EOF immediately */
```

Reading from `/dev/null` returns nothing—immediate end-of-file.

```c
    do {
        bn = lshift(u.u_offset, -6);    /* Block number (64-byte pages) */
        on = u.u_offset[1] & 077;       /* Offset within page */
        a = UISA->r[0];                 /* Save segment register */
        spl7();
        UISA->r[0] = bn;                /* Map to requested page */
```

The PDP-11 MMU limits direct access to 64KB. To read arbitrary physical memory, we temporarily remap segment 0 to point to the desired page.

```c
        if(dev.d_minor == 1)
            UISA->r[0] = KISA->r[(bn>>7)&07] + (bn & 0177);
```

For `/dev/kmem`, translate through the kernel's address space. This allows reading kernel data structures.

```c
        c = fubyte(on);                 /* Read the byte */
        UISA->r[0] = a;                 /* Restore segment register */
        spl0();
    } while(u.u_error==0 && passc(c)>=0);
}
```

Read one byte via `fubyte()`, restore the mapping, pass to user via `passc()`. Repeat until done.

## mmwrite() — Write Memory

```c
/* mem.c */
mmwrite(dev)
{
    register c, bn, on;
    int a;

    if(dev.d_minor == 2) {
        c = u.u_count;
        u.u_count = 0;
        u.u_base =+ c;
        dpadd(u.u_offset, c);
        return;
    }
```

Writing to `/dev/null`: Accept all data, advance pointers, discard everything. The "rathole" consumes infinite data.

```c
    for(;;) {
        bn = lshift(u.u_offset, -6);
        on = u.u_offset[1] & 077;
        if ((c=cpass())<0 || u.u_error!=0)
            break;
        a = UISA->r[0];
        spl7();
        UISA->r[0] = bn;
        if(dev.d_minor == 1)
            UISA->r[0] = KISA->r[(bn>>7)&07] + (bn & 0177);
        subyte(on, c);          /* Write the byte */
        UISA->r[0] = a;
        spl0();
    }
}
```

Same mapping trick as read. Get byte from user via `cpass()`, write to memory via `subyte()`.

## Use Cases

### /dev/null — The Bit Bucket

```sh
$ command > /dev/null    # Discard output
$ cat /dev/null          # Empty file (0 bytes)
```

Writing discards data; reading returns EOF immediately.

### /dev/mem — Physical Memory

```sh
$ od /dev/mem            # Dump physical memory
```

Used by debuggers and system utilities to examine raw memory. Dangerous—can crash the system if misused.

### /dev/kmem — Kernel Memory

```sh
$ ps                     # Reads process table from /dev/kmem
```

Programs like `ps` read kernel data structures (proc table, etc.) through this device. The kernel address translation makes kernel variables accessible.

## The MMU Trick

The PDP-11's memory management unit maps virtual addresses to physical:

```
Virtual Address          Physical Address
    │                         │
    ▼                         ▼
┌────────┐              ┌────────────┐
│ 0-8KB  │──UISA[0]────►│ Some page  │
│ 8-16KB │──UISA[1]────►│ Some page  │
│  ...   │              │    ...     │
└────────┘              └────────────┘
```

To access arbitrary physical memory:
1. Save current UISA[0]
2. Set UISA[0] = target page
3. Access address 0-8KB (maps to target)
4. Restore UISA[0]

This must be done at high priority (spl7) to prevent interrupts from using the corrupted mapping.

## Contrast with TTY

Both are character devices, but very different:

| Aspect | TTY | Memory |
|--------|-----|--------|
| Hardware | Real device (terminal) | Pseudo-device |
| Interrupts | Yes (keyboard, transmit) | No |
| Buffering | Three queues | None |
| Processing | Echo, line editing | None |
| Blocking | Waits for input | Never blocks |

## Other Character Devices

### Line Printer (lp.c)

Output-only device:
- `lpwrite()` — Send characters to printer
- `lpstart()` — Start printing from output queue
- `lpintr()` — Handle printer-ready interrupt

### Paper Tape (pc.c)

```c
pcread()   /* Read from paper tape reader */
pcwrite()  /* Write to paper tape punch */
```

### Raw Disk (rk.c)

```c
rkread(dev)
{
    physio(rkstrategy, &rrkbuf, dev, B_READ);
}
```

Character interface to block device. Uses `physio()` to bypass buffer cache—data goes directly between disk and user memory.

## Device Registration

```c
/* conf/c.c */
struct cdevsw cdevsw[] {
    &klopen,  &klclose, &klread,  &klwrite, &klsgtty,  /* 0 = kl */
    &nulldev, &nulldev, &mmread,  &mmwrite, &nodev,    /* 1 = mem */
    &nulldev, &nulldev, &rkread,  &rkwrite, &nodev,    /* 2 = rrk */
    &pcopen,  &pcclose, &pcread,  &pcwrite, &nodev,    /* 3 = pc */
    &lpopen,  &lpclose, &nodev,   &lpwrite, &nodev,    /* 4 = lp */
    0
};
```

`nulldev` — Does nothing (for devices that don't need open/close)
`nodev` — Returns error (for unsupported operations)

## Creating Device Files

```sh
# mknod /dev/null c 1 2
#        │        │ │ │
#        │        │ │ └── minor number (2 = null)
#        │        │ └──── major number (1 = mem driver)
#        │        └─────── character device
#        └───────────────── device file name
```

The `mknod` command creates special files that point to device drivers through major/minor numbers.

## Summary

- **Character devices** transfer bytes, not blocks
- **Direct interface**: `read()`, `write()` instead of `strategy()`
- **Varied purposes**: Terminals, pseudo-devices, raw disk access
- **/dev/null**: Discards writes, returns EOF on read
- **/dev/mem**: Access physical memory via MMU tricks
- **/dev/kmem**: Access kernel address space

## Key Design Points

1. **Simplicity**: Most character devices just move bytes—no complex buffering.

2. **Flexibility**: Same interface for hardware (terminals) and pseudo-devices (null).

3. **Direct access**: User process interacts without buffer cache intermediary.

4. **MMU manipulation**: Clever use of memory mapping for /dev/mem.

5. **Dual interfaces**: Block devices often have character (raw) counterparts.

## Experiments

1. **Read /dev/mem**: Write a program to read the first 1KB of physical memory.

2. **Benchmark /dev/null**: Time writing large amounts to /dev/null vs a real file.

3. **Examine kernel**: Read proc table from /dev/kmem (requires knowing the address).

4. **Create devices**: Use mknod to create new device files.

## Further Reading

- Chapter 13: TTY Subsystem — Complex character device
- Chapter 14: Block Devices — The other device model
- Chapter 10: File I/O — How devices fit in the file abstraction

---

**Part IV Complete! Next: Part V — User Space**
