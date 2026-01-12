#!/bin/bash
set -e

cd "$(dirname "$0")/.."

mkdir -p build

echo "Combining markdown files..."

# Concatenate all chapters in order with Part dividers
cat \
  chapters/00_front_matter.md \
  parts/part1.md \
  chapters/01_introduction.md \
  chapters/02_pdp11_architecture.md \
  chapters/03_building_the_system.md \
  parts/part2.md \
  chapters/04_boot_sequence.md \
  chapters/05_process_management.md \
  chapters/06_memory_management.md \
  chapters/07_traps_and_syscalls.md \
  chapters/08_scheduling.md \
  parts/part3.md \
  chapters/09_inodes_and_superblock.md \
  chapters/10_file_io.md \
  chapters/11_path_resolution.md \
  chapters/12_buffer_cache.md \
  parts/part4.md \
  chapters/13_tty_subsystem.md \
  chapters/14_block_devices.md \
  chapters/15_character_devices.md \
  parts/part5.md \
  chapters/16_the_shell.md \
  chapters/17_core_utilities.md \
  chapters/18_c_compiler.md \
  chapters/19_assembler.md \
  parts/part6.md \
  chapters/appendix_a_syscall_reference.md \
  chapters/appendix_b_file_formats.md \
  chapters/appendix_c_pdp11_reference.md \
  chapters/appendix_d_glossary.md \
  > build/combined.md

echo "Generating PDF with Pandoc..."

pandoc build/combined.md \
  --metadata-file=metadata.yaml \
  --template=eisvogel \
  --pdf-engine=xelatex \
  --toc \
  --toc-depth=2 \
  --number-sections \
  --top-level-division=chapter \
  --syntax-highlighting=tango \
  -V colorlinks=true \
  -V book=true \
  -V classoption=oneside \
  -o build/unix_v4_commentary.pdf

echo "PDF generated: build/unix_v4_commentary.pdf"
