#!/bin/bash
Z=$HOME/dev/starling/starling-office-zh; Z2=$HOME/dev/starling/starling-office-zh2
cd $Z && git fetch -q && git rebase origin/office 2>&1 | tail -1
FIX=$(git rev-parse --short HEAD); BASE=$(git rev-parse --short origin/office); echo "fix $FIX base $BASE"
E=$Z/engine/src/out/host_release_arm64; export STARLING_ENGINE_OUT=$E FLUTTER_SWIFT_ENGINE_OUT=$E
(cd $Z2 && git checkout -q --detach $BASE) || exit 3
for d in $Z $Z2; do (cd $d && swift build -c release --package-path apps/OfficeApp 2>&1 | grep -E "error:|Build complete" | tail -1); done
cd $Z
export PYTHON=$HOME/starling-word-check/lab/venv/bin/python
bash test/tools/docx-pair.sh $Z2/apps/OfficeApp/.build/release/OfficeApp $Z/apps/OfficeApp/.build/release/OfficeApp 6
echo PAIR14DONE
