.PHONY: pdf print clean

pdf:
	@./scripts/build-pdf.sh

print: pdf
	@echo "Creating print-ready PDF..."
	@DISPLAY= gs -dBATCH -dNOPAUSE -dSAFER \
		-sDEVICE=pdfwrite \
		-dCompatibilityLevel=1.4 \
		-dPDFSETTINGS=/prepress \
		-dEmbedAllFonts=true \
		-dCompressFonts=true \
		-dSubsetFonts=true \
		-sOutputFile=unix_v4_commentary_print.pdf \
		build/unix_v4_commentary.pdf
	@echo "Print-ready PDF: unix_v4_commentary_print.pdf"

clean:
	rm -rf build/ unix_v4_commentary_print.pdf
