import random, subprocess, sys, os
N = int(sys.argv[1]) if len(sys.argv) > 1 else 200
FINALS = "ABCDEFGHJKLMPSTXfdhlmnrsucgtq@`"
fails = 0
for seed in range(N):
    rnd = random.Random(seed)
    out = bytearray()
    for _ in range(rnd.randint(20, 400)):
        k = rnd.random()
        if k < 0.34:                                   # printable ascii run
            out.extend(bytes(rnd.randint(0x20, 0x7e) for _ in range(rnd.randint(1, 40))))
        elif k < 0.50:                                 # a plausible CSI
            params = ";".join(str(rnd.randint(0, 300)) for _ in range(rnd.randint(0, 6)))
            priv = "?" if rnd.random() < 0.25 else ""
            out.extend(b"\x1b[" + (priv + params + rnd.choice(FINALS)).encode())
        elif k < 0.60:                                 # SGR specifically
            n = rnd.choice([[0],[1],[7],[22],[38,5,rnd.randint(0,255)],
                            [48,5,rnd.randint(0,255)],
                            [38,2,rnd.randint(0,255),rnd.randint(0,255),rnd.randint(0,255)],
                            [30+rnd.randint(0,7)],[90+rnd.randint(0,7)],[39],[49]])
            out.extend(b"\x1b[" + ";".join(map(str,n)).encode() + b"m")
        elif k < 0.68:                                 # control chars
            out.append(rnd.choice([0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d]))
        elif k < 0.78:                                 # utf-8 text
            out.extend(rnd.choice(["héllo","日本語","🎉🚀","Привет","αβγ","✓✗→"]).encode())
        elif k < 0.86:                                 # raw escape soup
            out.extend(b"\x1b" + bytes([rnd.randint(0x20,0x7e)]))
        elif k < 0.93:                                 # random bytes (invalid utf8 too)
            out.extend(bytes(rnd.randint(0,255) for _ in range(rnd.randint(1,12))))
        else:                                          # OSC
            out.extend(b"\x1b]" + bytes(rnd.randint(0x20,0x7e) for _ in range(rnd.randint(0,20)))
                       + rnd.choice([b"\x07", b"\x1b\\", b"\x1bZ"]))
    p = "/var/tmp/bench/fuzz.bin"
    open(p,"wb").write(bytes(out))
    cols = rnd.choice([3,5,10,17,40,80,132,201,244])
    rows = rnd.choice([2,3,5,12,24,47,56])
    chunk = rnd.choice([1,2,5,17,999,65536])
    a = subprocess.run(["./diff_c",p,str(cols),str(rows),str(chunk)],capture_output=True,text=True)
    b = subprocess.run(["./dif/diff_swift",p,str(cols),str(rows),str(chunk)],capture_output=True,text=True)
    if a.stdout != b.stdout:
        fails += 1
        print(f"MISMATCH seed={seed} grid={rows}x{cols} chunk={chunk} len={len(out)}")
        print("   C    :", a.stdout.strip() or a.stderr.strip())
        print("   swift:", b.stdout.strip() or b.stderr.strip())
        os.rename(p, f"/var/tmp/bench/fuzzfail-{seed}.bin")
        if fails >= 5: break
print(f"{N-fails}/{N} streams identical" if fails==0 else f"FAILURES: {fails}")
