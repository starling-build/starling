#!/usr/bin/env python3
"""Start-menu open latency from a Desktop-Duplication capture.

t0  = the frame the marker turns white; the keystroke was injected in the same
      instant, after a synchronous paint, so marker and input share a frame.
t1  = the first frame whose menu-region signature departs from the pre-t0
      baseline (first pixels), and the frame after which it stops changing
      (settled).
The rep-to-rep spacing in the video is checked against the wall-clock spacing
the injector recorded, which calibrates out any capture-rate drift.
"""
import sys, statistics

FPS = 30.0

def load(prefix):
    mk = open(prefix + ".marker.raw", "rb").read()
    mn = open(prefix + ".region.raw", "rb").read()
    n = len(mk)
    assert len(mn) == n * 256, "signal length mismatch"
    return mk, [mn[i*256:(i+1)*256] for i in range(n)], n

def mad(a, b):
    return sum(abs(a[j] - b[j]) for j in range(256)) / 256.0

def analyze(prefix, stamps_file, label, thresh=8.0, settle_eps=0.5):
    mk, sig, n = load(prefix)
    edges = [i for i in range(1, n) if mk[i] > 128 and mk[i-1] <= 128]

    # calibration: video spacing vs wall spacing
    scale = 1.0
    wall = []
    try:
        for line in open(stamps_file):
            p = line.split()
            if len(p) >= 4 and p[0] == "rep":
                wall.append(float(p[3]))
    except OSError:
        pass
    if len(wall) >= 2 and len(edges) >= 2:
        vid_span = (edges[-1] - edges[0]) / FPS * 1000.0
        wall_span = wall[-1] - wall[0]
        scale = wall_span / vid_span

    rows = []
    for k, e in enumerate(edges):
        base = sig[max(0, e - 4)]
        first = settled = None
        for i in range(e, min(n, e + 90)):
            if mad(sig[i], base) > thresh:
                first = i
                break
        if first is not None:
            for i in range(first, min(n, first + 90) - 3):
                if all(mad(sig[i+d+1], sig[i+d]) < settle_eps for d in range(3)):
                    settled = i
                    break
        if first is not None:
            rows.append((k + 1, e, first, settled,
                         (first - e) / FPS * 1000.0 * scale,
                         None if settled is None else (settled - e) / FPS * 1000.0 * scale))
    print("=== %s ===" % label)
    print("  frames %d, reps detected %d, calibration scale %.5f (1.0 = video time == wall time)"
          % (n, len(rows), scale))
    print("  %-4s %-8s %-8s %-10s %-12s" % ("rep", "t0", "first", "settled", "first(ms)"))
    for r in rows:
        print("  %-4d %-8d %-8d %-10s %-12.1f %s"
              % (r[0], r[1], r[2], str(r[3]), r[4],
                 "" if r[5] is None else "settled %.1f ms" % r[5]))
    f = [r[4] for r in rows]
    s = [r[5] for r in rows if r[5] is not None]
    if f:
        print("  FIRST PIXELS  median %.1f ms   min %.1f   max %.1f   (n=%d)"
              % (statistics.median(f), min(f), max(f), len(f)))
    if s:
        print("  SETTLED       median %.1f ms   min %.1f   max %.1f" % (statistics.median(s), min(s), max(s)))
    print("  frame quantum at %.0f fps: %.1f ms" % (FPS, 1000.0 / FPS))
    return f, s

if __name__ == "__main__":
    analyze(sys.argv[1], sys.argv[2], sys.argv[3])
