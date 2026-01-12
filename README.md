# The UNIX Fourth Edition Source Code Commentary

A comprehensive, line-by-line commentary on the UNIX Fourth Edition (1973) source code.

## About

UNIX v4 represents one of the most elegant and influential pieces of software ever written - an entire operating system in roughly 10,000 lines of code that you can actually understand. This book provides a complete guide to the kernel, device drivers, file system, shell, and user-space utilities.

Unlike modern operating systems with millions of lines of code, UNIX v4 is small enough for one person to comprehend completely. This commentary explains not just *what* the code does, but *why* it was designed that way.

## Contents

- **Part I: Foundation** - Introduction, PDP-11 architecture, building the system
- **Part II: The Kernel** - Boot sequence, processes, memory, traps, scheduling
- **Part III: The File System** - Inodes, file I/O, path resolution, buffer cache
- **Part IV: Device Drivers** - TTY subsystem, block devices, character devices
- **Part V: User Space** - The shell, core utilities, C compiler, assembler
- **Part VI: Appendices** - System call reference, file formats, PDP-11 reference, glossary

## Building the PDF

### Prerequisites

**macOS (MacPorts):**

```bash
sudo port install pandoc texlive-latex-recommended texlive-fonts-recommended \
                  texlive-latex-extra texlive-fonts-extra texlive-xetex
```

**Debian/Ubuntu:**

```bash
sudo apt install pandoc texlive-latex-recommended texlive-fonts-recommended \
                 texlive-latex-extra texlive-fonts-extra texlive-xetex
```

**Eisvogel template:**

```bash
mkdir -p ~/.pandoc/templates
curl -L https://github.com/Wandmalfarbe/pandoc-latex-template/releases/latest/download/Eisvogel.tar.gz \
  | tar xz -C ~/.pandoc/templates
cp ~/.pandoc/templates/Eisvogel-*/eisvogel.latex ~/.pandoc/templates/
```

### Generate PDF

```bash
make pdf
```

The PDF will be generated at `build/unix_v4_commentary.pdf`.

## Project Structure

```
.
├── chapters/           # All 24 chapter markdown files
├── parts/              # Part divider files for PDF
├── meta/               # Project planning documents
├── scripts/            # Build scripts
├── metadata.yaml       # PDF metadata and styling
├── Makefile            # Build commands
└── README.md
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests for:

- Corrections and clarifications
- Additional explanations
- Improved code analysis
- Typo fixes

## License

This work is licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).

You are free to:
- **Share** - copy and redistribute the material in any medium or format
- **Adapt** - remix, transform, and build upon the material

Under the following terms:
- **Attribution** - You must give appropriate credit
- **NonCommercial** - You may not use the material for commercial purposes
- **ShareAlike** - If you remix or transform, you must distribute under the same license

## Acknowledgments

- **Ken Thompson** and **Dennis Ritchie** - For creating UNIX
- **Bell Labs** - For fostering this incredible work
- **The Computer History Museum** - For preserving this history

---

*"UNIX is basically a simple operating system, but you have to be a genius to understand the simplicity."* — Dennis Ritchie
