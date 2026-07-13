@echo on
rem pyarrow wheel build — mirrors ci/scripts/python_wheel_windows_build.bat
rem (env vars + python -m build), adapted to ARM64 and our install prefix.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" arm64 || exit /B 1
rem Edit these placeholders to match your layout.
set BASE=C:\Users\you\build
set NINJADIR=C:\Users\you\tools\ninja
set PYEXE=C:\Users\you\.venv-arm64\Scripts\python.exe
set ARROW_HOME=%BASE%\arrow-dist
set CMAKE_PREFIX_PATH=%BASE%\arrow-dist
set PATH=%NINJADIR%;%PATH%
rem Pin Ninja: without this, scikit-build-core may pick the VS generator and its
rem default -A platform; Ninja + vcvarsall arm64 guarantees ARM64 objects.
set CMAKE_GENERATOR=Ninja
set CMAKE_BUILD_PARALLEL_LEVEL=8
set SETUPTOOLS_SCM_PRETEND_VERSION=25.0.0
set PYARROW_BUNDLE_ARROW_CPP=ON
set PYARROW_WITH_ACERO=ON
set PYARROW_WITH_DATASET=ON
set PYARROW_WITH_PARQUET=ON
set PYARROW_WITH_PARQUET_ENCRYPTION=OFF
set PYARROW_WITH_FLIGHT=OFF
set PYARROW_WITH_GANDIVA=OFF
set PYARROW_WITH_S3=OFF
set PYARROW_WITH_GCS=OFF
set PYARROW_WITH_AZURE=OFF
set PYARROW_WITH_HDFS=OFF
set PYARROW_WITH_ORC=OFF
set PYARROW_WITH_SUBSTRAIT=OFF

pushd %BASE%\arrow-25.0.0\python
%PYEXE% -m build --wheel . --no-isolation -vv ^
 -C build.verbose=true ^
 -C cmake.build-type=Release || exit /B 1
popd

echo === delvewheel repair (mangle msvcp140 for coexistence with torch) ===
for /f %%i in ('dir %BASE%\arrow-25.0.0\python\dist\pyarrow-*.whl /B') do (
  set WHEEL_NAME=%BASE%\arrow-25.0.0\python\dist\%%i
)
echo Wheel: %WHEEL_NAME%
%PYEXE% -m delvewheel repair -vv --ignore-existing --with-mangle ^
 -w %BASE%\arrow-25.0.0\python\repaired_wheels %WHEEL_NAME% || exit /B 1
echo PYARROW_WHEEL_BUILD_OK
