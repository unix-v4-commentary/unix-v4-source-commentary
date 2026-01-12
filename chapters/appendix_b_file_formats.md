# Appendix B: File Formats

This appendix documents the binary file formats used in UNIX Fourth Edition, including the a.out executable format, archive format, and the on-disk filesystem layout.

---

## a.out Executable Format

The `a.out` format is the executable file format used by UNIX v4. The name comes from "assembler output," as it's the default output file produced by the assembler.

### Header Structure

Every a.out file begins with an 8-word (16-byte) header:

```
Offset  Size    Field           Description
------  ----    -----           -----------
0       2       a_magic         Magic number (0407 or 0410)
2       2       a_text          Size of text segment (bytes)
4       2       a_data          Size of initialized data (bytes)
6       2       a_bss           Size of uninitialized data (bytes)
8       2       a_syms          Size of symbol table (bytes)
10      2       a_entry         Entry point (usually 0)
12      2       a_unused        Unused
14      2       a_flag          Relocation flags
```

### Magic Numbers

| Magic | Octal | Description |
|-------|-------|-------------|
| 0407 | 0407 | Normal executable (text not read-only) |
| 0410 | 0410 | Read-only text (shared text segment) |

**0407 Format:**
- Text and data are combined into a single segment
- Cannot share text between processes
- Simpler memory layout

**0410 Format:**
- Separate text and data segments
- Text is read-only and can be shared between processes
- Used for larger programs to save memory

### File Layout

```
+------------------+ Offset 0
|     Header       | 16 bytes
+------------------+ Offset 020 (16)
|                  |
|   Text Segment   | a_text bytes
|                  |
+------------------+ Offset 020 + a_text
|                  |
|   Data Segment   | a_data bytes
|                  |
+------------------+
|                  |
|  Relocation Info | (if present)
|                  |
+------------------+
|                  |
|   Symbol Table   | a_syms bytes
|                  |
+------------------+
|                  |
|  String Table    | (symbol names)
|                  |
+------------------+
```

### Memory Layout at Execution

When `exec()` loads a 0407 file:
```
Address 0
+------------------+
|   Text + Data    | Combined segment
+------------------+
|       BSS        | Zero-initialized
+------------------+
|                  |
|      Stack       | Grows downward
+------------------+ Address 64KB
```

When `exec()` loads a 0410 file:
```
Address 0
+------------------+
|      Text        | Read-only, shared
+------------------+
|      Data        | Per-process
+------------------+
|       BSS        | Zero-initialized
+------------------+
|                  |
|      Stack       | Grows downward
+------------------+ Address 64KB
```

### Relocation

When the file contains relocation information (not stripped), the relocation entries follow the data segment. Each relocation entry is 8 bytes:

```
struct reloc {
    int    r_vaddr;    /* Address to relocate */
    int    r_symndx;   /* Symbol index or segment */
    int    r_type;     /* Relocation type */
};
```

### Symbol Table

Symbol table entries are 12 bytes each:

```
struct sym {
    char   s_name[8];  /* Symbol name (truncated to 8 chars) */
    int    s_type;     /* Type and storage class */
    int    s_value;    /* Value (address) */
};
```

Symbol types:
| Value | Meaning |
|-------|---------|
| 0 | Undefined |
| 1 | Absolute |
| 2 | Text |
| 3 | Data |
| 4 | BSS |
| 037 | File name |

### Example: Examining an a.out File

```
$ od -o a.out | head
0000000 000407 000062 000004 000000
0000020 ...
```

Breaking down the header:
- 000407 = Magic (normal executable)
- 000062 = Text size (50 bytes)
- 000004 = Data size (4 bytes)
- 000000 = BSS size (0 bytes)

---

## Archive Format (.a files)

Archives are used by the linker to package multiple object files into a single library. The `ar` command creates and manipulates archives.

### Archive Structure

```
+------------------+
|  Archive Header  | Magic string
+------------------+
|  Member Header   |
+------------------+
|  Member Content  | (object file)
+------------------+
|  Member Header   |
+------------------+
|  Member Content  |
+------------------+
       ...
```

### Archive Magic

Archives begin with the magic string:
```
!<arch>\n
```
(8 bytes: `!<arch>` followed by newline)

### Member Header

Each archive member is preceded by a 60-byte header:

```
struct ar_hdr {
    char ar_name[16];   /* Member name, blank padded */
    char ar_date[12];   /* Modification time (decimal) */
    char ar_uid[6];     /* User ID (decimal) */
    char ar_gid[6];     /* Group ID (decimal) */
    char ar_mode[8];    /* File mode (octal) */
    char ar_size[10];   /* Size in bytes (decimal) */
    char ar_fmag[2];    /* Magic: "`\n" */
};
```

**Notes:**
- All fields are ASCII, not binary
- Names longer than 16 characters are truncated
- The `ar_fmag` field contains the string `` `\n`` (backquote, newline)
- Member content follows immediately after the header
- If member size is odd, a padding newline is added

### Symbol Table (__.SYMDEF)

If the archive contains a symbol table (created by `ranlib`), it appears as the first member named `__.SYMDEF`:

```
struct ranlib {
    int  ran_off;       /* Offset of symbol name in string table */
    int  ran_foff;      /* File offset of archive member */
};
```

---

## Filesystem Format

The UNIX v4 filesystem uses a simple and elegant on-disk layout. This section describes the physical structure of data on disk.

### Disk Layout

```
Block 0: Boot Block
Block 1: Superblock
Blocks 2-N: Inode List
Blocks N+1-end: Data Blocks
```

### Boot Block (Block 0)

The first 512-byte block is reserved for the boot loader. On a bootable disk, it contains code to load and execute the kernel. On non-bootable filesystems, it may be unused.

### Superblock (Block 1)

The superblock contains filesystem metadata. It is defined in `usr/sys/filsys.h`:

```c
struct filsys {
    int   s_isize;      /* Size of inode list in blocks */
    int   s_fsize;      /* Size of filesystem in blocks */
    int   s_nfree;      /* Number of entries in s_free */
    int   s_free[100];  /* Free block list cache */
    int   s_ninode;     /* Number of entries in s_inode */
    int   s_inode[100]; /* Free inode cache */
    char  s_flock;      /* Lock for free list manipulation */
    char  s_ilock;      /* Lock for inode list manipulation */
    char  s_fmod;       /* Superblock modified flag */
    char  s_ronly;      /* Read-only flag */
    int   s_time[2];    /* Last modification time */
};
```

**Total size:** 412 bytes

**Field descriptions:**

| Field | Description |
|-------|-------------|
| s_isize | Number of blocks in inode list (starting at block 2) |
| s_fsize | Total blocks in filesystem |
| s_nfree | Count of block numbers in s_free[] (0-100) |
| s_free[] | Cache of free block numbers |
| s_ninode | Count of inode numbers in s_inode[] |
| s_inode[] | Cache of free inode numbers |
| s_flock | Prevents concurrent free list modification |
| s_ilock | Prevents concurrent inode list modification |
| s_fmod | Set when superblock needs writing |
| s_ronly | Set for read-only mounted filesystems |
| s_time | Time of last modification |

### Free Block List

Free blocks are managed using a linked list of block groups. The superblock caches up to 100 free block numbers in `s_free[]`. When this cache is exhausted, `s_free[0]` contains a pointer to a block that contains another 100 free block numbers, and so on.

```
Superblock s_free[]:
+----+----+----+----+...+----+
|ptr | b1 | b2 | b3 |...| b99|
+----+----+----+----+...+----+
  |
  v
Block containing more free block numbers:
+----+----+----+----+...+----+
|ptr | b1 | b2 | b3 |...| b99|
+----+----+----+----+...+----+
  |
  v
  ...
```

### Inode List

Inodes are stored sequentially starting at block 2. Each inode is 32 bytes, so 16 inodes fit per 512-byte block.

**Inode number to block calculation:**
```c
block = (inode_number + 31) / 16;
offset = ((inode_number + 31) % 16) * 32;
```

Note: Inode numbers start at 1 (inode 0 is unused). The +31 accounts for this offset.

### On-Disk Inode Structure

Each inode is 32 bytes on disk:

```
Offset  Size    Field       Description
------  ----    -----       -----------
0       2       di_mode     Type, permissions, flags
2       1       di_nlink    Number of hard links
3       1       di_uid      Owner user ID
4       1       di_gid      Owner group ID
5       1       di_size0    File size high byte
6       2       di_size1    File size low word
8       16      di_addr[8]  Block addresses (13-bit each)
24      4       di_atime    Access time
28      4       di_mtime    Modification time
```

**Total: 32 bytes**

### Inode Mode Field

The `di_mode` field encodes file type and permissions:

```
Bit 15    14    13    12   11   10    9    8    7    6    5    4    3    2    1    0
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|alloc|  type  |large|suid|sgid|    owner    |    group    |    other    |
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
```

| Bits | Value | Meaning |
|------|-------|---------|
| 15 | IALLOC (0100000) | Inode is allocated |
| 14-13 | IFMT (060000) | File type |
| | 00 | Regular file |
| | 01 | Character device (020000) |
| | 10 | Directory (040000) |
| | 11 | Block device (060000) |
| 12 | ILARG (010000) | Large file (indirect blocks) |
| 11 | ISUID (04000) | Set user ID on execution |
| 10 | ISGID (02000) | Set group ID on execution |
| 8-6 | | Owner permissions (rwx) |
| 5-3 | | Group permissions (rwx) |
| 2-0 | | Other permissions (rwx) |

### Block Addressing

The `di_addr[]` array holds 8 block addresses, but they are stored in a packed 13-bit format (3 bytes per address pair):

```
di_addr storage (16 bytes for 8 addresses):
+-------+-------+-------+
| addr0 low | a0h|a1l | addr1 high |  ...
+-------+-------+-------+
```

**Small files (ILARG not set):**
- di_addr[0-7] point directly to data blocks
- Maximum file size: 8 * 512 = 4KB

**Large files (ILARG set):**
- di_addr[0-6] point to indirect blocks
- Each indirect block contains 256 block numbers (512 bytes / 2 bytes per number)
- di_addr[7] points to a doubly-indirect block
- Maximum file size: (7 * 256 + 256 * 256) * 512 = approximately 33MB

```
Small file:
di_addr[0] --> data block
di_addr[1] --> data block
...

Large file:
di_addr[0] --> indirect block --> 256 data blocks
di_addr[1] --> indirect block --> 256 data blocks
...
di_addr[7] --> double indirect --> 256 indirect blocks --> 65536 data blocks
```

### Directory Format

Directories are regular files with a specific internal format. Each directory entry is 16 bytes:

```c
struct direct {
    int   d_ino;        /* Inode number (2 bytes) */
    char  d_name[14];   /* Filename (14 bytes, null-padded) */
};
```

**Notes:**
- Filenames are limited to 14 characters
- A `d_ino` of 0 indicates an empty (deleted) directory entry
- The `.` and `..` entries are always present

### Special Inodes

| Inode | Purpose |
|-------|---------|
| 1 | Root directory (/) |
| 2 | Usually /lost+found or reserved |

### Device Files

For device files (character or block special files), the `di_addr[0]` field contains the device number:

```
di_addr[0]:
+--------+--------+
| major  | minor  |
+--------+--------+
  8 bits   8 bits
```

- Major number: Identifies the device driver
- Minor number: Identifies the specific device instance

### Example Filesystem Calculation

For a filesystem on an RK05 disk (4872 blocks):

```
Block 0:      Boot block
Block 1:      Superblock
Blocks 2-41:  Inode list (40 blocks = 640 inodes)
Blocks 42-4871: Data blocks (4830 blocks)
```

Settings in superblock:
```
s_isize = 40      (blocks in inode list)
s_fsize = 4872    (total filesystem blocks)
```

---

## Object File Format

Object files (produced by the assembler before linking) use the same basic structure as executables, with different magic numbers and additional relocation information.

### Object File Header

Same as a.out header, but with different magic values:
- 0407: Relocatable object with relocation info
- 0410: Pure (read-only text) relocatable object

### Relocation Entries

Object files contain relocation entries that tell the linker how to adjust addresses when combining multiple object files:

```
struct reloc {
    int r_address;    /* Address to patch */
    int r_symbolnum;  /* Symbol or segment reference */
    int r_type;       /* Type of relocation */
};
```

---

## Summary

UNIX v4's file formats are characterized by:

1. **Simplicity** - Minimal headers, straightforward layouts
2. **Efficiency** - Packed formats to save space
3. **Fixed limits** - 14-character filenames, 64KB address space

These constraints reflect the limited resources of the PDP-11 era while still providing the foundation for a fully functional operating system.

---

## See Also

- Chapter 9: Inodes and Superblock
- Chapter 11: Path Resolution
- Chapter 18: The C Compiler
- Appendix C: PDP-11 Quick Reference
