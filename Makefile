
.PHONY: all build wheel test repl clean

all: build

build:
	@python3 setup.py build_ext --inplace	
	@rm -rf ./build ./cycsound.c

wheel:
	@STATIC=1 python3 setup.py bdist_wheel
	@rm -rf cycsound.egg-info

repl:
	@ipython -i scripts/load_cycsound.py

clean:
	@rm -rf build __pycache__ dist cycsound.egg-info .pytest_cache
	@rm -f cycsound.c *.so

test:
	@cd tests && pytest