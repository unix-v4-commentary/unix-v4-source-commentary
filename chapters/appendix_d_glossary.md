# Appendix D: Glossary

This glossary defines key terms, data structures, functions, and concepts used throughout the UNIX Fourth Edition source code and this commentary.

---

## A

**a.out**
: The default output filename produced by the assembler and linker. Also refers to the executable file format used by UNIX v4. See Appendix B.

**address space**
: The range of memory addresses accessible to a process. On the PDP-11, each process has a 64KB (16-bit) address space divided into text, data, and stack segments.

**alloc()**
: Function in `alloc.c` that allocates a free disk block from the filesystem's free list.

**APR (Active Page Register)**
: PDP-11 memory management register that defines the mapping between virtual and physical addresses for each memory segment.

---

## B

**bio.c**
: Buffer I/O source file (`usr/sys/dmr/bio.c`) containing the buffer cache implementation including `bread()`, `bwrite()`, and `brelse()`.

**bmap()**
: Function in `subr.c` that maps a logical file block number to a physical disk block number, handling both direct and indirect block addressing.

**bread()**
: "Block read" - reads a disk block into a buffer, returning a pointer to the buffer. Blocks until I/O completes.

**brelse()**
: "Buffer release" - returns a buffer to the free list after use. The buffer remains in the cache for potential reuse.

**BSS**
: "Block Started by Symbol" - the uninitialized data segment of a program, zero-filled at load time.

**buffer cache**
: A pool of memory buffers used to cache disk blocks, reducing the need for disk I/O. Managed by `bio.c`.

**bwrite()**
: "Block write" - writes a buffer's contents to disk. May be synchronous or asynchronous depending on flags.

---

## C

**callout**
: A deferred function call, typically scheduled by `timeout()` to execute after a specified delay.

**cdevsw[]**
: Character device switch table - an array of function pointers for character device operations (open, close, read, write).

**clist**
: Character list - a linked list of small buffers (c-blocks) used for TTY input and output queuing.

**clock()**
: Clock interrupt handler in `clock.c`, called 60 times per second. Updates time, handles scheduling, and processes callouts.

**context switch**
: The process of saving one process's state and restoring another's, performed by `swtch()` in `slp.c`.

**copyin()/copyout()**
: Functions to safely copy data between user and kernel address spaces.

**core**
: Physical memory. "Core map" refers to the data structure tracking physical memory allocation.

**coremap[]**
: Array tracking allocation of physical memory (core) in 64-byte blocks.

---

## D

**data segment**
: The portion of a process's address space containing initialized global and static variables.

**device driver**
: Kernel code that manages a hardware device, providing a standard interface (open, close, read, write, strategy) to the rest of the kernel.

**device number**
: A number identifying a device, consisting of a major number (device type/driver) and minor number (specific device instance).

**device switch table**
: Arrays (`bdevsw[]`, `cdevsw[]`) mapping device major numbers to driver functions.

**direct block**
: A disk block address stored directly in an inode's `i_addr[]` array, as opposed to an indirect block.

**directory**
: A special file containing a list of (inode number, filename) pairs. See `namei()`.

**dmr**
: Dennis M. Ritchie - author of device driver code in `usr/sys/dmr/`.

---

## E

**effective UID/GID**
: The user/group ID used for permission checking, which may differ from the real UID/GID due to setuid/setgid bits.

**estabur()**
: "Establish user registers" - configures memory management registers for a process's text, data, and stack segments.

**exec()**
: System call that replaces the current process image with a new program from an executable file.

**expand()**
: Function to change a process's memory allocation, either growing or shrinking its address space.

---

## F

**falloc()**
: Allocate a free entry in the system file table.

**file descriptor**
: A small integer (0-14 in UNIX v4) that identifies an open file within a process. Index into `u.u_ofile[]`.

**file structure**
: Kernel structure (`struct file`) representing an open file, containing the file offset and pointer to the inode.

**file table**
: System-wide array of `struct file` entries, shared among all processes.

**filsys structure**
: The superblock structure defined in `filsys.h`, containing filesystem metadata.

**fork()**
: System call that creates a new process as a copy of the calling process.

**free list**
: Linked list of available resources (disk blocks, inodes, buffers, etc.).

**fubyte()/fuword()**
: "Fetch user byte/word" - safely read a byte/word from user space.

---

## G

**getblk()**
: Get a buffer for a specified device and block number. May return a cached buffer or allocate a new one.

**getf()**
: Get file structure pointer from a file descriptor.

**geterror()**
: Extract error status from a buffer after I/O completion.

---

## H

**hash chain**
: Linked list of buffers or inodes with the same hash value, used for quick lookup.

---

## I

**i-list**
: The contiguous area on disk (blocks 2 through N) containing all inodes for a filesystem.

**i-node**
: See inode.

**ialloc()**
: Allocate a free inode from the filesystem.

**ifree()**
: Free an inode, returning it to the filesystem's free inode list.

**iget()**
: Get a locked, in-memory copy of an inode, reading from disk if necessary.

**ILARG**
: Inode flag indicating "large file" - the inode uses indirect block addressing.

**indirect block**
: A disk block containing block numbers rather than file data, used to address large files.

**init**
: Process 1, the ancestor of all user processes. Created by the kernel during boot, it spawns `getty` processes and adopts orphaned processes.

**inode**
: "Index node" - data structure containing all metadata about a file except its name. Stored both on disk and cached in memory.

**interrupt**
: Hardware signal that causes the CPU to suspend current execution and transfer control to an interrupt handler.

**interrupt vector**
: Memory location containing the address of an interrupt handler.

**iomove()**
: Copy data between a buffer and user space during file I/O.

**iput()**
: Release an inode obtained via `iget()`, decrementing its reference count and writing to disk if modified.

**itrunc()**
: Truncate a file to zero length, freeing all its data blocks.

**iupdat()**
: Update an inode on disk if it has been modified.

---

## K

**ken**
: Ken Thompson - author of core kernel code in `usr/sys/ken/`.

**kernel mode**
: Privileged processor mode with full access to hardware and memory. Also called supervisor mode.

**kernel stack**
: Per-process stack used when executing in kernel mode, stored in the user structure.

**KL11**
: The console terminal interface on the PDP-11, driven by `kl.c`.

---

## L

**link count**
: Number of directory entries (hard links) referring to an inode. When it reaches zero and no processes have the file open, the file is deleted.

**lock**
: Mechanism to ensure exclusive access to a resource. In UNIX v4, typically a flag that causes processes to sleep until cleared.

---

## M

**magic number**
: The first word(s) of a file identifying its format. For executables: 0407 (combined text/data) or 0410 (separate text).

**major device number**
: Upper byte of device number, identifying the device driver.

**maknode()**
: Create a new inode in a directory.

**malloc()**
: Allocate contiguous blocks from a resource map (core memory or swap space). Not the C library malloc.

**memory management**
: Hardware and software mechanisms for mapping virtual addresses to physical addresses and protecting memory regions.

**mfree()**
: Return blocks to a resource map.

**minor device number**
: Lower byte of device number, identifying a specific device instance to the driver.

**MMU (Memory Management Unit)**
: Hardware that translates virtual addresses to physical addresses and enforces memory protection.

**mount**
: Attach a filesystem to a directory in the existing file hierarchy.

**mount table**
: Array of `struct mount` entries tracking mounted filesystems.

---

## N

**namei()**
: "Name to inode" - converts a pathname to an inode, following the directory hierarchy. The heart of pathname resolution.

**newproc()**
: Create a new process structure and copy the parent's context. Called by `fork()`.

**nice value**
: Process priority adjustment. Higher nice values mean lower scheduling priority.

---

## O

**open file table**
: Per-process array (`u.u_ofile[]`) of pointers to file structures for open files.

**openi()**
: Perform device-specific open operations when opening a special file.

---

## P

**panic()**
: Kernel function called for unrecoverable errors. Prints a message and halts the system.

**PDP-11**
: Digital Equipment Corporation minicomputer family for which UNIX v4 was written. See Appendix C.

**physio()**
: Perform physical (raw) I/O directly between a device and user memory, bypassing the buffer cache.

**pipe**
: Inter-process communication mechanism allowing one process to write data that another can read. Implemented in `pipe.c`.

**priority**
: Scheduling priority determining which process runs next. Lower values mean higher priority.

**proc structure**
: Per-process data structure (`struct proc`) containing process state, priority, memory allocation info, etc.

**proc[]**
: System-wide array of process structures.

**process**
: An executing program with its own address space, resources, and execution context.

**process ID (PID)**
: Unique identifier assigned to each process.

**prele()**
: Release a locked inode's lock without decrementing its reference count.

**PSW (Processor Status Word)**
: PDP-11 register containing condition codes and processor mode/priority.

---

## R

**raw device**
: Character device interface to a block device, bypassing the buffer cache. Typically named with an 'r' prefix (e.g., `/dev/rrk0`).

**read-ahead**
: Optimization where the system reads additional blocks beyond what was requested, anticipating future reads.

**readi()**
: Read data from an inode into the user area, handling block mapping and buffer cache.

**real UID/GID**
: The actual user/group ID of the process owner, as opposed to the effective UID/GID.

**reference count**
: Count of pointers/handles to a resource (inode, file structure). Resource is freed when count reaches zero.

**register**
: Fast CPU storage location. The PDP-11 has 8 general registers (r0-r7).

**resource map**
: Data structure for managing allocation of contiguous blocks (memory, swap space).

**RK05**
: DEC disk drive with 2.4MB capacity, commonly used with UNIX v4. Driven by `rk.c`.

**root directory**
: The top-level directory of the filesystem, referenced by inode 1 and accessed as `/`.

---

## S

**sched()**
: The scheduler function in `slp.c`, also known as process 0 or the swapper.

**segment**
: A region of the address space (text, data, or stack) with specific permissions and mapping.

**setrun()**
: Mark a process as runnable after it was sleeping.

**signal**
: Software notification sent to a process, causing it to execute a handler or terminate.

**sleep()**
: Put the current process to sleep waiting on a channel (event). Process is awakened by `wakeup()` on that channel.

**slp.c**
: Source file containing process switching, sleep/wakeup, and scheduler code.

**special file**
: A file representing a device rather than data on disk. Block special files use `bdevsw[]`; character special files use `cdevsw[]`.

**stack segment**
: Region of address space for the process stack, growing downward from high addresses.

**strategy()**
: Block device driver function that queues I/O requests. Called by buffer cache code.

**subyte()/suword()**
: "Store user byte/word" - safely write a byte/word to user space.

**superblock**
: Block 1 of a filesystem, containing filesystem metadata (size, free lists, etc.).

**sureg()**
: "Set user registers" - load memory management registers with process-specific values.

**swap device**
: Disk (or partition) used for swapping process images in and out of memory.

**swap()**
: Move a process image between memory and the swap device.

**swapmap**
: Resource map tracking allocation of swap space.

**swapper**
: Process 0, which moves processes between memory and swap space when memory is scarce.

**switch register**
: Console panel switches on the PDP-11, readable via the `switch` system call.

**swtch()**
: Perform a context switch to the highest-priority runnable process.

**sysent[]**
: System call entry table mapping system call numbers to handler functions.

**system call**
: Request from user program to kernel for a service. Invoked via the `sys` (trap) instruction.

---

## T

**text segment**
: Read-only portion of address space containing program instructions. May be shared between processes running the same program.

**text structure**
: Kernel structure tracking shared text segments among processes.

**time**
: System time in seconds since January 1, 1970 (the UNIX epoch). Stored as two 16-bit words.

**timeout()**
: Schedule a function to be called after a specified number of clock ticks.

**trap**
: Exception or interrupt caused by executing a special instruction (like `sys`) or error condition.

**trap()**
: Kernel trap handler in `trap.c`, dispatching system calls and handling faults.

**TTY (teletype)**
: Terminal device. The TTY subsystem handles input/output processing for character-based terminals.

---

## U

**u (user structure)**
: Per-process kernel data structure containing open files, current directory, signal handlers, saved registers, and the kernel stack. Always mapped at a fixed kernel address.

**u.u_ar0**
: Pointer to saved user registers in the user structure.

**u.u_base**
: I/O transfer address for current system call.

**u.u_cdir**
: Pointer to inode of current working directory.

**u.u_count**
: I/O transfer count for current system call.

**u.u_error**
: Error code from most recent system call.

**u.u_offset[]**
: File offset for current I/O operation.

**u.u_ofile[]**
: Array of pointers to open file structures.

**u.u_procp**
: Pointer to the current process's proc structure.

**u.u_signal[]**
: Array of signal handler addresses.

**ufalloc()**
: Allocate a free file descriptor in the current process.

**USIZE**
: Size of user structure in 64-byte blocks (typically 16, or 1KB).

**user mode**
: Unprivileged processor mode for running user programs, with restricted access to hardware and memory.

---

## V

**vector**
: See interrupt vector.

---

## W

**wait channel (wchan)**
: Address used to identify what event a sleeping process is waiting for. Processes are awakened when `wakeup()` is called with their wait channel.

**wait()**
: System call to wait for a child process to terminate and retrieve its exit status.

**wakeup()**
: Wake all processes sleeping on a specified channel (address).

**wdir()**
: Write a directory entry.

**working directory**
: The current directory for pathname resolution. Changed by `chdir()`.

**writei()**
: Write data from the user area to an inode, handling block mapping and buffer cache.

---

## X

**xalloc()**
: Allocate shared text segment for a process.

**xfree()**
: Free a process's reference to its shared text segment.

---

## Z

**zombie**
: A terminated process whose parent has not yet called `wait()`. The process structure remains allocated to hold the exit status.

---

## Numeric/Symbol

**0407**
: Magic number for normal (non-pure) executable files.

**0410**
: Magic number for pure (shared text) executable files.

**/dev**
: Directory containing device special files.

**/etc**
: Directory containing system configuration files.

**/etc/init**
: The init program, first user process executed after boot.

**/etc/passwd**
: User account database.

---

## Source File Quick Reference

| File | Location | Contents |
|------|----------|----------|
| alloc.c | ken/ | Disk block allocation |
| bio.c | dmr/ | Buffer cache |
| clock.c | ken/ | Clock interrupt handler |
| fio.c | ken/ | File descriptor operations |
| iget.c | ken/ | Inode operations |
| kl.c | dmr/ | Console driver |
| main.c | ken/ | Kernel entry point |
| mem.c | dmr/ | Memory device driver |
| nami.c | ken/ | Path resolution (namei) |
| pipe.c | dmr/ | Pipe implementation |
| prf.c | ken/ | printf functions |
| rdwri.c | ken/ | readi/writei |
| rk.c | dmr/ | RK05 disk driver |
| sig.c | ken/ | Signal handling |
| slp.c | ken/ | Sleep/wakeup, scheduler |
| subr.c | ken/ | bmap and utilities |
| sys1.c | ken/ | fork, exec, exit, wait |
| sys2.c | ken/ | open, read, write, close |
| sys3.c | ken/ | unlink, chdir, chmod, etc. |
| sys4.c | ken/ | signal, kill, times, etc. |
| sysent.c | ken/ | System call table |
| text.c | ken/ | Shared text segments |
| trap.c | ken/ | Trap handler |
| tty.c | dmr/ | TTY line discipline |

---

## See Also

- Appendix A: System Call Reference
- Appendix B: File Formats
- Appendix C: PDP-11 Quick Reference
