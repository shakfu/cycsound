# cycsound

This is an early stage project to develop a cython wrapper of the csound 6.x api -- essentially wrapping the `csound.h` api.

There's a very good and well-maintained ctypes-based wrapper called `ctcsound.py` which is provided by default with csound. Anyone wanting to use python and csound should use that.

Note: There is a new version (7.x) of csound being developed in the [develop branch](https://github.com/csound/csound) of csound, the `dev` branch of this project will track that once it is released and is stable.

## Rationale

To provide an alternative to the default ctypes-based wrapper. [Cython](https://cython.readthedocs.io/en/latest/) has some advantages over ctypes which are elaborated [here](https://stackoverflow.com/questions/1942298/wrapping-a-c-library-in-python-c-cython-or-ctypes) by cython core developer, but really, the main driver from my side was to learn the csound api by wrapping it.

If this project develops further and becomes a bit more mature, it might be a useful alternative for those who are integrating csound with other cython-based code and who want to distributabe a statically linked extension as a self-contained wheel for example.


## Status

- [x] wrap enough to play arbitrary csd files
- [x] build static variant as wheel (macOS only)
- [x] partial wrapping of csound.h
- [ ] complete wrapping of csound.h
- [ ] unittests (partially implemented)
- [ ] include support for plugins in wheel
- [ ] threaded / async / non-blocking performance
- [ ] feature parity with `ctcsound.py`


## Building

Requires python3 and `cython` and `csound` to be installed on your system using the default platform installation.

To build (with the default dynamic linking) on both Linux and macOS:

```sh
make
```

or

```sh
python3 setup.py build
```

To build with static linking on macOS needs [homebrew](https://brew.sh)

```sh
make STATIC=1
```

or

```sh
STATIC=1 python3 setup.py build
```


To build on Windows:

```sh
python setup.py build
```

## Test

Requires `pytest`

just `pytest` or `make test`

