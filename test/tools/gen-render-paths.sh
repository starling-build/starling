#!/bin/bash
# Prints the local packages OfficeApp depends on (paths relative to the repo), to check test/tools/render-paths.txt against.
cd "$(dirname "$0")/../.." || exit 2
. ~/bin/office-env.sh >/dev/null 2>&1
( cd apps/OfficeApp && swift package show-dependencies --format json ) | python3 -c "
import sys,json,os
t=sys.stdin.read(); j=json.loads(t[t.index('{'):]); root=os.getcwd()
def w(n):
  print(os.path.relpath(n['path'], os.path.dirname(os.path.dirname(root))) if False else n['path']); [w(c) for c in n['dependencies']]
w(j)"
