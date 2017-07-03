#!/usr/bin/env bash

set -e -x

if [[ "$(uname -m)" = i686 ]]; then
	TOOLCHAIN_URL='https://github.com/Noctem/pogeo-toolchain/releases/download/v1.2/gcc-7.1-centos5-i686.tar.bz2'
	export LD_LIBRARY_PATH="/toolchain/lib:${LD_LIBRARY_PATH}"
	MFLAG="-m32"
else
	TOOLCHAIN_URL='https://github.com/Noctem/pogeo-toolchain/releases/download/v1.2/gcc-7.1-centos5-x86-64.tar.bz2'
	export LD_LIBRARY_PATH="/toolchain/lib64:/toolchain/lib:${LD_LIBRARY_PATH}"
	MFLAG="-m64"
fi

curl -L "$TOOLCHAIN_URL" -o toolchain.tar.bz2
tar -C / -xf toolchain.tar.bz2

export MANYLINUX=1
export PATH="/toolchain/bin:${PATH}"
export CFLAGS="-I/toolchain/include ${MFLAG}"
export CXXFLAGS="-I/toolchain/include ${MFLAG}"

# Compile wheels
for PIP in /opt/python/cp3[56789]*/bin/pip; do
	"$PIP" install -U https://github.com/cython/cython/archive/0.26b0.tar.gz --install-option="--no-cython-compile"
	"$PIP" install -U cyrandom
	"$PIP" wheel -v /io/ -w wheelhouse/
done

# Repair for manylinux compatibility
for WHL in wheelhouse/*.whl; do
	auditwheel repair "$WHL" -w /io/wheelhouse/ || auditwheel -v show "$WHL"
done

# Install packages and test
for PYBIN in /opt/python/cp3[56789]*/bin; do
	"${PYBIN}/pip" install pogeo --no-index -f /io/wheelhouse
	"${PYBIN}/python" /io/test/test_pogeo.py
done
