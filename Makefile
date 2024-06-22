
.PHONY: all build wheel test repl clean

all: build

build:
	@python3 setup.py build_ext --inplace	
	@rm -rf ./build ./csnd.c

wheel:
	@STATIC=1 python3 setup.py bdist_wheel
	@rm -rf csnd.egg-info

repl:
	@ipython -i scripts/load_csnd.py

clean:
	@rm -rf build __pycache__ dist csnd.egg-info
	@rm -f csnd.c *.so

test:
	@cd tests && pytest