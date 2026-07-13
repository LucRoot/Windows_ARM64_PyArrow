@echo off
rem Wrapper: own (hidden) console so vcvarsall survives; internal redirection.
call "%~dp0build_pyarrow_wheel.bat" > "%~dp0pyarrow_build.out.log" 2> "%~dp0pyarrow_build.err.log"
