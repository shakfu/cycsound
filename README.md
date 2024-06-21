# csnd

This is an early stage project to develop a cython wrapper
of the csound api -- essentially wrapping the `csound.h` api.

There's a very good and well-maintained ctypes-based wrapper
called `ctcsound.py` which is provided by default with csound. 
Anyone wanting to use python and csound should that use that.

If this project develops further and becomes mature, it might 
be a useful alternative for those who are integrating csound
with other cython-based code and who want to statically link
the extension.

## Building

Requires `cython` and `csound` to be installed on your system

To build on Linux and MacOS:

```sh
make
```

or

```sh
python3 setup.py build
```

To build on Windows:

```sh
python setup.py build
```
