@echo off
rem Wrapper: gives cmd its own (hidden) console so vcvarsall survives,
rem and redirects internally instead of via Start-Process stream redirection.
call "C:\RootClaw\docs\pyarrow_arm64_build\build_arrow_cpp.bat" > "C:\RootClaw\docs\pyarrow_arm64_build\cpp_build.out.log" 2> "C:\RootClaw\docs\pyarrow_arm64_build\cpp_build.err.log"
