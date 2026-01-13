.PHONY: pdf print clean

pdf:
	@./scripts/build-pdf.sh

print: pdf
	@echo "Creating print-ready PDF..."
	@gs -q -dNOPAUSE -dBATCH -dSAFER \
		-dPDFSETTINGS=/prepress \
		-dCompatibilityLevel=1.4 \
		-dFirstPage=2 \
		-sDEVICE=pdfwrite \
		-sOutputFile=unix_v4_commentary_print.pdf \
		build/unix_v4_commentary.pdf
	@echo "Print-ready PDF: unix_v4_commentary_print.pdf"

clean:
	rm -rf build/ unix_v4_commentary_print.pdf
