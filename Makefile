
.PHONY: all build csnd test clean

all: csnd

csnd:
	@python3 setup.py build_ext --inplace	
	@rm -rf ./build ./csnd.c

test:
	@python3 tests/test_csnd.py

clean:
	@rm -rf build
	@rm -f *.so
