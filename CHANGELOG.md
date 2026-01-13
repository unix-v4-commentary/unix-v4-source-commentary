# Changelog

## 2026-01-13

### Added
- `make print` target: creates print-service-compatible PDF (PDF 1.4, cover removed)
- Dedication haiku in front matter with zen image
- Footnote linking to squoze.net for UNIX v4 source code availability
- Missing trap vectors br7+7 through br7+9 (vectors 240, 244, 250) in Chapter 7
- Complete system call reference: added 19 missing syscalls from sysent.c
- Blockquote explaining 512-byte block size rationale (Chapter 9)
- Blockquote explaining inode count formula from mkfs.c (Chapter 9)
- Blockquote explaining small/large file algorithm tradeoff (Chapter 10)
- Blockquote explaining canonicalization and canon() function (Chapter 13)
- Blockquote explaining octal convention on PDP-11 (Chapter 13)
- Blockquote on elevator algorithm history in computer science (Chapter 14)
- Blockquote explaining "switch" in cdevsw/bdevsw (dispatch table) (Chapter 15)
- Blockquote on classic UNIX dup() redirection technique (Chapter 16)
- Recursive descent parser diagrams: call hierarchy and example parse tree (Chapter 16)
- Footnote on PDP-11 local labels (f/b notation for branches) (Chapter 17)

### Fixed
- RK05 disk capacity: 2.4 MB → 2.38 MiB (correct math: 203×2×12×512 bytes)
- Flow control diagram in Chapter 13: converted Unicode to pure ASCII
- Special character rendering: `#`, `@`, `Ctrl-D` now use code formatting
- `Ctrl-\` rendering: wrapped in backticks to prevent backslash escaping
- malloc() free list table: added column headers (Size | Addr) for clarity
- Multiple drives diagram: removed misleading horizontal arrows (Chapter 14)

### Changed
- Added graphicx package for image support
- Page breaks added for improved layout: sections 6.4, 6.7, 7.10, 11.7.2, 12.18, 13.4, 14.8, 14.15.2, 14.17, 15.4, 15.6, 15.12.3, 15.15, 16.6, 16.12, 17.4, 17.7.3, 17.9, 18.5, 18.8

## 2026-01-12

### Added
- **Initial release** of The UNIX Fourth Edition Source Code Commentary
  - 19 chapters covering kernel, file system, device drivers, and user space
  - 4 appendices: system calls, file formats, PDP-11 reference, glossary
  - PDF build system using Pandoc + LaTeX + Eisvogel
  - Licensed under CC BY-NC-SA 4.0
- Pre-built PDF for users without build dependencies
- Auto-versioning build system with date and build number
- **Appendix E: Running UNIX v4** - complete guide to running v4 on OpenSIMH
  - Quick start with turnkey version
  - Full installation from tape instructions
  - Basic usage guide (chdir, ed editor, cc compiler)
  - Shutdown procedure and kernel rebuild instructions
- Traps vs interrupts explanation in PDP-11 chapter — *Warren Toomey*
- Interrupt handling added to prerequisites section
- About the Author section

### Fixed
- Correct tape date to June 1974 (v4 released Nov 1973, tape sent June 1974) — *Thalia Archibald*
- PSW register diagram alignment in PDF output — *Warren Toomey*
- PDR register diagram: corrected bit fields (PLF 14-8, W 7, ED 3, ACF 2-1)
- ASCII diagram alignment using Menlo monospace font with fixed-width columns
- Markdown list formatting: added blank lines before 75 lists following colons
- Changed `cd` to `chdir` in build instructions (v4 uses chdir, not cd)
- Chapter numbering issues
- README formatting
- Eisvogel template installation instructions — *David Barto*
- Free block list diagram: converted to pure ASCII for proper alignment
- Three-level file abstraction diagram: converted to pure ASCII
- TOC section number width: fixed collision with chapter titles
- Verbatim block font size: now matches code block size
- Grammar: "The key fields for UNIX:" → "The key fields for UNIX are the following:"
- Unicode arrows in build diagrams: converted to standard ASCII (`-->`)
- Table split in section 4.5.6: added page break to keep table intact
- Boot timeline: changed `t=?` to sequential `t=N [Phase]` format

### Changed
- Expanded acknowledgements with full University of Utah tape recovery timeline (sourced from Angelo Papenhoff's 39C3 presentation)
  - Credits: Martin Newell, Jay Lepreau, Aleks Maricq, Rob Ricci, Thalia Archibald, Jon Duerig, Al Kossow, Len Shustek, Angelo Papenhoff, Jacob Ritorto, Ashlin Inwood
- Added TL;DR to README pointing directly to pre-built PDF
- Added page breaks before sections 10.4, 10.12, 10.13, 4.9 to improve layout
