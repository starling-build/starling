#!/bin/bash
# Build and run OfficeApp's XCTest suite on a glibc 2.43 / libstdc++ 15 box.
# SwiftPM builds _Testing_Foundation and the test runner's Foundation import
# with no access to the package's glibcMathCompat flags, so libstdc++'s
# <math.h> wrapper clashes with glibc's ("redefinition of 'acos'").  A
# stand-in math.h first on CPLUS_INCLUDE_PATH reaches every compile step.
# Usage: test/tools/office-unit-tests.sh [scratch-dir] [swift test args...]
# Exits non-zero when the run executed 0 tests, or fewer than MIN_TESTS (default 600) of a full
# run: a test binary that cannot load (a missing shared library) runs nothing and "passes".
# A filtered run (extra swift test args such as --filter) only has to execute at least one test.
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
scratch=${1:-$root/.build-tests}; shift || true
shim=$scratch/mathshim
mkdir -p "$shim"
printf '#ifndef _GLIBCXX_MATH_H\n#define _GLIBCXX_MATH_H 1\n#endif\n#include "/usr/include/math.h"\n' > "$shim/math.h"
export CPLUS_INCLUDE_PATH=$shim${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}
swift build --build-tests --package-path "$root/apps/OfficeApp" --scratch-path "$scratch"
log=$(mktemp)
set +e
swift test --skip-build --package-path "$root/apps/OfficeApp" --scratch-path "$scratch" "$@" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
set -e
# the last "Executed N tests" line is the whole run's total
n=$(grep -aoE "Executed [0-9]+ tests?" "$log" | tail -1 | grep -aoE "[0-9]+" || true)
n=${n:-0}
min=${MIN_TESTS:-600}; [ $# -gt 0 ] && min=1
rm -f "$log"
if [ "$n" -lt "$min" ]; then echo "office-unit-tests: only $n tests ran (need at least $min): the test binary did not run properly" >&2; exit 3; fi
echo "office-unit-tests: XCTest executed $n tests (need at least $min), swift test exit $rc"
exit $rc
