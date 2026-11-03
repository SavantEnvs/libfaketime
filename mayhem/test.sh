#!/usr/bin/env bash
#
# mayhem/test.sh — functional oracle: runs a probe program under the normally-built
# src/libfaketime.so.1 and asserts the exact faked clock values for known FAKETIME inputs.
# Everything is pre-built by mayhem/build.sh; this script never compiles.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

LIB="$SRC/src/libfaketime.so.1"
PROBE=/mayhem/oracle_probe
for f in "$LIB" "$PROBE"; do
  [ -e "$f" ] || { echo "missing $f (mayhem/build.sh should have produced it)" >&2; emit_ctrf libfaketime-oracle 0 1; exit 1; }
done

export TZ=UTC
export FAKETIME_DISABLE_SHM=1
unset FAKETIME FAKETIME_FMT FAKETIME_TIMESTAMP_FILE FAKETIME_LOAD_FILE FAKETIME_NO_CACHE
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

passed=0
failed=0
# check <name> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then passed=$((passed + 1)); echo "PASS $1"
  else failed=$((failed + 1)); echo "FAIL $1: expected [$2] got [$3]"; fi
}
probe() { LD_PRELOAD="$LIB" "$PROBE" "$@" 2>&1; }

# absolute timestamp, all three clock APIs agree
out=$(FAKETIME="2003-01-01 10:00:05" probe 1)
check absolute "time=1041415205 clock=1041415205.000000000 tv=1041415205.000000" "$out"

# fractional seconds
out=$(FAKETIME="2000-01-01 00:00:00.5" probe 1)
check fractional "time=946684800 clock=946684800.500000000 tv=946684800.500000" "$out"

# start-at: clock begins at the given date and then runs on (seconds part is fixed in the first call)
out=$(FAKETIME="@2000-01-01 00:00:00" probe 1 | sed 's/ clock=.*//')
check start_at "time=946684800" "$out"

# relative offset: +1d is within a few seconds of real time + 86400
real=$(date +%s)
t=$(FAKETIME="+1d" probe 1 | sed -n 's/^time=\([0-9]*\) .*/\1/p')
if [ -n "$t" ] && [ $((t - real - 86400)) -ge -5 ] && [ $((t - real - 86400)) -le 30 ]; then
  passed=$((passed + 1)); echo "PASS offset_plus_1d"
else failed=$((failed + 1)); echo "FAIL offset_plus_1d: real=$real got=[$t]"; fi

# FAKETIME_FMT custom parse format
out=$(FAKETIME_FMT="%d/%m/%Y" FAKETIME="25/12/2010" probe 1)
check custom_format "time=1293235200 clock=1293235200.000000000 tv=1293235200.000000" "$out"

# FAKETIME_TIMESTAMP_FILE: first non-comment line is the spec
printf '# a comment\n2001-02-03 04:05:06\n' > "$TMP/faketimerc"
out=$(FAKETIME_TIMESTAMP_FILE="$TMP/faketimerc" probe 1)
check timestamp_file "time=981173106 clock=981173106.000000000 tv=981173106.000000" "$out"

# invalid specs are rejected with a message and a non-zero exit
out=$(FAKETIME="bogus" probe 1); rc=$?
check invalid_spec_rc 1 "$rc"
case "$out" in *"failed to parse FAKETIME timestamp"*) r=ok;; *) r="$out";; esac
check invalid_spec_msg ok "$r"
out=$(FAKETIME="x0" probe 1); rc=$?
check invalid_rate_rc 1 "$rc"
case "$out" in *"invalid clock rate"*) r=ok;; *) r="$out";; esac
check invalid_rate_msg ok "$r"

# the unfaked probe really reports the current time (guards against a no-op preload)
real=$(date +%s)
t=$("$PROBE" 1 | sed -n 's/^time=\([0-9]*\) .*/\1/p')
if [ -n "$t" ] && [ $((t - real)) -ge -5 ] && [ $((t - real)) -le 5 ]; then
  passed=$((passed + 1)); echo "PASS unfaked_real_time"
else failed=$((failed + 1)); echo "FAIL unfaked_real_time: real=$real got=[$t]"; fi

emit_ctrf libfaketime-oracle "$passed" "$failed"
