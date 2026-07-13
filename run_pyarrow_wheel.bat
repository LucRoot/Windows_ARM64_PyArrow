@echo off
rem Wrapper: own (hidden) console so vcvarsall survives; internal redirection.
call "C:\RootClaw\docs\pyarrow_arm64_build\build_pyarrow_wheel.bat" > "C:\RootClaw\docs\pyarrow_arm64_build\pyarrow_build.out.log" 2> "C:\RootClaw\docs\pyarrow_arm64_build\pyarrow_build.err.log"
