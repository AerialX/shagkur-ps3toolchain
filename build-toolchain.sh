#!/bin/sh
#---------------------------------------------------------------------------------
# Check Parameters
#---------------------------------------------------------------------------------

if ! test $PS3DEV; then { echo "Error: \$PS3DEV not set."; exit 1; } fi

target=$1
prefix=$PS3DEV/host/$target
buildscriptdir=`dirname $PWD/$0`
PATH=$PATH:$PS3DEV/bin:$prefix/bin

export PATH

PLATFORM=`uname -s`

case $PLATFORM in
	*BSD*)
		MAKE=gmake
		;;
	*)
		MAKE=make
		;;
esac

case $PLATFORM in
	Darwin )
		cflags="-mmacosx-version-min=10.4 -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch i386 -arch ppc"
		ldflags="-mmacosx-version-min=10.4 -arch i386 -arch ppc -Wl,-syslibroot,/Developer/SDKs/MacOSX10.4u.sdk"
		;;
	MINGW32* )
		cflags="-D__USE_MINGW_ACCESS"
		;;
esac

case $target in
	ppu | spu | clean) ;;
	"") 
		{ echo "Please specify build target (ppu/spu/clean)"; exit 1; }
		;;
	*) 
		{ echo "Unkonwn build target"; exit 1; }
		;;
esac

case $target in
	ppu)
		binutils_opts="--enable-64-bit-bfd"
		gcc_opts="--enable-languages=c,c++ --with-cpu=cell --enable-long-double-128 --disable-libstdcxx-pch"
		newlib_opts="--enable-newlib-multithread"
		;;
	spu)
		binutils_opts=""
		gcc_opts="--enable-languages=c --disable-libssp"
		newlib_opts=""
		;;
	*)
		binutils_opts=""
		gcc_opts=""
		newlib_opts=""
		;;
esac
		
checkdepends() {
	autoconf --version 1>/dev/null || { echo "Error: autoconf missing."; exit 1; }
	automake --version 1>/dev/null || { echo "Error: automake missing."; exit 1; }
	
	if ! which bison >/dev/null 2>&1
	then
		if ! which yacc >/dev/null 2>&1
		then
			{ echo "Error: bison/yacc missing."; exit 1; }
		else
			command=yacc
		fi
	else
		command=bison
	fi
	$command -V 1>/dev/null || { echo "Error: bison missing."; exit 1; }
	
	flex --version 1>/dev/null || { echo "Error: flex missing."; exit 1; }
	gcc --version 1>/dev/null || { echo "Error: gcc missing."; exit 1; }
	make -v 1>/dev/null || { echo "Error: make missing."; exit 1; }
	makeinfo --version 1>/dev/null || { echo "Error: makeinfo missing."; exit 1; }
	patch -v 1>/dev/null || { echo "Error: patch missing."; exit 1; }
	
	( ls -ld $PS3DEV || mkdir -p $PS3DEV ) 1> /dev/null 2> /dev/null || { echo "ERROR: Create $PS3DEV before continuing."; exit 1; }
	touch $PS3DEV/test.tmp 1> /dev/null || { echo "ERROR: Grant write permissions for $PS3DEV before continuing."; exit 1; }
	
	echo "All dependecies solved."
}

download() {
	if [ ! -f binutils-2.20.tar.bz2 ]
	then
		wget --continue ftp://ftp.gnu.org/gnu/binutils/binutils-2.20.tar.bz2 || { exit 1; }
	fi
	
	if [ ! -f gcc-4.5.1.tar.bz2 ]
	then
		wget --continue ftp://ftp.gnu.org/gnu/gcc/gcc-4.5.1/gcc-4.5.1.tar.bz2 || { exit 1; }
	fi
	
	if [ ! -f newlib-1.18.0.tar.gz ]
	then
		wget --continue ftp://sources.redhat.com/pub/newlib/newlib-1.18.0.tar.gz || { exit 1; }
	fi
	
	if [ ! -f gmp-5.0.1.tar.bz2 ]
	then
		wget --continue ftp://ftp.gmplib.org/pub/gmp-5.0.1/gmp-5.0.1.tar.bz2 || { exit 1; }
	fi
	
	if [ ! -f mpc-0.8.2.tar.gz ]
	then
		wget --continue http://www.multiprecision.org/mpc/download/mpc-0.8.2.tar.gz || { exit 1; }
	fi
	
	if [ ! -f mpfr-2.4.2.tar.bz2 ]
	then
		wget --continue http://www.mpfr.org/mpfr-2.4.2/mpfr-2.4.2.tar.bz2 || { exit 1; }
	fi
}

prepare() {
	if [ ! -f prepared-binutils ]
	then
		tar xfvj binutils-2.20.tar.bz2 || { exit 1; }
		cd binutils-2.20 || { exit 1; }
		cat ../../patches/binutils-2.20.patch | patch -p1 || { exit 1; }
		cd $buildscriptdir/build
		touch prepared-binutils
	fi
	
	if [ ! -f prepared-gcc ]
	then
		tar xfvj gcc-4.5.1.tar.bz2 || { exit 1; }
		cd gcc-4.5.1 || { exit 1; }
		cat ../../patches/gcc-4.5.1.patch | patch -p1 || { exit 1; }
		tar xfvj ../gmp-5.0.1.tar.bz2 && ln -s gmp-5.0.1 gmp || { exit 1; }
		tar xfvz ../mpc-0.8.2.tar.gz && ln -s mpc-0.8.2 mpc || { exit 1; }
		tar xfvj ../mpfr-2.4.2.tar.bz2 && ln -s mpfr-2.4.2 mpfr || { exit 1; }
		cd $buildscriptdir/build
		touch prepared-gcc
	fi
		
	if [ ! -f prepared-newlib ]
	then
		tar xfvz newlib-1.18.0.tar.gz || { exit 1; }
		cd newlib-1.18.0 || { exit 1; }
		cat ../../patches/newlib-1.18.0.patch | patch -p1 || { exit 1; }
		cd $buildscriptdir/build
		touch prepared-newlib
	fi
}

checkdepends

if [ ! -d build ]
then
	mkdir -p build
fi

cd build

download
prepare

#---------------------------------------------------------------------------------
# build and install binutils
#---------------------------------------------------------------------------------

cd binutils-2.20 || { exit 1; }

if [ ! -d build-$target ]
then
	mkdir build-$target || { exit 1; }
fi

cd build-$target || { exit 1; }

if [ ! -f configured-binutils ]
then
  CFLAGS=$cflags LDFLAGS=$ldflags ../configure \
	--prefix=$prefix --target=$target --disable-nls --disable-shared --disable-debug \
	--with-gcc --with-gnu-as --with-gnu-ld --disable-dependency-tracking $binutils_opts \
	|| { echo "Error configuing $target binutils"; exit 1; }
	touch configured-binutils
fi

if [ ! -f built-binutils ]
then
  $MAKE || { echo "Error building ppc binutils"; exit 1; }
  touch built-binutils
fi

if [ ! -f installed-binutils ]
then
  $MAKE install || { echo "Error installing ppc binutils"; exit 1; }
  touch installed-binutils
fi
cd $buildscriptdir/build

#---------------------------------------------------------------------------------
# build and install just the c compiler
#---------------------------------------------------------------------------------

cd gcc-4.5.1 || { exit 1; }

if [ ! -d build-$target ]
then
	mkdir build-$target || { exit 1; }
fi

cd build-$target || { exit 1; }

if [ ! -f configured-gcc ]
then
	cp -r $buildscriptdir/build/newlib-1.18.0/newlib/libc/include $prefix/$target/sys-include
	CFLAGS="$cflags" LDFLAGS="$ldflags" CFLAGS_FOR_TARGET="-O2" LDFLAGS_FOR_TARGET="" ../configure \
	--prefix=$prefix \
	--target=$target \
	--enable-lto \
	--disable-nls \
	--disable-shared \
	--enable-threads \
	--disable-multilib \
	--disable-win32-registry \
	--with-newlib \
	--disable-dependency-tracking \
	$gcc_opts \
	2>&1 | tee gcc_configure.log
	touch configured-gcc
fi

if [ ! -f built-gcc-stage1 ]
then
	$MAKE all-gcc || { echo "Error building gcc stage1"; exit 1; }
	touch built-gcc-stage1
fi

if [ ! -f installed-gcc-stage1 ]
then
	$MAKE install-gcc || { echo "Error installing gcc stage1"; exit 1; }
	touch installed-gcc-stage1
	rm -fr $prefix/$target/sys-include
fi
cd $buildscriptdir/build

#---------------------------------------------------------------------------------
# build and install newlib
#---------------------------------------------------------------------------------

unset CFLAGS
unset LDFLAGS

cd newlib-1.18.0 || { exit 1; }

if [ ! -d build-$target ]
then
	mkdir build-$target || { exit 1; }
fi

cd build-$target || { exit 1; }

if [ ! -f configured-newlib ]
then
	../configure \
	--target=$target \
	--prefix=$prefix \
	--enable-newlib-hw-fp \
	$newlib_opts \
	|| { echo "Error configuring newlib"; exit 1; }
	touch configured-newlib
fi

if [ ! -f built-newlib ]
then
  $MAKE || { echo "Error building newlib"; exit 1; }
  touch built-newlib
fi
if [ ! -f installed-newlib ]
then
  $MAKE install || { echo "Error installing newlib"; exit 1; }
  touch installed-newlib
fi
cd $buildscriptdir/build

#---------------------------------------------------------------------------------
# build and install the final compiler
#---------------------------------------------------------------------------------

cd gcc-4.5.1 && cd build-$target || { exit 1; }

if [ ! -f built-gcc-stage2 ]
then
	$MAKE all || { echo "Error building gcc stage2"; exit 1; }
	touch built-gcc-stage2
fi

if [ ! -f installed-gcc-stage2 ]
then
	$MAKE install || { echo "Error installing gcc stage2"; exit 1; }
	touch installed-gcc-stage2
fi
cd $buildscriptdir/build

