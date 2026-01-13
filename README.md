# The UNIX Fourth Edition Source Code Commentary

A comprehensive, line-by-line commentary on the UNIX Fourth Edition source code (released November 1973; tape recovered from June 1974 distribution).

**TL;DR:** Just want to read? Download [`unix_v4_commentary.pdf`](unix_v4_commentary.pdf) directly. The rest of this README is for building from source.

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

**Eisvogel template (required):**

```bash
mkdir -p ~/.pandoc/templates
cd ~/.pandoc/templates
curl -LO https://github.com/Wandmalfarbe/pandoc-latex-template/releases/latest/download/Eisvogel.tar.gz
tar xzf Eisvogel.tar.gz
cp Eisvogel-*/eisvogel.latex .
rm -rf Eisvogel.tar.gz Eisvogel-*/
```

Verify installation:
```bash
ls ~/.pandoc/templates/eisvogel.latex
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
- **Martin Newell** - Original recipient of the tape (June 1974)
- **Jay Lepreau** - Saved the tape from being discarded
- **University of Utah** - Aleks Maricq (discovery), Rob Ricci, Thalia Archibald (research & upload), Jon Duerig (transport to CHM)
- **Computer History Museum** - Al Kossow, Len Shustek (tape recovery)
- **Angelo Papenhoff** (squoze.net) - Emulation, restoration, 39C3 presentation
- **Jacob Ritorto** - First boot on real PDP-11/45
- **Ashlin Inwood** - Boot on real PDP-11/40
- **The Internet Archive** - Hosting the tape image
- **Thalia Archibald**, **Warren Toomey** - Corrections and feedback on this book

---

*"UNIX is basically a simple operating system, but you have to be a genius to understand the simplicity."* — Dennis Ritchie
