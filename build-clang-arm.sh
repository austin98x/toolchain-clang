#!/bin/bash

set -e

###############################################################################
#
# common functions
#
function prepare_package()
{
	package=$1
	url=$2
	name=$3

	cd "${_SOURCE_DIR}"

	if [ ! -e $package ] ; then
		wget $url/$package
	fi

	mkdir -p "${_BUILD_DIR}/$name"

	if [ ! -d "$name" ] ; then
		mkdir -p "$name"
		echo "Extracting $package ..."
		tar xf $package -C "$name" --strip-components=1
	fi

	cd -
}

function build_and_install()
{
	extra_opt=$1
	make $extra_opt -j`nproc`
	make $extra_opt install
}

function print_ignore_build_msg()
{
	package=$1
	echo "Ignoring build: $package"
}

function mark_build_succeeded()
{
	touch .succeeded
}

function precheck()
{
	if ! which gcc > /dev/null ; then
		echo "No gcc found"
		exit 1
	fi

	if ! which g++ > /dev/null ; then
		echo "No g++ found"
		exit 1
	fi

	ver=`gcc --version | grep ^gcc | sed 's/^.* //g'`
	major=`echo $ver | cut -d'.' -f1`
	minor=`echo $ver | cut -d'.' -f2`

	can_build=0
	if ([ "$major" -ge "4" ] && [ "$minor" -ge "7" ]) || [ "$major" -ge "5" ] ; then
		can_build=1
	else
		# detect suitable version
		vers=(4.7 4.8 4.9 5.1 5.2)
		for v in ${vers[@]} ; do
			if which gcc-$v > /dev/null ; then
				GCC=gcc-$v
				GXX=g++-$v
				can_build=1
				break
			fi
		done
	fi

	if [ "$can_build" = "1" ] ; then
		echo "Select ${GCC}/${GXX} for building clang"
	else
		echo "Your gcc version ($ver) is too old, please upgrade to 4.7+"
		exit 1
	fi
}
#
###############################################################################
#
# binutils
#
function build_binutils()
{
	_VER=$_BINUTILS_VER
	_PACKAGE=binutils-${_VER}.tar.bz2

	dir="${_BUILD_DIR}/binutils"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg binutils
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/binutils binutils

	cd $dir
	${_SOURCE_DIR}/binutils/configure	\
			--prefix=${_HOST_DIR}/usr	\
			--with-sysroot=${_SYSROOT}	\
			--target=${_TARGET}	\
			--enable-threads	\
			--disable-shared	\
			--enable-static	\
			--disable-multilib	\
			--disable-werror

	build_and_install MAKEINFO=true
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# m4
#
function build_m4()
{
	_VER=$_M4_VER
	_PACKAGE=m4-${_VER}.tar.xz

	dir="${_BUILD_DIR}/m4"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg m4
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/m4 m4

	cd $dir
	${_SOURCE_DIR}/m4/configure --prefix=${_HOST_DIR}/usr

	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# gmp
#
function build_gmp()
{
	_VER=$_GMP_VER
	_PACKAGE=gmp-${_VER}.tar.xz

	dir="${_BUILD_DIR}/gmp"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg gmp
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/gmp gmp

	cd $dir
	${_SOURCE_DIR}/gmp/configure	\
			--prefix=${_HOST_DIR}/usr	\
			--enable-shared

	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# mpfr
#
function build_mpfr()
{
	_VER=$_MPFR_VER
	_PACKAGE=mpfr-${_VER}.tar.xz

	dir="${_BUILD_DIR}/mpfr"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg mpfr
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/mpfr mpfr

	cd $dir
	${_SOURCE_DIR}/mpfr/configure	\
			--prefix=${_HOST_DIR}/usr	\
			--with-gmp=${_HOST_DIR}/usr	\
			--enable-shared

	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# mpc
#
function build_mpc()
{
	_VER=$_MPC_VER
	_PACKAGE=mpc-${_VER}.tar.gz

	dir="${_BUILD_DIR}/mpc"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg mpc
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/mpc mpc

	cd $dir
	${_SOURCE_DIR}/mpc/configure	\
			--prefix=${_HOST_DIR}/usr	\
			--with-gmp=${_HOST_DIR}/usr	\
			--enable-shared

	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# gcc
#
function build_gcc()
{
	# initial, intermediate, final
	step=$1
	_VER=${_GCC_VER}
	_PACKAGE=gcc-${_VER}.tar.bz2

	_COMMON_CFG="--prefix=${_HOST_DIR}/usr	\
			--with-sysroot=${_SYSROOT}	\
			--target=${_TARGET}	\
			--with-gmp=${_HOST_DIR}/usr	\
			--with-mpfr=${_HOST_DIR}/usr	\
			--with-mpc=${_HOST_DIR}/usr	\
			--enable-threads=posix	\
			--disable-libsanitizer	\
			--disable-libquadmath	\
			--enable-gnu-unique-object	\
			--disable-multilib"

	_EXTRA_CFG=""
	_MAKE_ARGS=""
	_MAKE_INSTALL_ARGS=""

	dir="${_BUILD_DIR}/gcc-$step"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg gcc-$step
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/gcc/gcc-${_VER} gcc-$step

	cd $dir

	case $step in
		initial)
			_EXTRA_CFG="\
				--enable-languages=c	\
				--disable-shared	\
				--disable-libgcc	\
				--without-headers	\
				--with-newlib	\
				"
			_MAKE_ARGS="all-gcc"
			_MAKE_INSTALL_ARGS="install-gcc"
			;;
		intermediate)
			_EXTRA_CFG="\
				--enable-languages=c	\
				--enable-shared	\
				"
			_MAKE_ARGS="all-gcc all-target-libgcc"
			_MAKE_INSTALL_ARGS="install-gcc install-target-libgcc"
			;;
		final)
			_EXTRA_CFG="\
				--enable-languages=c,c++	\
				--enable-shared	\
				--with-build-time-tools=${_HOST_DIR}/usr/${_TARGET}/bin	\
				"
			_MAKE_INSTALL_ARGS="install"
			;;
		*)
			echo "Unkown build step: $step"
			exit 1
			;;
	esac

	MAKEINFO=missing ${_SOURCE_DIR}/gcc-$step/configure	\
			${_COMMON_CFG}	\
			${_EXTRA_CFG}

	make -j`nproc` ${_MAKE_ARGS}
	make -j`nproc` ${_MAKE_INSTALL_ARGS}
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# linux headers
#
function build_linux_headers()
{
	_VER=$_HEADER_VER
	_PACKAGE=linux-${_VER}.tar.xz

	dir="${_BUILD_DIR}/linux"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg headers
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} https://www.kernel.org/pub/linux/kernel/v3.x linux

	cp -ar "${_SOURCE_DIR}"/linux/* "${dir}"

	cd $dir
	make -j`nproc` ARCH=arm64 INSTALL_HDR_PATH=${_SYSROOT}/usr headers_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# gawk
#
function build_gawk()
{
	_VER=$_GAWK_VER
	_PACKAGE=gawk-${_VER}.tar.xz

	dir="${_BUILD_DIR}/gawk"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg gawk
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/gawk gawk

	cd $dir
	${_SOURCE_DIR}/gawk/configure --prefix=${_HOST_DIR}/usr

	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# glibc
#
function build_glibc()
{
	# base, full
	step=$1

	_VER=$_GLIBC_VER
	_PACKAGE=glibc-${_VER}.tar.xz

	dir="${_BUILD_DIR}/glibc-$step"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg glibc-$step
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/glibc glibc-$step

	cd $dir

	export CC="${_HOST_DIR}/usr/bin/${_TARGET}-gcc"
	export CXX="${_HOST_DIR}/usr/bin/${_TARGET}-g++"
	export CFLAGS="-O2"
	export CXXFLAGS="-O2"

	# Fixed make version >= 4.0
	sed -ie "/3\.79\*.*/s/)/ \| 4\.\*)/" ${_SOURCE_DIR}/glibc-$step/configure

	${_SOURCE_DIR}/glibc-$step/configure	\
			libc_cv_forced_unwind=yes	\
			libc_cv_ssp=no	\
			--prefix=/usr	\
			--target=${_TARGET}	\
			--host=${_TARGET}	\
			--with-headers=${_SYSROOT}/usr/include	\
			--with-fp	\
			--without-cvs	\
			--without-gd	\
			--enable-obsolete-rpc	\
			--enable-shared	\
			--disable-profile

	case $step in
		base)
			sed -ie "s/\(^headers.*$\)/\1 bits\/stdio_lim.h/" ${_SOURCE_DIR}/glibc-$step/stdio-common/Makefile

			make -j`nproc`	\
				install_root=${_SYSROOT}	\
				install-bootstrap-headers=yes	\
		 		install-headers

				make -j`nproc` csu/subdir_lib

				# Hard code workaround for building gcc intermediate
				mkdir -p ${_SYSROOT}/usr/lib
				cp csu/crt{1,i,n}.o ${_SYSROOT}/usr/lib/

				mkdir -p ${_SYSROOT}/usr/include/gnu
				touch ${_SYSROOT}/usr/include/gnu/stubs.h

				${_HOST_DIR}/usr/bin/${_TARGET}-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o ${_SYSROOT}/usr/lib/libc.so
			;;
		full)
			make -j`nproc`
			make install_root=${_SYSROOT} install
			;;
		*)
			echo "Unkown build step: $step"
			exit 1
			;;
	esac

	unset CC CXX CFLAGS CXXFLAGS
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# gdb
#
function build_gdb()
{
	_VER=$_GDB_VER
	_PACKAGE=gdb-${_VER}.tar.bz2

	dir="${_BUILD_DIR}/gdb"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg gdb
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${_GNU_MIRRORS}/gdb gdb

	cd $dir
	${_SOURCE_DIR}/gdb/configure	\
			--prefix=${_HOST_DIR}/usr	\
			--target=${_TARGET}	\
			--enable-threads	\
			--without-uiout	\
			--without-guile \
			--without-babeltrace \
			--disable-tui	\
			--disable-gdbtk	\
			--disable-werror	\
			--with-python=`which python2`

	build_and_install MAKEINFO=true
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# prepare clang sources
#
function prepare_clang()
{
	_VER=$_CLANG_VER
	_PACKAGE_LLVM=llvm-${_VER}.src.tar.xz
	_PACKAGE_CFE=cfe-${_VER}.src.tar.xz
	_PACKAGE_CRT=compiler-rt-${_VER}.src.tar.xz
	_URL=http://llvm.org/releases/${_VER}

	prepare_package ${_PACKAGE_LLVM} ${_URL} llvm
	prepare_package ${_PACKAGE_CFE} ${_URL} llvm/tools/clang
	prepare_package ${_PACKAGE_CRT} ${_URL} llvm/projects/compiler-rt
}
#
###############################################################################
#
# clang
#
function build_clang()
{
	dir="${_BUILD_DIR}/llvm"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg clang
		return
	fi

	rm -fr "$dir"
	prepare_clang

	cd "$dir"

	# CC=${_HOST_DIR}/usr/bin/clang CXX=${_HOST_DIR}/usr/bin/clang++
	# ENABLE_LIBCPP=--enable-libcpp
	CC=${_GCC} CXX=${_GXX}	\
	"${_SOURCE_DIR}"/llvm/configure	\
			--prefix=${_HOST_DIR}/usr	\
			--target=${_TARGET}	\
			--enable-targets=arm	\
			--enable-optimized	\
			--enable-shared	\
			${ENABLE_LIBCPP}	\
			--disable-assertions	\
			--disable-bindings	\
			--with-default-sysroot=${_SYSROOT}	\
			--with-gcc-toolchain=${_HOST_DIR}/usr	\
			--with-binutils-include=${_HOST_DIR}/usr/lib/gcc/${_TARGET}/${_GCC_VER}/plugin/include

	# export EXTRA_LD_OPTIONS="-lc++abi"
	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# build clang for host
#
function build_clang_host()
{
	dir="${_BUILD_DIR}/llvm_host"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg clang_host
		return
	fi

	rm -fr "$dir"
	mkdir -p "$dir"
	prepare_clang

	cd "$dir"

	cmake ${_SOURCE_DIR}/llvm	\
		-DCMAKE_BUILD_TYPE=Release	\
		-DCMAKE_INSTALL_PREFIX=${_HOST_DIR}/usr	\
		-DCMAKE_C_COMPILER=${_GCC}	\
		-DCMAKE_CXX_COMPILER=${_GXX}	\
		-DCMAKE_CXX_FLAGS="-std=c++11"	\
		-DLLVM_TARGETS_TO_BUILD="X86;ARM"	\
		-DLLVM_ENABLE_ASSERTIONS=OFF

	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# extract lib to destination
#
function install_existing_lib()
{
	_PACKAGE=$1
	_DEST=$2

	echo "Installing ${_PACKAGE} ..."

	tar xf ${_PACKAGE} -C ${_DEST}
}
#
###############################################################################
#
# usage
#
function usage()
{
	echo "Usage: $1 [options]"
	echo "Options:"
	echo "-i                target abi, [${_ABI}]"
	echo "-a                target arch, [${_ARCH}]"
	echo "-t                target, [${_TARGET}]"
	echo "-h                host directory, [${_HOST_DIR}]"
	echo "-d                build with gdb"
	echo "-e                using existing glibc"
	echo "-c                clean build directory"
	echo "-l                build clang"
}
#
###############################################################################
#
# ln -s everything ${_TARGET}-* to /usr/local/bin
#
function do_link()
{
	files=`ls ${_HOST_DIR}/usr/bin/${_TARGET}-*`

	for file in $files ; do
		name=`basename $file`
		ln -fs "$file" /usr/local/bin/$name
	done
}
#
###############################################################################
#
# work start from here
#
_TARGET=aarch64-unknown-linux-gnu
_HOST_DIR=/opt/toolchain-clang/host
_SOURCE_DIR=`pwd`/source
_BUILD_DIR=`pwd`/build

_GAWK_VER=4.1.3
_BINUTILS_VER=2.25
_M4_VER=1.4.17
_GMP_VER=6.0.0a
_MPFR_VER=3.1.3
_MPC_VER=1.0.3
_GCC_VER=4.9.3
_HEADER_VER=3.14.1
_GLIBC_VER=2.19
_GDB_VER=7.7.1
_CLANG_VER=3.7.0

_ABI="lp64"
_ARCH="armv8-a"
_WITH_GDB=1
_USE_EXISTING_LIBC=0
_BUILD_CLANG=1
_GCC=gcc
_GXX=g++

while getopts i:a:t:h:decl flag; do
	case $flag in
		i)
			_ABI=$OPTARG
			;;
		a)
			_ARCH=$OPTARG
			;;
		h)
			_HOST_DIR=$OPTARG
			;;
		d)
			_WITH_GDB=1
			;;
		e)
			_USE_EXISTING_LIBC=1
			;;
		c)
			rm -fr ${_BUILD_DIR}
			exit 0
			;;
		l)
			_BUILD_CLANG=1
			;;
		*)
			usage $0
			exit 0
			;;
	esac
done

_SYSROOT=${_HOST_DIR}/usr/${_TARGET}/sysroot

_GNU_MIRRORS=http://mirrors.ustc.edu.cn/gnu

export LDFLAGS="-L${_HOST_DIR}/lib -L${_HOST_DIR}/usr/lib -Wl,-rpath,${_HOST_DIR}/usr/lib"
export PATH="${_HOST_DIR}/bin:${_HOST_DIR}/usr/bin:$PATH"

mkdir -p "${_SOURCE_DIR}"
mkdir -p "${_BUILD_DIR}"

build_binutils
build_m4
build_gmp
build_mpfr
build_mpc

if [ "${_USE_EXISTING_LIBC}" = "0" ]; then
	build_gcc initial
	build_linux_headers
	build_gawk
	build_glibc base
	build_gcc intermediate
	build_glibc full
else
	build_linux_headers
	install_existing_lib glibc.tar.xz "${_SYSROOT}"
fi
build_gcc final

if [ "${_WITH_GDB}" = "1" ]; then
	build_gdb
fi

if [ "${_BUILD_CLANG}" = "1" ] ; then
	precheck
	build_clang
fi

do_link
#
###############################################################################
#
# vim: ts=4 noet ci pi sts=0 sw=4
