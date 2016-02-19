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
	suffix=$4

	cd "${SRCDIR}"

	if [ ! -e $package ] ; then
		wget $url/$package
	fi

	mkdir -p "${BLDDIR}/${name}${suffix}"

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

function clean()
{
	make clean
	rm -f .succeeded
}

function uninstall()
{
	rm -rf $PREFIX/usr/include/llvm
	rm -rf $PREFIX/usr/include/llvm-c
	rm -rf $PREFIX/usr/include/clang
	rm -rf $PREFIX/usr/include/clang-c
	rm -rf $PREFIX/usr/include/cxxabi
	rm -rf $PREFIX/usr/lib/libLLVM*
	rm -rf $PREFIX/usr/lib/llvm*
	rm -rf $PREFIX/usr/lib/LLVM*
	rm -rf $PREFIX/usr/lib/clang
	rm -rf $PREFIX/usr/lib/libclang*
	rm -rf $PREFIX/usr/lib/libLTO*
	rm -rf $PREFIX/usr/lib/BugpointPasses.so
	rm -rf $PREFIX/usr/bin/llvm*
	rm -rf $PREFIX/usr/bin/clang*
	rm -rf $PREFIX/usr/bin/llc
	rm -rf $PREFIX/usr/bin/lli
	rm -rf $PREFIX/usr/bin/macho-dump
	rm -rf $PREFIX/usr/bin/bugpoint
	rm -rf $PREFIX/usr/bin/verify-uselistorder
	rm -rf $PREFIX/usr/bin/obj2yaml
	rm -rf $PREFIX/usr/bin/yaml2obj
	rm -rf $PREFIX/usr/bin/git-clang-format
	rm -rf $PREFIX/usr/bin/opt
	rm -rf $PREFIX/usr/share/clang
	rm -rf $PREFIX/usr/share/llvm

	rm -rf $PREFIX/usr/include/c++/v1
	rm -rf $PREFIX/usr/lib/libc++*

	rm -rf $PREFIX/usr/lib/libgtest*
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
# gawk for building glibc
#
function build_gawk()
{
	_VER=${_GAWK_VER}
	_PACKAGE=gawk-${_VER}.tar.xz

	dir="${BLDDIR}/gawk"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg gawk
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${GNU_MIRRORS}/gawk gawk

	cd $dir
	${SRCDIR}/gawk/configure --prefix=${PREFIX}/usr

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
	_VER=${_GLIBC_VER}
	_PACKAGE=glibc-${_VER}.tar.xz

	dir="${BLDDIR}/glibc"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg glibc
		return
	fi

	rm -fr $dir
	prepare_package ${_PACKAGE} ${GNU_MIRRORS}/glibc glibc
	cd $dir

	export CFLAGS="-O2 -U_FORTIFY_SOURCE -fno-stack-protector"
	export CXXFLAGS="-O2 -U_FORTIFY_SOURCE -fno-stack-protector"

	${SRCDIR}/glibc/configure	\
			--prefix=$PREFIX/usr	\
			--enable-add-ons	\
			--enable-obsolete-rpc	\
			--enable-bind-now	\
			--enable-shared	\
			--enable-multi-arch	\
			--enable-stackguard-randomization	\
			--disable-profile	\
			--disable-werror

	# damn
	mkdir -p "$PREFIX/etc"
	touch "$PREFIX/etc/ld.so.conf"

	build_and_install

	unset CFLAGS CXXFLAGS
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# clang
#
function build_clang()
{
	dir="${BLDDIR}/llvm"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg clang
		return
	fi

	_VER=${_CLANG_VER}
	_PACKAGE_LLVM=llvm-${_VER}.src.tar.xz
	_PACKAGE_CFE=cfe-${_VER}.src.tar.xz
	_PACKAGE_CRT=compiler-rt-${_VER}.src.tar.xz

	_URL=${LLVM_URL}/${_VER}

	rm -fr "$dir"
	prepare_package ${_PACKAGE_LLVM} ${_URL} llvm
	prepare_package ${_PACKAGE_CFE} ${_URL} llvm/tools/clang
	prepare_package ${_PACKAGE_CRT} ${_URL} llvm/projects/compiler-rt
	cd "$dir"

	cmake ${SRCDIR}/llvm	\
		-DCMAKE_BUILD_TYPE=Release	\
		-DCMAKE_INSTALL_PREFIX=$PREFIX/usr	\
		-DCMAKE_C_COMPILER=${GCC}	\
		-DCMAKE_CXX_COMPILER=${GXX}	\
		-DLLVM_TARGETS_TO_BUILD="X86"	\
		-DLLVM_ENABLE_LIBCXX=ON	\
		-DLLVM_ENABLE_ASSERTIONS=OFF

	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# libc++
#
function build_libcxx()
{
	step=$1
	dir="${BLDDIR}/libcxx-$step"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg libcxx
		return
	fi

	_VER=${_CLANG_VER}
	_PACKAGE=libcxx-${_VER}.src.tar.xz
	_URL=${LLVM_URL}/${_VER}

	rm -fr "$dir"
	prepare_package ${_PACKAGE} ${_URL} libcxx "-$step"
	cd "$dir"

	_gcc_ver=`LANGUAGE=en_US ${GXX} --version | grep ^g++ | sed 's/^.* //g' | sed 's#\([0-9]\.[0-9]\)\.[0-9]#\1#'`
	# FIXME gcc's target name is not same as system's folder name on some paltform.
	_gcc_target=`LANGUAGE=en_US ${GXX} -v 2>&1 | grep "Target: " | cut -d' ' -f2`
	if [ ! -d "/usr/include/${_gcc_target}" ] ; then
		if [ -d "/usr/include/i386-linux-gnu" ] ; then
			_gcc_target="i386-linux-gnu"
		elif [ -d "/usr/include/i586-linux-gnu" ] ; then
			_gcc_target="i586-linux-gnu"
		elif [ -d "/usr/include/i686-linux-gnu" ] ; then
			_gcc_target="i686-linux-gnu"
		else
			echo "can not find include folder!"
			return
		fi
	fi

	major=`echo $_VER | cut -d'.' -f1`
	minor=`echo $_VER | cut -d'.' -f2`
	if ([ "$major" -ge "3" ] && [ "$minor" -ge "7" ]) then
		_LIBSUPCXX_CMAKE_DEF="-DLIBCXX_CXX_ABI_INCLUDE_PATHS"
		_LIBCXX_CMAKE_DEF="-DLIBCXX_CXX_ABI_INCLUDE_PATHS"
	else
		_LIBSUPCXX_CMAKE_DEF="-DLIBCXX_LIBSUPCXX_INCLUDE_PATHS"
		_LIBCXX_CMAKE_DEF="-DLIBCXX_LIBCXXABI_INCLUDE_PATHS"
	fi

	case $step in
		base)
			_CXXABI=libsupc++		
			#_CXXABI=libstdc++	
			_CXXABI_PATHS_FLAG="${_LIBSUPCXX_CMAKE_DEF}=/usr/include/c++/${_gcc_ver};/usr/include/c++/${_gcc_ver}/${_gcc_target};/usr/include/${_gcc_target}/c++/${_gcc_ver}"
			;;
		final)
			_CXXABI=libcxxabi
			_CXXABI_PATHS_FLAG="${_LIBCXX_CMAKE_DEF}=$PREFIX/usr/include/cxxabi"
			;;
		*)
			echo "Unkown build step for libcxx: $step"
			return
			;;
	esac

	cmake "$SRCDIR/libcxx"	\
		-DCMAKE_BUILD_TYPE=Release	\
		-DCMAKE_INSTALL_PREFIX=$PREFIX/usr	\
		-DCMAKE_C_COMPILER=clang	\
		-DCMAKE_CXX_COMPILER=clang++	\
		-DLIBCXX_CXX_ABI=${_CXXABI}	\
		${_CXXABI_PATHS_FLAG}

	build_and_install
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# libc++abi
#
function build_libcxxabi()
{
	dir="${BLDDIR}/libcxxabi"

	if [ -f "$dir/.succeeded" ] ; then
		print_ignore_build_msg libcxxabi
		return
	fi

	_VER=${_CLANG_VER}
	_PACKAGE=libcxxabi-${_VER}.src.tar.xz
	_URL=${LLVM_URL}/${_VER}

	rm -fr "$dir"
	prepare_package ${_PACKAGE} ${_URL} libcxxabi
	cd "$dir"

	cmake "${SRCDIR}/libcxxabi"	\
		-DCMAKE_BUILD_TYPE=Release	\
		-DCMAKE_INSTALL_PREFIX=$PREFIX/usr	\
		-DCMAKE_C_COMPILER=clang	\
		-DCMAKE_CXX_COMPILER=clang++	\
		-DLIBCXXABI_LIBCXX_INCLUDES="$PREFIX/usr/include/c++/v1"

	build_and_install
	cp -a ${SRCDIR}/libcxxabi/include $PREFIX/usr/include/cxxabi
	mark_build_succeeded
	cd -
}
#
###############################################################################
#
# usage
#
function usage()
{
	echo "Usage: $1 [options]"
	echo "[-p prefix] custom prefix"
	echo "[-v version] choose specify version of clang"
	echo "[-c] use specify libc"
	echo "[-u] uninstall clang"
}
#
###############################################################################
#
# main
#
PREFIX=
SRCDIR=`pwd`/source
BLDDIR=`pwd`/build
GCC=gcc
GXX=g++

GNU_MIRRORS=http://mirrors.ustc.edu.cn/gnu
LLVM_URL=http://llvm.org/releases

BUILD_LIBC=0

_GLIBC_VER=2.13
_GAWK_VER=4.1.0
_CLANG_VER=3.7.1 #default to 3.7.1

while getopts p:c:v:u flag; do
	case $flag in
		p)
			PREFIX=$OPTARG
			;;
		c)
			BUILD_LIBC=1
			;;
		v)
			_CLANG_VER=$OPTARG
			;;
		u)
			uninstall
			exit 0
			;;
		*)
			usage $0
			exit 0
			;;
	esac
done

precheck

mkdir -p "${SRCDIR}"
mkdir -p "${BLDDIR}"

if [ "$BUILD_LIBC" = "1" ] ; then
	build_gawk
	build_glibc
fi

build_clang
build_libcxx base
build_libcxxabi
build_libcxx final

###############################################################################
#
# vim: ts=4 noet ci pi sts=0 sw=4
