.PHONY: pdf print print_nocov clean

pdf:
	@./scripts/build-pdf.sh

print:
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

print_nocov:
	@echo "Creating print PDF without covers..."
	@TOTAL=$$(pdfinfo unix_v4_commentary_print.pdf | grep Pages | awk '{print $$2}') && \
	LAST=$$((TOTAL - 1)) && \
	DISPLAY= gs -dBATCH -dNOPAUSE -dSAFER -q \
		-sDEVICE=pdfwrite \
		-dCompatibilityLevel=1.4 \
		-dPDFSETTINGS=/prepress \
		-dEmbedAllFonts=true \
		-dCompressFonts=true \
		-dSubsetFonts=true \
		-dFirstPage=2 \
		-dLastPage=$$LAST \
		-sOutputFile=unix_v4_commentary_print_nocov.pdf \
		unix_v4_commentary_print.pdf && \
	echo "Print PDF without covers: unix_v4_commentary_print_nocov.pdf (pages 2-$$LAST)"

clean:
	rm -rf build/ unix_v4_commentary_print.pdf unix_v4_commentary_print_nocov.pdf
