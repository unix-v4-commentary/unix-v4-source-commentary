# Appendix A: System Call Reference

This appendix provides a complete reference for all system calls implemented in UNIX Fourth Edition. Each entry includes the system call number, C library interface, arguments, return value, and a brief description.

---

## Overview

UNIX v4 implements 35 active system calls (out of 64 slots in the system call table). System calls are invoked via the `sys` instruction on the PDP-11, which causes a trap to kernel mode. The kernel looks up the system call number in `sysent[]` (defined in `usr/sys/ken/sysent.c`) and dispatches to the appropriate handler.

### Argument Passing

- Arguments are passed in the `u.u_arg[]` array in the user structure
- Return values are placed in registers r0 (and sometimes r1)
- Errors are indicated by setting `u.u_error` to an error code

### Error Codes

| Code | Name | Meaning |
|------|------|---------|
| 1 | EPERM | Not owner |
| 2 | ENOENT | No such file or directory |
| 3 | ESRCH | No such process |
| 4 | EINTR | Interrupted system call |
| 5 | EIO | I/O error |
| 6 | ENXIO | No such device or address |
| 7 | E2BIG | Argument list too long |
| 8 | ENOEXEC | Exec format error |
| 9 | EBADF | Bad file number |
| 10 | ECHILD | No children |
| 11 | EAGAIN | No more processes |
| 12 | ENOMEM | Not enough memory |
| 13 | EACCES | Permission denied |
| 14 | EFAULT | Bad address |
| 15 | ENOTBLK | Block device required |
| 16 | EBUSY | Mount device busy |
| 17 | EEXIST | File exists |
| 18 | EXDEV | Cross-device link |
| 19 | ENODEV | No such device |
| 20 | ENOTDIR | Not a directory |
| 21 | EISDIR | Is a directory |
| 22 | EINVAL | Invalid argument |
| 23 | ENFILE | File table overflow |
| 24 | EMFILE | Too many open files |
| 25 | ENOTTY | Not a typewriter |
| 26 | ETXTBSY | Text file busy |
| 27 | EFBIG | File too large |
| 28 | ENOSPC | No space left on device |
| 29 | ESPIPE | Illegal seek |

---

## System Call Reference

### 0 - indir (indirect system call)

```c
syscall(number, args...)
```

**Description:** Execute an indirect system call. The first argument is the system call number, followed by that call's arguments. Primarily used for implementing system call stubs.

**Implementation:** `nullsys()` - does nothing in UNIX v4

---

### 1 - exit

```c
exit(status)
int status;
```

**Arguments:**
- `status` - Exit status (passed in r0, shifted left 8 bits)

**Returns:** Does not return

**Description:** Terminate the calling process. All open file descriptors are closed, the current directory inode is released, and the process enters the zombie state until its parent calls `wait()`. The exit status is saved for retrieval by the parent.

**Implementation:** `rexit()` in `usr/sys/ken/sys1.c`

---

### 2 - fork

```c
pid = fork()
int pid;
```

**Arguments:** None

**Returns:**
- In parent: PID of child process
- In child: PID of parent process (note: parent's PID, not 0)
- On error: -1

**Description:** Create a new process. The child is an exact copy of the parent, including all open file descriptors and current file positions. The child inherits the parent's memory image but has a separate copy.

**Notes:**
- Fork returns twice - once in each process
- The parent's PC is advanced by 2 so it skips to the instruction after fork
- Process times (user, system) are reset to 0 in the child

**Implementation:** `fork()` in `usr/sys/ken/sys1.c`

---

### 3 - read

```c
nread = read(fd, buffer, nbytes)
int fd;
char *buffer;
int nbytes;
```

**Arguments:**
- `fd` - File descriptor (in r0)
- `buffer` - Address of buffer to read into
- `nbytes` - Number of bytes to read

**Returns:** Number of bytes actually read, or -1 on error

**Description:** Read data from a file. For regular files, reads from the current file position and advances it. For pipes, blocks if no data available. For device files, behavior depends on the device driver.

**Implementation:** `read()` in `usr/sys/ken/sys2.c`

---

### 4 - write

```c
nwritten = write(fd, buffer, nbytes)
int fd;
char *buffer;
int nbytes;
```

**Arguments:**
- `fd` - File descriptor (in r0)
- `buffer` - Address of buffer to write from
- `nbytes` - Number of bytes to write

**Returns:** Number of bytes actually written, or -1 on error

**Description:** Write data to a file. For regular files, writes at the current position and advances it. For pipes, blocks if the pipe buffer is full.

**Implementation:** `write()` in `usr/sys/ken/sys2.c`

---

### 5 - open

```c
fd = open(name, mode)
char *name;
int mode;
```

**Arguments:**
- `name` - Pathname of file to open
- `mode` - Access mode: 0=read, 1=write, 2=read/write

**Returns:** File descriptor, or -1 on error

**Description:** Open an existing file for reading and/or writing. The file must exist (use `creat()` to create files). Access permissions are checked based on the mode.

**Implementation:** `open()` in `usr/sys/ken/sys2.c`

---

### 6 - close

```c
close(fd)
int fd;
```

**Arguments:**
- `fd` - File descriptor (in r0)

**Returns:** 0 on success, -1 on error

**Description:** Close an open file descriptor. Releases the file table entry and decrements the inode reference count.

**Implementation:** `close()` in `usr/sys/ken/sys2.c`

---

### 7 - wait

```c
pid = wait()
int pid;
/* Status returned in r1 */
```

**Arguments:** None

**Returns:**
- r0: PID of terminated child
- r1: Exit status of child
- -1 if no children exist

**Description:** Wait for a child process to terminate. If a child has already terminated (zombie state), return immediately with its status. Otherwise, block until a child terminates.

**Implementation:** `wait()` in `usr/sys/ken/sys1.c`

---

### 8 - creat

```c
fd = creat(name, mode)
char *name;
int mode;
```

**Arguments:**
- `name` - Pathname of file to create
- `mode` - Permission bits (masked with 07777)

**Returns:** File descriptor opened for writing, or -1 on error

**Description:** Create a new file or truncate an existing file. If the file exists, it is truncated to zero length and opened for writing. If it doesn't exist, a new file is created with the specified permissions (modified by umask).

**Implementation:** `creat()` in `usr/sys/ken/sys2.c`

---

### 9 - link

```c
link(name1, name2)
char *name1, *name2;
```

**Arguments:**
- `name1` - Pathname of existing file
- `name2` - New pathname (link) to create

**Returns:** 0 on success, -1 on error

**Description:** Create a hard link. The new pathname refers to the same inode as the existing file. Both pathnames must be on the same filesystem. The link count of the inode is incremented. Only superuser can link directories.

**Errors:**
- EEXIST - name2 already exists
- EXDEV - Cross-device link attempted

**Implementation:** `link()` in `usr/sys/ken/sys2.c`

---

### 10 - unlink

```c
unlink(name)
char *name;
```

**Arguments:**
- `name` - Pathname to remove

**Returns:** 0 on success, -1 on error

**Description:** Remove a directory entry. Decrements the link count of the inode. When the link count reaches zero and no processes have the file open, the file's blocks are freed. Only superuser can unlink directories.

**Implementation:** `unlink()` in `usr/sys/ken/sys3.c`

---

### 11 - exec

```c
exec(name, argv)
char *name;
char *argv[];
```

**Arguments:**
- `name` - Pathname of executable file
- `argv` - Array of argument strings, NULL-terminated

**Returns:** Does not return on success, -1 on error

**Description:** Execute a program. The current process image is replaced with the new program. Open file descriptors remain open (unless close-on-exec is set). Signals are reset to default.

**Executable Format:**
- Word 0: Magic number (0407 or 0410)
- Word 1: Text size
- Word 2: Data size
- Word 3: BSS size

**Implementation:** `exec()` in `usr/sys/ken/sys1.c`

---

### 12 - chdir

```c
chdir(dirname)
char *dirname;
```

**Arguments:**
- `dirname` - Pathname of new current directory

**Returns:** 0 on success, -1 on error

**Description:** Change the current working directory. The specified pathname must be a directory and the process must have execute permission.

**Implementation:** `chdir()` in `usr/sys/ken/sys3.c`

---

### 13 - time

```c
time()
/* Returns time in r0 (high) and r1 (low) */
```

**Arguments:** None

**Returns:** Current time in seconds since epoch (Jan 1, 1970) as a 32-bit value split across r0 (high 16 bits) and r1 (low 16 bits)

**Description:** Get the current system time.

**Implementation:** `gtime()` in `usr/sys/ken/sys3.c`

---

### 14 - mknod

```c
mknod(name, mode, dev)
char *name;
int mode;
int dev;
```

**Arguments:**
- `name` - Pathname for new node
- `mode` - File type and permissions
- `dev` - Device number (major/minor) for device files

**Returns:** 0 on success, -1 on error

**Description:** Create a special file (device node). Only superuser can create device nodes. The mode specifies the file type:
- 040000 (IFDIR) - Directory
- 020000 (IFCHR) - Character device
- 060000 (IFBLK) - Block device

**Implementation:** `mknod()` in `usr/sys/ken/sys2.c`

---

### 15 - chmod

```c
chmod(name, mode)
char *name;
int mode;
```

**Arguments:**
- `name` - Pathname of file
- `mode` - New permission bits

**Returns:** 0 on success, -1 on error

**Description:** Change file permissions. Only the file owner or superuser can change permissions.

**Implementation:** `chmod()` in `usr/sys/ken/sys3.c`

---

### 16 - chown

```c
chown(name, owner)
char *name;
int owner;
```

**Arguments:**
- `name` - Pathname of file
- `owner` - New owner UID

**Returns:** 0 on success, -1 on error

**Description:** Change file owner. Only superuser can change file ownership. When a non-superuser changes ownership, the setuid bit is cleared.

**Implementation:** `chown()` in `usr/sys/ken/sys3.c`

---

### 17 - break (sbrk)

```c
brk(addr)
char *addr;
```

**Arguments:**
- `addr` - New end of data segment

**Returns:** 0 on success, -1 on error

**Description:** Change the program break (end of data segment). Used to allocate or deallocate memory for the heap. The break address is rounded up to a 64-byte boundary.

**Implementation:** `sbreak()` in `usr/sys/ken/sys1.c`

---

### 18 - stat

```c
stat(name, buf)
char *name;
struct stat *buf;
```

**Arguments:**
- `name` - Pathname of file
- `buf` - Buffer for stat structure

**Returns:** 0 on success, -1 on error

**Description:** Get file status. Fills in a stat structure with information about the file.

**Stat Structure (36 bytes):**
```c
struct stat {
    int  st_dev;    /* Device */
    int  st_ino;    /* Inode number */
    int  st_mode;   /* Mode and permissions */
    char st_nlink;  /* Link count */
    char st_uid;    /* Owner UID */
    char st_gid;    /* Group GID */
    char st_size0;  /* Size high byte */
    int  st_size1;  /* Size low word */
    int  st_addr[8];/* Block addresses */
    int  st_atime[2]; /* Access time */
    int  st_mtime[2]; /* Modification time */
};
```

**Implementation:** `stat()` in `usr/sys/ken/sys3.c`

---

### 19 - seek (lseek)

```c
seek(fd, offset, whence)
int fd;
int offset;
int whence;
```

**Arguments:**
- `fd` - File descriptor (in r0)
- `offset` - Position offset
- `whence` - Base for offset:
  - 0: From beginning
  - 1: From current position
  - 2: From end
  - 3: Like 0, but offset is in 512-byte blocks
  - 4: Like 1, but offset is in 512-byte blocks
  - 5: Like 2, but offset is in 512-byte blocks

**Returns:** 0 on success, -1 on error

**Description:** Reposition file offset. Cannot seek on pipes.

**Implementation:** `seek()` in `usr/sys/ken/sys2.c`

---

### 20 - (unimplemented)

Reserved for getpid (not implemented in v4)

---

### 21 - mount

```c
mount(special, dir, rwflag)
char *special;
char *dir;
int rwflag;
```

**Arguments:**
- `special` - Pathname of block device
- `dir` - Pathname of mount point
- `rwflag` - 0=read/write, 1=read-only

**Returns:** 0 on success, -1 on error

**Description:** Mount a filesystem. The block device is mounted on the specified directory. Only superuser can mount filesystems.

**Implementation:** `smount()` in `usr/sys/ken/sys3.c`

---

### 22 - umount

```c
umount(special)
char *special;
```

**Arguments:**
- `special` - Pathname of block device to unmount

**Returns:** 0 on success, -1 on error

**Description:** Unmount a filesystem. Fails if any files on the filesystem are open.

**Implementation:** `sumount()` in `usr/sys/ken/sys3.c`

---

### 23 - setuid

```c
setuid(uid)
int uid;
```

**Arguments:**
- `uid` - New user ID (in r0, low byte only)

**Returns:** 0 on success, -1 on error

**Description:** Set user ID. If the caller is superuser or the new UID matches the real UID, both effective and real UID are changed.

**Implementation:** `setuid()` in `usr/sys/ken/sys3.c`

---

### 24 - getuid

```c
uid = getuid()
/* Returns real UID in low byte of r0, effective UID in high byte */
```

**Arguments:** None

**Returns:** Real UID in r0 low byte, effective UID in r0 high byte

**Description:** Get user ID. Returns both the real and effective user IDs.

**Implementation:** `getuid()` in `usr/sys/ken/sys3.c`

---

### 25 - stime

```c
stime()
/* Time passed in r0 (high) and r1 (low) */
```

**Arguments:** Time value in r0/r1

**Returns:** 0 on success, -1 on error

**Description:** Set system time. Only superuser can set the time.

**Implementation:** `stime()` in `usr/sys/ken/sys3.c`

---

### 26-27 - (unimplemented)

Reserved

---

### 28 - fstat

```c
fstat(fd, buf)
int fd;
struct stat *buf;
```

**Arguments:**
- `fd` - File descriptor (in r0)
- `buf` - Buffer for stat structure

**Returns:** 0 on success, -1 on error

**Description:** Get status of an open file. Like stat(), but operates on a file descriptor instead of a pathname.

**Implementation:** `fstat()` in `usr/sys/ken/sys3.c`

---

### 29 - (unimplemented)

Reserved

---

### 30 - smdate

```c
smdate(name, timep)
char *name;
int *timep;
```

**Description:** Set modification date (stub implementation in v4)

**Implementation:** `nullsys()`

---

### 31 - stty

```c
stty(fd, argp)
int fd;
int *argp;
```

**Arguments:**
- `fd` - File descriptor of terminal (in r0)
- `argp` - Pointer to 3-word structure

**Returns:** 0 on success, -1 on error

**Description:** Set terminal parameters. The structure contains:
- Word 0: Input modes
- Word 1: Output modes
- Word 2: Erase and kill characters

**Implementation:** `stty()` in `usr/sys/dmr/tty.c`

---

### 32 - gtty

```c
gtty(fd, argp)
int fd;
int *argp;
```

**Arguments:**
- `fd` - File descriptor of terminal (in r0)
- `argp` - Pointer to 3-word buffer

**Returns:** 0 on success, -1 on error

**Description:** Get terminal parameters.

**Implementation:** `gtty()` in `usr/sys/dmr/tty.c`

---

### 33 - (unimplemented)

Reserved

---

### 34 - nice

```c
nice(incr)
int incr;
```

**Arguments:**
- `incr` - Priority adjustment (in r0)

**Returns:** Previous nice value

**Description:** Change process priority. Positive values decrease priority (make process nicer). Values are clamped to 0-20. Only superuser can decrease the nice value (increase priority).

**Implementation:** `nice()` in `usr/sys/ken/sys3.c`

---

### 35 - sleep

```c
sleep(seconds)
int seconds;
```

**Arguments:**
- `seconds` - Number of seconds to sleep (in r0)

**Returns:** 0

**Description:** Suspend execution for the specified number of seconds.

**Implementation:** `sslep()` in `usr/sys/ken/sys2.c`

---

### 36 - sync

```c
sync()
```

**Arguments:** None

**Returns:** 0

**Description:** Flush all filesystem buffers to disk. Writes all modified buffer cache blocks and superblocks.

**Implementation:** `sync()` in `usr/sys/ken/sys3.c`

---

### 37 - kill

```c
kill(pid, sig)
int pid;
int sig;
```

**Arguments:**
- `pid` - Process ID to signal (in r0)
- `sig` - Signal number

**Returns:** 0 on success, -1 on error

**Description:** Send a signal to a process. The sender must have the same controlling terminal as the target, or be superuser.

**Implementation:** `kill()` in `usr/sys/ken/sys4.c`

---

### 38 - switch (getcsw)

```c
csw = getcsw()
```

**Arguments:** None

**Returns:** Console switch register value

**Description:** Read the console switch register. Used for debugging and system configuration on the PDP-11.

**Implementation:** `getswit()` in `usr/sys/ken/sys3.c`

---

### 39-40 - (unimplemented)

Reserved

---

### 41 - dup

```c
newfd = dup(fd)
int fd;
```

**Arguments:**
- `fd` - File descriptor to duplicate (in r0)

**Returns:** New file descriptor, or -1 on error

**Description:** Duplicate a file descriptor. Returns the lowest available file descriptor number that refers to the same open file.

**Implementation:** `dup()` in `usr/sys/ken/sys3.c`

---

### 42 - pipe

```c
pipe()
/* Returns read fd in r0, write fd in r1 */
```

**Arguments:** None

**Returns:**
- r0: Read end file descriptor
- r1: Write end file descriptor
- -1 on error

**Description:** Create a pipe. Data written to the write end can be read from the read end. Used for inter-process communication.

**Implementation:** `pipe()` in `usr/sys/dmr/pipe.c`

---

### 43 - times

```c
times(buffer)
int *buffer;
```

**Arguments:**
- `buffer` - Pointer to 6-word buffer

**Returns:** 0

**Description:** Get process times. Fills buffer with:
- Word 0-1: User time of current process
- Word 2-3: System time of current process
- Word 4-5: Sum of children's user and system times

**Implementation:** `times()` in `usr/sys/ken/sys4.c`

---

### 44 - profil

```c
profil(buff, bufsiz, offset, scale)
int *buff;
int bufsiz;
int offset;
int scale;
```

**Arguments:**
- `buff` - Buffer for profile counters
- `bufsiz` - Size of buffer
- `offset` - PC offset for profiling
- `scale` - Scaling factor for PC

**Returns:** 0

**Description:** Enable execution profiling. The kernel periodically samples the PC and increments a counter in the buffer based on where the process was executing.

**Implementation:** `profil()` in `usr/sys/ken/sys4.c`

---

### 45 - (unimplemented)

Reserved (tiu - was used for TIU hardware)

---

### 46 - setgid

```c
setgid(gid)
int gid;
```

**Arguments:**
- `gid` - New group ID (in r0, low byte only)

**Returns:** 0 on success, -1 on error

**Description:** Set group ID. Like setuid, but for group ID.

**Implementation:** `setgid()` in `usr/sys/ken/sys3.c`

---

### 47 - getgid

```c
gid = getgid()
/* Returns real GID in low byte of r0, effective GID in high byte */
```

**Arguments:** None

**Returns:** Real GID in r0 low byte, effective GID in r0 high byte

**Description:** Get group ID.

**Implementation:** `getgid()` in `usr/sys/ken/sys3.c`

---

### 48 - signal

```c
old = signal(sig, func)
int sig;
int (*func)();
```

**Arguments:**
- `sig` - Signal number
- `func` - Handler: 0=default, 1=ignore, or address of handler function

**Returns:** Previous handler value

**Description:** Set signal handler. Cannot change handler for signal 9 (KILL).

**Signals in UNIX v4:**
| Number | Name | Default Action |
|--------|------|----------------|
| 1 | SIGHUP | Terminate |
| 2 | SIGINT | Terminate |
| 3 | SIGQIT | Core dump |
| 4 | SIGINS | Core dump |
| 5 | SIGTRC | Core dump |
| 6 | SIGIOT | Core dump |
| 7 | SIGEMT | Core dump |
| 8 | SIGFPT | Core dump |
| 9 | SIGKIL | Terminate (cannot catch) |
| 10 | SIGBUS | Core dump |
| 11 | SIGSEG | Core dump |
| 12 | SIGSYS | Core dump |
| 13 | SIGPIP | Terminate |

**Implementation:** `ssig()` in `usr/sys/ken/sys4.c`

---

### 49-63 - (unimplemented)

Reserved for future use

---

## System Call Summary Table

| # | Name | Args | Description |
|---|------|------|-------------|
| 0 | indir | 0 | Indirect system call |
| 1 | exit | 0 | Terminate process |
| 2 | fork | 0 | Create child process |
| 3 | read | 2 | Read from file |
| 4 | write | 2 | Write to file |
| 5 | open | 2 | Open file |
| 6 | close | 0 | Close file |
| 7 | wait | 0 | Wait for child |
| 8 | creat | 2 | Create file |
| 9 | link | 2 | Create hard link |
| 10 | unlink | 1 | Remove directory entry |
| 11 | exec | 2 | Execute program |
| 12 | chdir | 1 | Change directory |
| 13 | time | 0 | Get system time |
| 14 | mknod | 3 | Create device node |
| 15 | chmod | 2 | Change permissions |
| 16 | chown | 2 | Change owner |
| 17 | break | 1 | Change data segment size |
| 18 | stat | 2 | Get file status |
| 19 | seek | 2 | Seek in file |
| 21 | mount | 3 | Mount filesystem |
| 22 | umount | 1 | Unmount filesystem |
| 23 | setuid | 0 | Set user ID |
| 24 | getuid | 0 | Get user ID |
| 25 | stime | 0 | Set system time |
| 28 | fstat | 1 | Get open file status |
| 31 | stty | 1 | Set terminal params |
| 32 | gtty | 1 | Get terminal params |
| 34 | nice | 0 | Set priority |
| 35 | sleep | 0 | Sleep |
| 36 | sync | 0 | Flush buffers |
| 37 | kill | 1 | Send signal |
| 38 | switch | 0 | Read console switches |
| 41 | dup | 0 | Duplicate fd |
| 42 | pipe | 0 | Create pipe |
| 43 | times | 1 | Get process times |
| 44 | profil | 4 | Execution profiling |
| 46 | setgid | 0 | Set group ID |
| 47 | getgid | 0 | Get group ID |
| 48 | signal | 2 | Set signal handler |

---

## See Also

- Chapter 7: Traps and System Calls
- `usr/sys/ken/sysent.c` - System call table
- `usr/sys/ken/sys1.c` - Process system calls
- `usr/sys/ken/sys2.c` - File I/O system calls
- `usr/sys/ken/sys3.c` - File system calls
- `usr/sys/ken/sys4.c` - Miscellaneous system calls
