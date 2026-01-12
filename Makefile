.PHONY: pdf clean

pdf:
	@./scripts/build-pdf.sh

clean:
	rm -rf build/
