#!/usr/bin/env bash
#
# mayhem/build.sh — builds (1) the sanitized, AFL-instrumented file-input harnesses and (2) the
# project's normal (unsanitized) libfaketime + test helpers that mayhem/test.sh runs.
# Runs in the commit image as `mayhem` in /mayhem; re-runnable and offline (no fetches).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) Sanitized harnesses. They #include src/libfaketime.c (see mayhem/harness.c), so the fuzzed
#    library code is compiled with $SANITIZER_FLAGS/$DEBUG_FLAGS and AFL edge coverage. The defines
#    are the library's own default feature set (src/Makefile).
FT_DEFS=(-std=gnu99 -DFAKE_PTHREAD -DFAKE_STAT -DFAKE_UTIME -DFAKE_SLEEP -DFAKE_TIMERS
         -DFAKE_INTERNAL_CALLS '-DPREFIX="/usr/local"' '-DLIBDIRNAME="/lib/faketime"')
LSAN_OFF_O=/tmp/libfaketime_lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.c" -o "$LSAN_OFF_O"

build_harness() {  # <binary name> <FT_MODE>
  AFL_LLVM_INSTRUMENT=CLASSIC AFL_MAP_SIZE=65536 \
    afl-clang-fast $SANITIZER_FLAGS $DEBUG_FLAGS "${FT_DEFS[@]}" -DFT_MODE="$2" \
      "$SRC/mayhem/harness.c" "$SRC/src/ft_sem.c" "$LSAN_OFF_O" -ldl -lm -lrt -lpthread -o "/mayhem/$1"
}
build_harness fuzz_faketime_spec 1
build_harness fuzz_faketimerc 2
build_harness fuzz_timestamp_load 3

# 2) The project's own build, with its NORMAL flags (no sanitizer, no -gdwarf-3): this is the
#    functional oracle's subject. Object files and *.so.1 are gitignored and rebuilt here.
# gcc: the Makefile's -Werror is only clean under it (clang trips on tautological-pointer warnings
# in the 64-bit-time variant). CFLAGS/LDFLAGS go in via the environment so the Makefile's `+=` keeps
# its own flags.
export CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS"
make -C src -j"$MAYHEM_JOBS" CC=gcc all
make -C test -j"$MAYHEM_JOBS" CC=gcc timetest
gcc -O1 "$SRC/mayhem/oracle_probe.c" -o /mayhem/oracle_probe
