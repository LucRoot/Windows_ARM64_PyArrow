# Native pyarrow 25.0.0 on Windows ARM64: a from-source Apache Arrow C++ build that replicates Arrow's own msvc-arm64 CI job

*Built and verified 2026-07-13 on a Snapdragon X Elite (X1E80100), Windows 11 25H2 (build 26200), 64 GB RAM. Every command, flag, error, and number below comes from the logged build session; the scripts in this repo reproduce each step.*

---

## TL;DR

pyarrow publishes no `win_arm64` wheel, so on native Windows ARM64 the entire Hugging Face training stack stops at `pip install datasets` (gap tracked upstream in [apache/arrow#47195](https://github.com/apache/arrow/issues/47195); upstream reports Arrow's CI already builds win-arm64 wheels — they are simply not uploaded). This repo documents, as far as we can find, the first public native `win_arm64` build of Apache Arrow C++ 25.0.0 + pyarrow 25.0.0 that works by **replicating Arrow's own upstream `msvc-arm64` CI job** rather than inventing a new toolchain: Ninja + `vcvarsall arm64` + BUNDLED dependencies + `CMAKE_UNITY_BUILD=ON` + `ARROW_SIMD_LEVEL=NONE`, no vcpkg. The result is a repaired `pyarrow-25.0.0-cp311-cp311-win_arm64.whl` (15,196,861 bytes, sha256 logged in §6) that installs cleanly with `datasets 5.0.0` + `trl 1.8.0` next to a native torch, passes both smoke scripts in this repo, and ran a real downstream training pipeline's dry-run with exact parameter parity against its WSL2 and x86-emulated runs. Cost: ~45 minutes of build-machine time (plus the recon itself), including two diagnosed failures.

---

## Quickstart: install the wheel from the release

The delvewheel-repaired wheel is published as a GitHub release asset (release `v25.0.0`):

```powershell
# 1. ARM64 CPython 3.11 venv (the wheel is cp311-only; this build used 3.11.15 ARM64 via uv)
<path-to-arm64-python-3.11>\python.exe -m venv .venv-arm64

# 2. Download pyarrow-25.0.0-cp311-cp311-win_arm64.whl from this repo's Releases page,
#    verify it, then install:
#    15,196,861 bytes, sha256 240c476c26a10e7d83d3f899ad66839b819d3d973ee60673a7af787962ea3a3a
.venv-arm64\Scripts\python -m pip install .\pyarrow-25.0.0-cp311-cp311-win_arm64.whl

# 3. Smoke it (edit the hardcoded output path at the top of the script first)
.venv-arm64\Scripts\python smoke_pyarrow.py          # expect: PYARROW_SMOKE_OK

# 4. The point of the exercise: real datasets + trl
.venv-arm64\Scripts\python -m pip install datasets trl
.venv-arm64\Scripts\python smoke_datasets.py         # expect: DATASETS_SMOKE_OK
```

Notes:

- The wheel is delvewheel-repaired with `msvcp140.dll` mangled (`msvcp140-eb8785...dll`, plus `msvcp140_atomic_wait`), so it coexists with torch's own CRT runtime in the same venv.
- Expected smoke output includes `codec bz2: no` — that is by design, not a defect (§5).
- `smoke_pyarrow.py` and `smoke_datasets.py` hardcode their scratch-parquet paths to the build machine's docs directory; point them anywhere writable before running.

---

## 1. Environment

| Item | Value |
|---|---|
| CPU | Snapdragon X Elite (X1E80100), 12 Oryon cores |
| OS / RAM | Windows 11 25H2 (build 26200) ARM64, 64 GB |
| Python | CPython 3.11.15 ARM64 (via uv), venv at `C:\Users\rootl\.venv-arm64` with native `torch 2.12.1+cpu` already installed |
| Compiler | VS 2022 Build Tools v17.14.35, MSVC 14.44.35207 **native ARM64** (`VC\Tools\MSVC\14.44.35207\bin\HostARM64\arm64\cl.exe`), Windows SDK 10.0.26100.0 ucrt/arm64 |
| Build tools | cmake 4.3.1, ninja 1.13.1 **winarm64** (official ninja-build GitHub release binary), git 2.53.0 |
| Source | Apache Arrow 25.0.0, tag `apache-arrow-25.0.0` at commit `59bea6e`, depth-1 clone (95 MB) |
| Build deps in venv | cython 3.2.8, libcst 1.8.6, scikit_build_core 1.0.3, setuptools_scm 10.2.0, build 1.5.1, delvewheel 1.13.0, numpy 2.4.6 (Arrow's `python/requirements-build.txt` set + delvewheel) |

Source pin, verified against the remote before cloning:

```
$ git ls-remote --tags https://github.com/apache/arrow.git | grep "apache-arrow-25\.0\.0(\^\{\})?$"
1a58293a62d3f2053ff3afda67fa063c639f0af0  refs/tags/apache-arrow-25.0.0
59bea6ec485e7fe351d1aa6753f964f6a6bc353a  refs/tags/apache-arrow-25.0.0^{}
$ git clone --depth 1 --branch apache-arrow-25.0.0 --single-branch https://github.com/apache/arrow.git arrow-25.0.0
$ git log --oneline -1  -> 59bea6e MINOR: [Release] Update versions for 25.0.0
```

Two environment warnings, both earned during the session:

- **Disk.** `C:` was at 952 GB total / 36 GB free (97% used) at recon. The C++ build tree (`arrow-build`) measured 1.8 GB after the build; the install tree (`arrow-dist`) is 42 MB. Reclaim the build tree once the wheel is verified.
- **Thermals.** The X Elite throttles hard under sustained all-core load. Both stages ran at `-j8` (12 cores minus headroom); budget idle cool-downs if you chain builds.

---

## 2. Why this build is expected to work: extracting Arrow's own ARM64 CI config

The intellectual core of this repo: the configuration below is not guessed — it is read out of Arrow 25.0.0's own CI, which already compiles Arrow C++ on Windows ARM64 on every run. If upstream's config builds upstream's tree on upstream's ARM64 runners, replicating it on a local ARM64 box is the shortest path to a working wheel. The chain of evidence, all in-tree at tag `apache-arrow-25.0.0`:

1. **`.github/workflows/cpp_extra.yml`** defines a job `msvc-arm64`:
   `uses: ./.github/workflows/cpp_windows.yml with: arch: arm64, os: windows-11-arm, simd-level: NONE`.
2. **`.github/workflows/cpp_windows.yml`** (the reusable job it calls) establishes the C++ half:
   - `CMAKE_GENERATOR: Ninja`
   - `vcvarsall.bat %VCVARS_ARCH%` with `arm64` — the native ARM64 MSVC toolchain, not cross-compile
   - **BUNDLED dependencies**: `ARROW_DEPENDENCY_SOURCE` is never set (BUNDLED is the default) and `BOOST_SOURCE: BUNDLED` is set explicitly. No vcpkg anywhere on the ARM64 path.
   - `CMAKE_UNITY_BUILD: ON`, `CMAKE_CXX_STANDARD: "20"`, cmake 4.1.2 on CI (this build used 4.3.1)
   - `ARROW_SIMD_LEVEL = NONE` passed as an input: `ci/scripts/cpp_build.sh` would default to `DEFAULT`; the CI job deliberately overrides to `NONE` for arm64. Replicated exactly.
3. **`ci/scripts/python_wheel_windows_build.bat`** (the x64 wheel script) establishes the pyarrow half, which is arch-independent in structure: `PYARROW_BUNDLE_ARROW_CPP=ON`, `PYARROW_WITH_*` flags mirroring the C++ feature set, `ARROW_HOME`/`CMAKE_PREFIX_PATH` pointing at the C++ install prefix, `python -m build --wheel --no-isolation`, then `delvewheel repair --with-mangle` — the mangle step renames `msvcp140.dll` inside the wheel so pyarrow can coexist with other packages (torch, here) that ship their own copy.
4. **`dev/tasks/python-wheels/github.windows.yml`** is x64-only in 25.0.0 (docker + vcpkg); there is no ARM64 *wheel* task in-tree. The "CI builds win-arm64 wheels" of apache/arrow#47195 refers to later main-branch work. The authoritative ARM64 evidence in the 25.0.0 tag is the `msvc-arm64` C++ job — which is what this build replicates, plus the x64 wheel script's packaging steps.

### Decision: BUNDLED, not vcpkg

Arrow's x64 Windows wheel path uses vcpkg with custom `amd64-windows-static-md-*` triplets. In the 25.0.0 tag, `ci/vcpkg/` has **no windows-arm64 triplet** (only linux/osx arm64). Authoring a custom triplet and building 15 dependencies through a second, untested toolchain buys nothing over the path upstream's own ARM64 CI already exercises. BUNDLED it is.

---

## 3. Build configuration: every flag and why

C++ stage (`build_arrow_cpp.bat` in this repo, run inside `vcvarsall arm64`):

| Flag | Value | Why |
|---|---|---|
| CMAKE_GENERATOR | Ninja | The ARM64 CI job's generator; also fastest. Arrow docs require Ninja for Windows/ARM64. |
| CMAKE_BUILD_TYPE | Release | wheel parity |
| CMAKE_POLICY_VERSION_MINIMUM | 3.5 | cmake 4.3.1 rejects bundled deps carrying `cmake_minimum_required < 3.5` (§8) |
| CMAKE_CXX_STANDARD | 20 | CI sets it explicitly |
| CMAKE_UNITY_BUILD | ON | CI uses it; large wall-clock win; 64 GB RAM absorbs the bigger translation units |
| CMAKE_INTERPROCEDURAL_OPTIMIZATION | OFF | Wheel CI uses ON; it costs a long LTCG link for runtime perf that is not the bottleneck (datasets is I/O-shaped). Revisit if perf matters. |
| ARROW_BUILD_SHARED / ARROW_BUILD_STATIC | ON / OFF | pyarrow wheels bundle shared libs |
| ARROW_DEPENDENCY_SOURCE | BUNDLED | Per the msvc-arm64 CI job (§2) |
| ARROW_DEPENDENCY_USE_SHARED | OFF | Static-link deps into `arrow.dll` → self-contained wheel (CI parity) |
| ARROW_PYTHON | ON | Builds the arrow_python C++ bridge pyarrow binds to (deprecated in 25.0.0 — see §8 gotcha 6) |
| ARROW_COMPUTE / ACERO / DATASET / FILESYSTEM / CSV / JSON | ON | datasets' real usage + wheel parity; ACERO is required by DATASET |
| ARROW_PARQUET | ON | HF datasets reads parquet constantly |
| PARQUET_REQUIRE_ENCRYPTION | OFF | Avoids the OpenSSL dep; datasets never touches encrypted parquet |
| ARROW_WITH_ZLIB / LZ4 / ZSTD / SNAPPY / BROTLI | ON | Parquet codec support; all portable C/C++, all bundled, all configured cleanly |
| ARROW_WITH_BZ2 | **OFF** | Bundled bzip2 is broken under Ninja upstream, and upstream's own Windows CI sets it OFF (§5) |
| ARROW_MIMALLOC | ON | CI uses it on Windows; bundled |
| ARROW_FLIGHT / GANDIVA / S3 / GCS / AZURE / HDFS / ORC / SUBSTRAIT | OFF | Not needed by datasets; each pulls a heavy dep tree (S3 = AWS SDK) |
| ARROW_WITH_OPENTELEMETRY | OFF | Wheel CI has it ON; heavy and unused by pyarrow consumers |
| ARROW_SIMD_LEVEL / ARROW_RUNTIME_SIMD_LEVEL | NONE | Exact msvc-arm64 CI choice; the MSVC-ARM64 SIMD path is not enabled upstream |
| ARROW_USE_GLOG / BUILD_TESTS / BENCHMARKS / UTILITIES | OFF | Lean build |
| ARROW_PACKAGE_KIND | python-wheel-windows-arm64 | Informational tag, mirrors CI's `python-wheel-windows` |
| Python3_EXECUTABLE | venv python | Deterministic FindPython3 (numpy 2.4.6 headers found via the venv) |

pyarrow stage (`build_pyarrow_wheel.bat`), mirroring `python_wheel_windows_build.bat`:

| Setting | Value | Why |
|---|---|---|
| `vcvarsall.bat arm64` | — | Native ARM64 toolchain for the Cython extension compile |
| CMAKE_GENERATOR | Ninja | Without it, scikit-build-core can fall back to the VS generator's default `-A` platform; Ninja + vcvarsall arm64 guarantees ARM64 objects |
| CMAKE_BUILD_PARALLEL_LEVEL | 8 | Thermal headroom (12 cores) |
| ARROW_HOME / CMAKE_PREFIX_PATH | arrow-dist prefix | Where the C++ stage installed |
| SETUPTOOLS_SCM_PRETEND_VERSION | 25.0.0 | Deterministic version in a depth-1 clone (no tag history for setuptools_scm) |
| PYARROW_BUNDLE_ARROW_CPP | ON | Wheel carries the Arrow DLLs |
| PYARROW_WITH_ACERO / DATASET / PARQUET | ON | Mirror the C++ feature set |
| PYARROW_WITH_PARQUET_ENCRYPTION and all other PYARROW_WITH_* | OFF | Mirror the C++ feature set |
| Build command | `python -m build --wheel . --no-isolation -vv -C build.verbose=true -C cmake.build-type=Release` | Per upstream wheel script |
| Repair | `python -m delvewheel repair -vv --ignore-existing --with-mangle` | Per upstream wheel script; mangles msvcp140 for torch coexistence |

---

## 4. Failure story #1: `Start-Process -RedirectStandardOutput` kills vcvarsall mid-init

The first C++ launch was found dead three minutes after start. Evidence:

- `cpp_build.out.log` (12 lines) ended at the vsdevcmd banner; the `[vcvarsall.bat] Environment initialized for: 'arm64'` line never printed.
- `cpp_build.err.log`: 0 bytes. `arrow-build/` was never created. No cmd/cmake/ninja processes alive.
- The batch died *during* vcvarsall, silently — not even the `set PATH` echo after it survived.

Bisection, in order:

1. **Git Bash → cmd quoting.** `cmd /c` probes from Git Bash need `MSYS_NO_PATHCONV=1` (otherwise MSYS path-converts `/c` and cmd starts bare: banner, prompt, EOF-exit) *and* cannot carry escaped inner quotes: cmd parses its own command line rather than receiving argv through MSVCRT, so `\"` arrives literally and fails with `'\"C:\...\vcvarsall.bat\"' is not recognized`. Lesson that stuck: **for anything non-trivial, write a `.bat` file and call it by path** (a path with no spaces needs no quoting at all).
2. **The toolchain is fine.** A probe `.bat` (vcvarsall arm64 → echo rc → `where cl.exe`) run via `cmd /c path` from Git Bash succeeds: `[vcvarsall.bat] Environment initialized for: 'arm64'`, rc=0, `cl.exe` = `VC\Tools\MSVC\14.44.35207\bin\HostARM64\arm64\cl.exe` (native ARM64 compiler confirmed; SDK 10.0.26100.0 ucrt/arm64 present).
3. **The launch mechanism is the killer.** Launch #1 used `powershell Start-Process cmd.exe -ArgumentList '/c',build.bat -RedirectStandardOutput ... -RedirectStandardError ...`. Start-Process stream redirection runs the child **without a console**; vcvarsall/vsdevcmd — which spawns `powershell.exe` grandchildren — dies mid-init in that mode: after the banner, before the initialized line, no error text in either stream.

**Fix (pattern B):** the `run_cpp_build.bat` wrapper gives cmd its own (hidden) console and redirects *internally* — `call build_arrow_cpp.bat > out.log 2> err.log` — launched via `Start-Process cmd.exe /c run_cpp_build.bat -WindowStyle Hidden` with **no** Start-Process redirects. An `echo VCVARS_INITIALIZED rc=%ERRORLEVEL%` marker was added right after vcvarsall so any future death localizes to before/after that line. Launch #2 (pattern B) went straight past vcvarsall: 45 seconds in, cmake configure was deep in bundled-dep resolution — zlib/zstd checksum lines, `_M_ARM64 - found` (correct ARM64 target detection), Boost building from source, multiple parallel cmake/ninja ExternalProject processes.

---

## 5. Failure story #2: bundled bzip2 hardcodes `${MAKE}`, which is empty under Ninja

Six and a half minutes into attempt #1 (with a cold dep cache), the build stopped at the bundled-dependency stage:

```
ninja: build stopped: subcommand failed
bzip2_ep-build-Release.cmake:37 Command failed: no such file or directory
running 'libbz2.a' '-j12' 'CC=...cl.exe' 'CFLAGS=...' 'AR=...lib.exe' 'RANLIB=:'
```

The program token — make — is missing, so the command degenerates to executing `libbz2.a` as a program. Root cause: Arrow 25.0.0 `ThirdpartyToolchain.cmake:3118-3125`, `build_bzip2()`, hardcodes `BUILD_COMMAND ${MAKE} libbz2.a ...` with **no MSVC branch**. `${MAKE}` is only defined by Makefile generators; under Ninja it is empty. This is broken upstream for *any* Ninja build of bundled bzip2 — not ARM64-specific. A sweep for same-class failures found `${MAKE}` only in jemalloc (already OFF here) and bzip2; every other dep in the set (zlib/lz4/zstd/snappy/brotli/utf8proc/re2/thrift/mimalloc/xsimd/boost/rapidjson) is CMake-driven and configured fine.

The fix is upstream's own choice, cited in the script comment: `ci/scripts/cpp_build.sh:250` defaults `ARROW_WITH_BZ2=OFF`, and `.github/workflows/cpp_windows.yml:65` sets `ARROW_WITH_BZ2: OFF` — the msvc-arm64 CI job never exercises bundled bzip2. (That same yml line also turns BROTLI and LZ4 off, but those two have real CMake builds and configured cleanly here, so they stay ON.) Accepting OFF costs almost nothing for the target workload: bz2 is the rarest codec in datasets' world — parquet in the wild is snappy/zstd/gzip, and raw `.bz2` dataset files are decompressed by Python's stdlib `bz2` inside `datasets`, not by pyarrow. The deviation from x64 wheel codec parity is confined to bz2-compressed parquet.

Fix applied: `-DARROW_WITH_BZ2=OFF`, relaunched **in place** — the `arrow-build` cache was retained, completed ExternalProjects were not rebuilt, cmake re-configured (~2–3 min), and ninja resumed the truncated graph.

---

## 6. Execution record and timeline

All times UTC, 2026-07-13:

| Time | Event |
|---|---|
| ~21:50 | Recon, toolchain probe, clone, and build scripts done |
| 21:55 | C++ launch #1 — found dead 3 min later (Start-Process redirection, §4) |
| ~22:00 | Launch #2 (pattern B) — past vcvarsall, configure running |
| ~22:06 | Attempt #1 fails at `bzip2_ep`, 6.5 min in (§5) |
| ~22:10 | Relaunch in place with `ARROW_WITH_BZ2=OFF` |
| **22:18:03** | **`ARROW_CPP_BUILD_OK`** — attempt #2, ~8 min with warm dep cache; ~23 min total wall from first launch including both failure diagnoses. Final ninja graph: **206 steps, 0 failures**. Only stderr content: the non-fatal `ARROW_PYTHON is deprecated. Use CMake presets instead.` warning. |
| 22:20 | Wheel stage launched (pattern B, hardened with `CMAKE_GENERATOR=Ninja`, `CMAKE_BUILD_PARALLEL_LEVEL=8`). 40 s in: ninja step 62/68, Cython extensions compiling with `Hostarm64\arm64\cl.exe`, link lines carrying `/machine:ARM64`, outputs named `_parquet.cp311-win_arm64.pyd`. |
| **22:22:55** | **`PYARROW_WHEEL_BUILD_OK`** — ~3 min: 68-step ninja compile + wheel pack + delvewheel |
| ~22:25 | Wheel installed into the venv; both smoke scripts pass |
| ~22:30 | Downstream training dry-run (§7) |
| 22:35 | Downstream pytest suite (§7) |

Recon-to-verified: ~45 minutes of build-machine time plus the recon itself.

Artifacts:

- **`arrow-dist` (42 MB):** `bin/` = `arrow.dll`, `arrow_acero.dll`, `arrow_compute.dll`, `arrow_dataset.dll`, `parquet.dll`; `lib/` = matching import libs + `cmake/` packages (Arrow, ArrowAcero, ArrowCompute, ArrowDataset, Parquet) + `pkgconfig/`. Note `arrow_python.dll` is **absent by design** — Arrow 25.0.0 no longer ships a separate arrow_python C++ library from `cpp/` (hence the deprecation warning), and pyarrow's own `python/` CMakeLists builds the bridge in-tree: wheel-stage link lines reference `arrow_python.lib` from the pyarrow temp build dir, and `python/CMakeLists.txt`'s find_package list (Arrow/ArrowDataset/ArrowAcero/ArrowCompute/Parquet) exactly matches what `arrow-dist/lib/cmake` provides. No ArrowPython package exists or is required.
- **Wheel:** `arrow-25.0.0\python\repaired_wheels\pyarrow-25.0.0-cp311-cp311-win_arm64.whl` — **15,196,861 bytes**, sha256 `240c476c26a10e7d83d3f899ad66839b819d3d973ee60673a7af787962ea3a3a`. delvewheel mangled `msvcp140.dll` → `msvcp140-eb8785...dll` (plus `msvcp140_atomic_wait`) for coexistence with torch's runtime in the same venv. Wheel-stage stderr: one scikit-build metadata deprecation warning only.
- **`arrow-build` cache: 1.8 GB** — retain until the wheel is verified, then reclaim (disk was at 33 GB free).

---

## 7. Verification results

Scorecard from the session log:

| Check | Result |
|---|---|
| Arrow C++ 25.0.0 native win_arm64 build | PASS (206 ninja steps, 0 failures) |
| arrow-dist install tree (5 DLLs + cmake pkgs) | PASS |
| pyarrow 25.0.0 cp311-win_arm64 wheel + delvewheel | PASS (15.2 MB, sha256 above) |
| pyarrow smoke (parquet zstd, dataset scanner, acero) | PASS |
| codecs gzip/zstd/lz4/snappy/brotli | PASS (bz2 off by design, §5) |
| datasets 5.0.0 + trl 1.8.0 install, `pip check` | PASS (no broken requirements) |
| datasets API slice (from_list/map/split/parquet) | PASS |
| Downstream Cycle 1 dry-run native | PASS (param parity below) |
| Other 4 downstream training scripts import datasets | PASS (blocked only on pre-Cycle-1 artifacts, env-independent) |
| Downstream `pytest tests/ -q` | PASS (230 passed, 1 skipped in 15.76s, pytest 9.1.1) |

`smoke_pyarrow.py` output, verbatim claims from the log: pyarrow 25.0.0 on python 3.11.15 win32; parquet zstd round-trip OK; dataset scanner + acero filter OK; codec inventory `gzip/zstd/lz4/snappy/brotli = YES`, `bz2 = no`.

Ecosystem note from the install step: `frozenlist`/`propcache`/`multidict`/`yarl` all have native `win_arm64` wheels on PyPI now — pyarrow was the last missing piece for a native HF stack on Windows ARM64. `pip install datasets trl` resolved to datasets 5.0.0 + trl 1.8.0, exact parity with the project's WSL environment.

Downstream end-to-end (the consumer project this build unblocked, on native Windows ARM64 in the same venv):

- **Cycle 1 `train_trunk_foundation.py --dry-run`: PASSED** with `trainable params: 113,770,496 || all params: 1,833,798,656 || trainable%: 6.2041` — exact parity with the WSL2 and x86-emulated runs. The dry-run data path used real `datasets.map` (1 example, tokenized) and the forward pass returned `loss=2.527240753173828`, logits `[1,164,151669]`.
- The other four training scripts all import `datasets` successfully (zero ImportErrors) and fail only on missing pipeline artifacts that any environment — including WSL — would hit before Cycle 1 completes (empty adapter dir → `Can't find 'adapter_config.json'`; a missing `router_training.jsonl` that the script itself tells you to generate first).
- `pytest tests/ -q`: **230 passed, 1 skipped**, matching the project's 230-test baseline exactly, on native Windows ARM64 with real datasets 5.0.0 + pyarrow 25.0.0.

---

## 8. Gotchas compendium

Each of these cost real time; §4 and §5 are the two build-stoppers, the rest are traps with quick fixes.

1. **`Start-Process` stream redirection kills vcvarsall.** `-RedirectStandardOutput/-RedirectStandardError` runs cmd without a console, and vcvarsall/vsdevcmd (which spawn powershell.exe grandchildren) dies mid-init, silently. Use a wrapper `.bat` that redirects internally, launch it `Start-Process cmd.exe /c wrapper.bat -WindowStyle Hidden`. Full story: §4.
2. **Git Bash `cmd /c` quoting is a trap twice over.** You need `MSYS_NO_PATHCONV=1` or `/c` gets path-converted; and cmd parses its own command line, so `\"` escaping arrives literally (`'\"C:\...\vcvarsall.bat\"' is not recognized`). Write `.bat` files and call them by path.
3. **Bundled bzip2 cannot build under Ninja** — `${MAKE}` is empty outside Makefile generators (`ThirdpartyToolchain.cmake:3118-3125`). Upstream bug; upstream's Windows CI sets `ARROW_WITH_BZ2=OFF` (`cpp_build.sh:250`, `cpp_windows.yml:65`). Full story: §5.
4. **scikit-build-core 1.x renamed its import package** to `scikit_build_core` (was `skbuild_core` in 0.x). Two import probes failed before `pip show -f` revealed it. If you probe build deps by import name, use the new one.
5. **cmake 4.x vs old bundled-dep minimums.** Several bundled third-party deps carry `cmake_minimum_required < 3.5`, which cmake 4.3.1 rejects. `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` is mandatory.
6. **`ARROW_PYTHON` is deprecated in 25.0.0 — and that's fine.** The non-fatal `ARROW_PYTHON is deprecated. Use CMake presets instead.` warning appears because Arrow no longer ships a separate `arrow_python` C++ library from `cpp/`; pyarrow's own `python/` CMakeLists builds the bridge in-tree (verified on the wheel-stage link lines). Do not go looking for `arrow_python.dll` or an ArrowPython cmake package — neither exists by design.
7. **`-march=armv8-a` is ignored by MSVC.** pyarrow's build passes GCC-style arch flags on win_arm64; MSVC warns `D9002: ignoring unknown option` and moves on. Harmless — the MSVC ARM64 baseline is armv8.0 already — but it means upstream's pyproject hardcodes GNU arch flags on the win_arm64 path.
8. **The `ls-remote | tail` trap.** Verifying the release tag with `git ls-remote --tags ... | tail -5` *missed* `apache-arrow-25.0.0`: alphabetical sort puts the bare tag before `-rc0`/`-rc1`/`.dev` suffixed tags. Grep for the exact tag (and its `^{}` peel) instead.

---

## 9. Reproduce this build

Everything above was produced by the four `.bat` scripts and two smoke scripts in this repo, plus the logged commands inline. On your own ARM64 box:

1. **Toolchain:** VS 2022 Build Tools with the *MSVC C++ ARM64* component, cmake 4.x, the winarm64 ninja binary from the official ninja-build releases, git, and an ARM64 CPython 3.11 venv. Verify the compiler is the native one: after `vcvarsall.bat arm64`, `where cl.exe` must report a `HostARM64\arm64\cl.exe` path.
2. **Source:** `git clone --depth 1 --branch apache-arrow-25.0.0 --single-branch https://github.com/apache/arrow.git arrow-25.0.0` and confirm `git log --oneline -1` reports `59bea6e`. Grep the tag exactly (§8, gotcha 8).
3. **Build deps in the venv** (versions used here, from Arrow's `python/requirements-build.txt` + delvewheel): cython 3.2.8, libcst 1.8.6, scikit_build_core 1.0.3, setuptools_scm 10.2.0, build 1.5.1, delvewheel 1.13.0, numpy 2.4.6.
4. **Edit paths.** All four `.bat` scripts hardcode the build machine's paths (venv, source tree, `arrow-build`, `arrow-dist`, ninja dir, log dir). Point them at yours before launching. The smoke scripts likewise hardcode their scratch-parquet paths.
5. **C++ stage:** launch `run_cpp_build.bat` (the pattern-B wrapper — never Start-Process with stream redirection, §4):

   ```powershell
   powershell Start-Process cmd.exe -ArgumentList '/c','C:\full\path\to\run_cpp_build.bat' -WindowStyle Hidden
   ```

   Watch `cpp_build.out.log` for `VCVARS_INITIALIZED rc=0`, then `ARROW_CPP_BUILD_OK`. On the build machine the successful attempt took ~8 min with a warm dep cache at `-j8`; a cold cache takes longer (the first, cold attempt was still inside the bundled-dependency stage 6.5 minutes in when it hit the §5 failure).
6. **Wheel stage:** same pattern with `run_pyarrow_wheel.bat`; watch `pyarrow_build.out.log` for `PYARROW_WHEEL_BUILD_OK` (~3 min). The repaired wheel lands in `arrow-25.0.0\python\repaired_wheels\`.
7. **Install and verify** per the Quickstart: `pip install` the repaired wheel, `smoke_pyarrow.py` → `PYARROW_SMOKE_OK`, then `pip install datasets trl` and `smoke_datasets.py` → `DATASETS_SMOKE_OK`.

---

## License

PolyForm Noncommercial 1.0.0 — see `LICENSE`. Required Notice: Copyright 2026 LucRoot (info@lucasroot.com). These scripts automate a build of Apache Arrow's own sources; Apache Arrow itself remains Apache-2.0 (see `arrow-dist/share/doc/arrow/` after the C++ stage).

Initial commit: Windows ARM64 PyArrow field guide + build scripts
