@echo off
rem Wrapper: gives cmd its own (hidden) console so vcvarsall survives,
rem and redirects internally instead of via Start-Process stream redirection.
call "%~dp0build_arrow_cpp.bat" > "%~dp0cpp_build.out.log" 2> "%~dp0cpp_build.err.log"
