#!/bin/bash
set -e

cd "$(dirname "$0")/.."

mkdir -p build

# Auto-increment version
VERSION=$(cat VERSION)
NEW_VERSION=$((VERSION + 1))
echo $NEW_VERSION > VERSION

# Generate version string: YYYYMMDD.NNN Edition
DATE=$(date +%Y%m%d)
VERSION_STRING=$(printf "%s.%03d Edition" "$DATE" "$NEW_VERSION")

echo "Building version: $VERSION_STRING"

# Update metadata.yaml with new version
sed -i '' "s/^date: .*/date: \"$VERSION_STRING\"/" metadata.yaml

echo "Combining markdown files..."

# Function to add file with pagebreak before it
add_chapter() {
    echo ""
    echo "\\newpage"
    echo ""
    cat "$1"
}

# Start with front matter (no pagebreak before first file)
cat chapters/00_front_matter.md > build/combined.md

# Part I
cat parts/part1.md >> build/combined.md
add_chapter chapters/01_introduction.md >> build/combined.md
add_chapter chapters/02_pdp11_architecture.md >> build/combined.md
add_chapter chapters/03_building_the_system.md >> build/combined.md

# Part II
cat parts/part2.md >> build/combined.md
add_chapter chapters/04_boot_sequence.md >> build/combined.md
add_chapter chapters/05_process_management.md >> build/combined.md
add_chapter chapters/06_memory_management.md >> build/combined.md
add_chapter chapters/07_traps_and_syscalls.md >> build/combined.md
add_chapter chapters/08_scheduling.md >> build/combined.md

# Part III
cat parts/part3.md >> build/combined.md
add_chapter chapters/09_inodes_and_superblock.md >> build/combined.md
add_chapter chapters/10_file_io.md >> build/combined.md
add_chapter chapters/11_path_resolution.md >> build/combined.md
add_chapter chapters/12_buffer_cache.md >> build/combined.md

# Part IV
cat parts/part4.md >> build/combined.md
add_chapter chapters/13_tty_subsystem.md >> build/combined.md
add_chapter chapters/14_block_devices.md >> build/combined.md
add_chapter chapters/15_character_devices.md >> build/combined.md

# Part V
cat parts/part5.md >> build/combined.md
add_chapter chapters/16_the_shell.md >> build/combined.md
add_chapter chapters/17_core_utilities.md >> build/combined.md
add_chapter chapters/18_c_compiler.md >> build/combined.md
add_chapter chapters/19_assembler.md >> build/combined.md

# Part VI - Appendices
cat parts/part6.md >> build/combined.md
add_chapter chapters/appendix_a_syscall_reference.md >> build/combined.md
add_chapter chapters/appendix_b_file_formats.md >> build/combined.md
add_chapter chapters/appendix_c_pdp11_reference.md >> build/combined.md
add_chapter chapters/appendix_d_glossary.md >> build/combined.md

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

echo "PDF generated: build/unix_v4_commentary.pdf (version $VERSION_STRING)"
