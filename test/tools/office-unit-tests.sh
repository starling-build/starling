#!/bin/bash
# Build and run OfficeApp's XCTest suite on a glibc 2.43 / libstdc++ 15 box.
# SwiftPM builds _Testing_Foundation and the test runner's Foundation import
# with no access to the package's glibcMathCompat flags, so libstdc++'s
# <math.h> wrapper clashes with glibc's ("redefinition of 'acos'").  A
# stand-in math.h first on CPLUS_INCLUDE_PATH reaches every compile step.
# Usage: test/tools/office-unit-tests.sh [scratch-dir] [swift test args...]
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
scratch=${1:-$root/.build-tests}; shift || true
shim=$scratch/mathshim
mkdir -p "$shim"
printf '#ifndef _GLIBCXX_MATH_H\n#define _GLIBCXX_MATH_H 1\n#endif\n#include "/usr/include/math.h"\n' > "$shim/math.h"
export CPLUS_INCLUDE_PATH=$shim${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}
swift build --build-tests --package-path "$root/apps/OfficeApp" --scratch-path "$scratch"
swift test --skip-build --package-path "$root/apps/OfficeApp" --scratch-path "$scratch" "$@"
