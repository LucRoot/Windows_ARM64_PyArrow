@echo on
rem Arrow C++ build for Windows ARM64 — replicates the upstream msvc-arm64 CI job
rem (.github/workflows/cpp_windows.yml with arch=arm64): Ninja + BUNDLED deps +
rem UNITY_BUILD + SIMD NONE. Feature set trimmed to what pyarrow/datasets needs.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" arm64 || exit /B 1
echo VCVARS_INITIALIZED rc=%ERRORLEVEL%
rem Edit these placeholders to match your layout.
set BASE=C:\Users\you\build
set NINJADIR=C:\Users\you\tools\ninja
set PYEXE=C:\Users\you\.venv-arm64\Scripts\python.exe
set SRC=%BASE%\arrow-25.0.0\cpp
set BLD=%BASE%\arrow-build
set DIST=%BASE%\arrow-dist
set PATH=%NINJADIR%;%PATH%

rem BZ2 OFF: bundled bzip2 builds via ${MAKE} (empty under Ninja) -> broken upstream;
rem upstream Windows CI (cpp_windows.yml + msvc-arm64 job) sets ARROW_WITH_BZ2=OFF.
cmake -S %SRC% -B %BLD% -G Ninja ^
 -DCMAKE_BUILD_TYPE=Release ^
 -DCMAKE_INSTALL_PREFIX=%DIST% ^
 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ^
 -DCMAKE_CXX_STANDARD=20 ^
 -DCMAKE_UNITY_BUILD=ON ^
 -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF ^
 -DPython3_EXECUTABLE=%PYEXE% ^
 -DARROW_BUILD_SHARED=ON ^
 -DARROW_BUILD_STATIC=OFF ^
 -DARROW_BUILD_TESTS=OFF ^
 -DARROW_BUILD_BENCHMARKS=OFF ^
 -DARROW_BUILD_UTILITIES=OFF ^
 -DARROW_DEPENDENCY_SOURCE=BUNDLED ^
 -DARROW_DEPENDENCY_USE_SHARED=OFF ^
 -DARROW_PYTHON=ON ^
 -DARROW_COMPUTE=ON ^
 -DARROW_ACERO=ON ^
 -DARROW_DATASET=ON ^
 -DARROW_FILESYSTEM=ON ^
 -DARROW_CSV=ON ^
 -DARROW_JSON=ON ^
 -DARROW_PARQUET=ON ^
 -DPARQUET_REQUIRE_ENCRYPTION=OFF ^
 -DARROW_MIMALLOC=ON ^
 -DARROW_JEMALLOC=OFF ^
 -DARROW_WITH_ZLIB=ON ^
 -DARROW_WITH_LZ4=ON ^
 -DARROW_WITH_ZSTD=ON ^
 -DARROW_WITH_SNAPPY=ON ^
 -DARROW_WITH_BROTLI=ON ^
 -DARROW_WITH_BZ2=OFF ^
 -DARROW_WITH_OPENTELEMETRY=OFF ^
 -DARROW_SIMD_LEVEL=NONE ^
 -DARROW_RUNTIME_SIMD_LEVEL=NONE ^
 -DARROW_USE_GLOG=OFF ^
 -DARROW_FLIGHT=OFF ^
 -DARROW_GANDIVA=OFF ^
 -DARROW_S3=OFF ^
 -DARROW_GCS=OFF ^
 -DARROW_AZURE=OFF ^
 -DARROW_HDFS=OFF ^
 -DARROW_ORC=OFF ^
 -DARROW_SUBSTRAIT=OFF ^
 -DARROW_PACKAGE_KIND=python-wheel-windows-arm64 ^
 -Dxsimd_SOURCE=BUNDLED || exit /B 1

cmake --build %BLD% --target install -j 8 || exit /B 1
echo ARROW_CPP_BUILD_OK
