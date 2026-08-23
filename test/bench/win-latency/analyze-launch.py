#!/usr/bin/env python3
"""Launch latency at 64x64: keystroke -> first pixels -> the window is DONE.

"Done" is relative, not an absolute pixel threshold, because the two shells
paint different amounts: it is the first frame within 2% of the total change
the launch produces, with the final state sampled 3.3 s in -- late enough that
Explorer's file list has actually arrived. Identical rule for both.
"""
import sys, statistics
FPS, N = 30.0, 64*64
FIRST_THRESH = 2.0
FINAL_AT = 100          # frames after t0 (3.3 s)
REL = 0.02

def run(prefix, stamps, label):
    mk = open(prefix + ".marker.raw", "rb").read()
    mn = open(prefix + ".region.raw", "rb").read()
    n = len(mk)
    sig = [mn[i*N:(i+1)*N] for i in range(n)]
    edges = [i for i in range(1, n) if mk[i] > 128 and mk[i-1] <= 128]
    mad = lambda a, b: sum(abs(a[j]-b[j]) for j in range(N)) / float(N)
    wall = [float(l.split()[3]) for l in open(stamps) if len(l.split()) > 3 and l.split()[0] == "rep" and l.split()[2] == "qpc_ms"]
    scale = (wall[-1]-wall[0]) / ((edges[-1]-edges[0])/FPS*1000.0) if len(wall) >= 2 else 1.0

    F, S = [], []
    print("=== %s ===" % label)
    print("  %-4s %-9s %-9s %s" % ("rep", "first(ms)", "done(ms)", "total change"))
    for k, e in enumerate(edges):
        if e + FINAL_AT >= n: continue
        base, final = sig[max(0, e-4)], sig[e+FINAL_AT]
        span = mad(base, final)
        first = next((i for i in range(e, e+110) if mad(sig[i], base) > FIRST_THRESH), None)
        done  = next((i for i in range(e, e+110) if mad(sig[i], final) < REL*span), None)
        if first is None or done is None: continue
        fm, sm = (first-e)/FPS*1000*scale, (done-e)/FPS*1000*scale
        F.append(fm); S.append(sm)
        print("  %-4d %-9.0f %-9.0f %.1f" % (k+1, fm, sm, span))
    print("  FIRST PIXELS  median %.0f ms  (min %.0f, max %.0f)" % (statistics.median(F), min(F), max(F)))
    print("  WINDOW DONE   median %.0f ms  (min %.0f, max %.0f)" % (statistics.median(S), min(S), max(S)))
    return F, S

if __name__ == "__main__":
    run(*sys.argv[1:4])
