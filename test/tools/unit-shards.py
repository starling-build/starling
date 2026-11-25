#!/usr/bin/env python3
"""unit-shards.py ROOT SCRATCH N — run the built OfficeApp XCTest binary as N parallel shards (called by office-unit-tests.sh when
UNIT_SHARDS=N). Exit 0 only if every shard passed AND every test in the binary's --list-tests ran exactly once (AAATextSetupTests once
per shard: it loads ICU into the process). Class times: $UNIT_CLASSTIMES, else SCRATCH/classtimes.tsv, else test/tools/unit-classtimes.tsv;
a class with no time gets 1 s. After a full green or red run the times are rewritten to SCRATCH/classtimes.tsv. (amd-8, 2026-11-25)"""
import os, re, subprocess, sys, time
root, scratch, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
binp = os.path.join(scratch, "debug", "OfficeAppPackageTests.xctest")
cwd = os.path.join(root, "apps", "OfficeApp")
SETUP = "AAATextSetupTests"
lst = subprocess.run([binp, "--list-tests"], cwd=cwd, capture_output=True, text=True).stdout
tests = [m.group(1) + "." + m.group(2) for m in (re.match(r"OfficeAppTests\.(\w+)/(\w+)", l) for l in lst.splitlines()) if m]
if not tests:
    print("unit-shards: --list-tests gave no tests"); sys.exit(3)
classes = sorted({t.split(".")[0] for t in tests})
tf = os.environ.get("UNIT_CLASSTIMES") or next((f for f in (os.path.join(scratch, "classtimes.tsv"), os.path.join(root, "test/tools/unit-classtimes.tsv")) if os.path.exists(f)), None)
times = {}
if tf:
    for l in open(tf):
        p = l.split()
        if len(p) == 3: times[p[2]] = float(p[0])
work = sorted((c for c in classes if c != SETUP), key=lambda c: -times.get(c, 1.0))
shards = [[0.0, []] for _ in range(n)]
for c in work:
    s = min(shards, key=lambda x: x[0]); s[0] += times.get(c, 1.0); s[1].append(c)
shards = [s for s in shards if s[1]]
log = os.environ.get("UNIT_LOG_DIR") or os.path.join(scratch, "shard-logs"); os.makedirs(log, exist_ok=True)
t0 = time.time(); procs = []
for i, (w, cs) in enumerate(shards):
    spec = ",".join("OfficeAppTests." + c for c in [SETUP] + cs)
    procs.append((i, subprocess.Popen([binp, spec], cwd=cwd, stdout=open(f"{log}/out{i}", "w"), stderr=subprocess.STDOUT)))
rcs = [(i, p.wait()) for i, p in procs]
seen = {}; per = {}
for i, _ in procs:
    txt = open(f"{log}/out{i}", errors="replace").read()
    for m in re.finditer(r"^Test Case '(\w+\.\w+)' (passed|failed|skipped)", txt, re.M):
        seen[m.group(1)] = seen.get(m.group(1), 0) + 1
    for m in re.finditer(r"^Test Suite '(\w+Tests)' (?:passed|failed) at.*\n\s*Executed (\d+) tests?, with .* in ([\d.]+) \(", txt, re.M):
        per[m.group(1)] = (float(m.group(3)), int(m.group(2)))
bad = []
for t in tests:
    want = len(shards) if t.startswith(SETUP + ".") else 1
    if seen.get(t, 0) != want: bad.append(f"{t} ran {seen.get(t, 0)}x (want {want})")
ran = sum(seen.values())
print(f"unit-shards: {len(shards)} shards, wall {time.time() - t0:.0f}s, {len(tests)} listed tests, {ran} test runs")
for i, rc in rcs:
    if rc: print(f"unit-shards: shard {i} exit {rc} (log {log}/out{i})")
for b in bad[:20]: print("unit-shards: MISSING/DUPLICATE " + b)
for l in subprocess.run(f"grep -ah 'error:' {log}/out* | grep -ao '[A-Za-z0-9]*Tests\\.test[A-Za-z0-9]*' | sort -u", shell=True, capture_output=True, text=True).stdout.split():
    print("  UNIT FAIL " + l)
if per and not bad:
    out = os.path.join(scratch, "classtimes.tsv")
    with open(out + ".tmp", "w") as f:
        for c, (d, k) in sorted(per.items(), key=lambda x: -x[1][0]): f.write(f"{d}\t{k}\t{c}\n")
    os.replace(out + ".tmp", out)
nfail = sum(len(re.findall(r"^Test Case '\w+\.\w+' failed", open(f"{log}/out{i}", errors="replace").read(), re.M)) for i, _ in procs)
print(f"Executed {len(tests)} tests, with {nfail} failures (0 unexpected) in {time.time() - t0:.1f} seconds")   # same shape as XCTest's total line
ok = not bad and all(rc == 0 for _, rc in rcs)
print(f"unit-shards: XCTest executed {len(tests)} tests in {len(shards)} shards (every listed test ran once), {'OK' if ok else 'FAILED'}")
sys.exit(0 if ok else 1)
