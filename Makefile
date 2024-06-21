
.PHONY: all build csnd test repl clean

all: csnd

csnd:
	@python3 setup.py build_ext --inplace	
	@rm -rf ./build ./csnd.c

test:
	@python3 test_csnd.py

repl:
	@ipython -i scripts/load_csnd.py

clean:
	@rm -rf build __pycache__
	@rm -f *.so
