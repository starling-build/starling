#!/usr/bin/env python3
"""Hand-rolled width probe: print text, ask the terminal where the cursor is
(CPR, ESC[6n), compare with python wcwidth. No ucs-detect code involved."""
import sys, os, termios, tty, select, re, json
from wcwidth import wcswidth

CASES = [
    # ghostty's narrow failures (expected 1 per wcwidth 17.0)
    ("2E3A two-em dash", "⸺"), ("2E3B three-em dash", "⸻"),
    ("16D63 Kirat Rai", "\U00016d63"), ("16D67 Kirat Rai", "\U00016d67"),
    ("16D68 Kirat Rai", "\U00016d68"), ("16D69 Kirat Rai", "\U00016d69"),
    ("16D6A Kirat Rai", "\U00016d6a"),
    # ghostty's wide failure (expected 2)
    ("115F hangul filler", "ᅟ"),
    # ghostty's Javanese pangkon conjuncts (expected 1)
    ("jav A98F+A9C0", "ꦏ꧀"), ("jav A9A0+A9C0", "ꦠ꧀"),
    ("jav A9A5+A9B3+A9C0", "ꦥ꦳꧀"), ("jav A9B1+A9C0", "ꦱ꧀"),
    # ghostty's Grantha virama conjuncts (expected 1)
    ("gra 11315+1134D", "\U00011315\U0001134d"), ("gra 11327+1134D", "\U00011327\U0001134d"),
    ("gra 11338+1134D", "\U00011338\U0001134d"),
    # classics
    ("231A watch", "⌚"), ("CJK ni", "你"), ("hangul syllable", "한"),
    ("e+combining acute", "é"), ("devanagari ksa", "क्ष"),
    ("thai cluster", "กิ"), ("ZWJ family", "\U0001F468‍\U0001F469‍\U0001F467‍\U0001F466"),
    ("flag US", "\U0001F1FA\U0001F1F8"), ("umbrella+VS16", "☂️"),
    ("watch+VS15", "⌚︎"), ("skin tone wave", "\U0001F44B\U0001F3FD"),
    ("mixed abc+CJK", "ab中文c"),
]

def cpr(fd_in, out):
    out.write("\x1b[6n"); out.flush()
    buf = ""
    while True:
        r,_,_ = select.select([fd_in], [], [], 2.0)
        if not r: return None
        buf += os.read(fd_in, 64).decode("latin1")
        m = re.search(r"\x1b\[(\d+);(\d+)R", buf)
        if m: return int(m.group(2))

def main():
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    out = sys.stdout
    results = []
    try:
        for label, text in CASES:
            out.write("\r\x1b[2K"); out.flush()
            base = cpr(fd, out)
            out.write(text)
            col = cpr(fd, out)
            measured = None if (col is None or base is None) else col - base
            expected = wcswidth(text)
            results.append({"label": label, "text": "".join(f"U+{ord(c):04X} " for c in text).strip(),
                            "measured": measured, "wcwidth": expected,
                            "ok": measured == expected})
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    with open(os.environ.get("PROBE_OUT", "/var/tmp/bench/probe-results.json"), "w") as f:
        json.dump(results, f, indent=1)
    bad = [r for r in results if not r["ok"]]
    out.write(f"\r\n{len(results)-len(bad)}/{len(results)} OK, {len(bad)} mismatches\r\n")
main()
