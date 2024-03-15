@echo off
setlocal EnableDelayedExpansion

where.exe /Q curl.exe || (
	echo ERROR: curl.exe was not found.
	exit /B 1
)

where.exe /Q tar.exe || (
	echo ERROR: tar.exe was not found.
	exit /B 1
)

where.exe /Q cmake.exe || (
	echo ERROR: cmake.exe was not found.
	exit /B 1
)

where.exe /Q git.exe || (
	echo ERROR: git.exe was not found.
	exit /B 1
)

where.exe /Q cl.exe || (
	if not exist "C:\Program Files (x86)\Microsoft Visual Studio\Installer" (
		echo ERROR: Visual Studio installation was not found.
		exit /B 1
	)

	for /f "tokens=*" %%i in ('"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath') do set VS=%%i

	if "!VS!" equ "" (
		echo ERROR: Visual Studio Native Desktop workload was not found.
		exit /B 1
	)
	call "!VS!\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 -no_logo || exit /B 1
)

if "%VSCMD_ARG_TGT_ARCH%" neq "x64" (
	echo ERROR: Run this from MSVC x64 native tools command prompt, 32-bit target is not supported.
	exit /b 1
)

set BUILD=%~dp0build
set DEPENDENCIES=%~dp0dependencies

set ZLIB_VERSION=1.3.1
set SNAPPY_VERSION=1.1.10
set ZSTD_VERSION=1.5.5

if not exist %BUILD% mkdir %BUILD%
if not exist %DEPENDENCIES% mkdir %DEPENDENCIES%

pushd %DEPENDENCIES%

if not exist zlib-%ZLIB_VERSION% (
	curl.exe -sfLO https://zlib.net/zlib-%ZLIB_VERSION%.tar.gz
	tar.exe -xf zlib-%ZLIB_VERSION%.tar.gz
)

cmake.exe -Wno-dev					^
	-S zlib-%ZLIB_VERSION%				^
	-B zlib-%ZLIB_VERSION%				^
	-DCMAKE_POLICY_DEFAULT_CMP0091=NEW		^
	-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded	^
	-DCMAKE_INSTALL_PREFIX=%DEPENDENCIES%\build	^
	|| exit /B 1
cmake.exe --build zlib-%ZLIB_VERSION% --config Release --target install --parallel || exit /B 1

if not exist snappy-%SNAPPY_VERSION% (
	curl.exe -sfLO https://github.com/google/snappy/archive/refs/tags/%SNAPPY_VERSION%.tar.gz
	tar.exe -xf %SNAPPY_VERSION%.tar.gz
)

cmake.exe -Wno-dev					^
	-S snappy-%SNAPPY_VERSION%			^
	-B snappy-%SNAPPY_VERSION%			^
	-DSNAPPY_BUILD_BENCHMARKS=OFF			^
	-DSNAPPY_BUILD_TESTS=OFF			^
	-DSNAPPY_FUZZING_BUILD=OFF			^
	-DSNAPPY_INSTALL=ON				^
	-DSNAPPY_REQUIRE_AVX=OFF			^
	-DSNAPPY_REQUIRE_AVX2=ON			^
	-DCMAKE_INSTALL_PREFIX=%DEPENDENCIES%\build	^
	|| exit /B 1
cmake.exe --build snappy-%SNAPPY_VERSION% --config Release --target install --parallel || exit /B 1

if not exist zstd-%ZSTD_VERSION% (
	curl.exe -sfLO https://github.com/facebook/zstd/releases/download/v%ZSTD_VERSION%/zstd-%ZSTD_VERSION%.tar.gz
	tar.exe -xf zstd-%ZSTD_VERSION%.tar.gz
)

cmake.exe -Wno-dev					^
	-S zstd-%ZSTD_VERSION%\build\cmake		^
	-B zstd-%ZSTD_VERSION%\build			^
	-DZSTD_BUILD_PROGRAMS=OFF			^
	-DZSTD_BUILD_SHARED=OFF				^
	-DZSTD_BUILD_STATIC=ON				^
	-DZSTD_BUILD_TESTS=OFF				^
	-DZSTD_LEGACY_SUPPORT=OFF			^
	-DZSTD_MULTITHREAD_SUPPORT=ON			^
	-DZSTD_PROGRAMS_LINK_SHARED=OFF			^
	-DZSTD_USE_STATIC_RUNTIME=ON			^
	-DCMAKE_INSTALL_PREFIX=%DEPENDENCIES%\build	^
	|| exit /B 1
cmake.exe --build zstd-%ZSTD_VERSION%\build --config Release --target install --parallel || exit /B 1

if not exist leveldb (
	git.exe clone https://github.com/Mojang/leveldb.git
	pushd leveldb
	git.exe checkout remotes/origin/t-yemekonnen/adding_zlib_support
	git.exe apply ..\..\define-compression-definitions.patch || exit /B 1
	popd leveldb
)

pushd leveldb

REM The cmake script that comes included with modern leveldb refuses
REM to locate any of the compression libraries needed to actually be
REM of any use - even on linux. Thanks Google.
REM
REM We're going old school. We'll just manually compile all the source
REM files needed and create a static library.

set LEVELDB_SRC=				^
	"db/builder.cc"                         ^
	"db/c.cc"                               ^
	"db/db_impl.cc"                         ^
	"db/db_iter.cc"                         ^
	"db/dbformat.cc"                        ^
	"db/dumpfile.cc"                        ^
	"db/filename.cc"                        ^
	"db/log_reader.cc"                      ^
	"db/log_writer.cc"                      ^
	"db/memtable.cc"                        ^
	"db/repair.cc"                          ^
	"db/table_cache.cc"                     ^
	"db/version_edit.cc"                    ^
	"db/version_set.cc"                     ^
	"db/write_batch.cc"                     ^
	"table/block_builder.cc"                ^
	"table/block.cc"                        ^
	"table/filter_block.cc"                 ^
	"table/format.cc"                       ^
	"table/iterator.cc"                     ^
	"table/merger.cc"                       ^
	"table/table_builder.cc"                ^
	"table/table.cc"                        ^
	"table/two_level_iterator.cc"           ^
	"util/arena.cc"                         ^
	"util/bloom.cc"                         ^
	"util/cache.cc"                         ^
	"util/coding.cc"                        ^
	"util/comparator.cc"                    ^
	"util/crc32c.cc"                        ^
	"util/env.cc"                           ^
	"util/filter_policy.cc"                 ^
	"util/hash.cc"                          ^
	"util/logging.cc"                       ^
	"util/options.cc"                       ^
	"util/status.cc"                        

cl.exe /nologo %LEVELDB_SRC% /c /EHsc /GR- /O2 /DLEVELDB_PLATFORM_WINDOWS /DWIN32 /I. /I./include /I%DEPENDENCIES%\build\include || exit /B 1
lib.exe /nologo *.obj /out:leveldb.lib /LIBPATH:%DEPENDENCIES%\build\lib zlibstatic.lib zstd_static.lib snappy.lib || exit /B 1

mkdir %BUILD%\include\leveldb %BUILD%\lib
copy /y .\include\leveldb %BUILD%\include\leveldb
copy /y leveldb.lib %BUILD%\lib\leveldb.lib

popd

popd

if "%GITHUB_WORKFLOW%" neq "" (
	7z.exe a -y mojang-leveldb.zip build\.
)