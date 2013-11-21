parser:
	ghc -Wall parser.hs

run: parser fact.ll
#	./parser -l fact.ll
	./parser < test.txt

test.pdf: test.dot
	dot -Tpdf test.dot -o test.pdf

clean:
	find . -name "*.hi" -type f -exec rm {} \;
	find . -name "*.o" -type f -exec rm {} \;

veryclean: clean
	-rm parser

.PHONY: parser clean veryclean
