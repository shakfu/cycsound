# csnd

This is an early stage project to develop a cython wrapper of the csound api -- essentially wrapping the `csound.h` api.

There's a very good and well-maintained ctypes-based wrapper called `ctcsound.py` which is provided by default with csound. Anyone wanting to use python and csound should use that.


## Rationale

To provide an alternative to the default ctypes-based wrapper. [Cython](https://cython.readthedocs.io/en/latest/) has some advantages over ctypes which are elaborated [here](https://stackoverflow.com/questions/1942298/wrapping-a-c-library-in-python-c-cython-or-ctypes) by cython core developer, but really, the main driver from my side was to learn the csound api by wrapping it.

If this project develops further and becomes a bit more mature, it might be a useful alternative for those who are integrating csound with other cython-based code and who want to distributabe a statically linked extension as a self-contained wheel for example.


## Status

- [x] wrap enough to play arbitrary csd files
- [x] build static variant as wheel (macOS only)
- [ ] include support for plugins in wheel
- [ ] unittests (partially implemented)
- [ ] threaded / async / non-blocking performance
- [ ] complete wrapping of csound.h
- [ ] feature parity with `ctcsound.py`

There's also the question of the name... perhaps it better to call the project `cycsound`?

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

