#!/usr/bin/env python3
"""build/tools/svg-ico.py IN.svg OUT.ico — a Windows icon from an SVG.

The Windows counterpart of svg-icns.sh. sdk/tools/stage-windows.ps1 -Icon
embeds an .ico in the staged exe; this makes one, with the sizes Windows asks
for at 100% to 300% (16 to 256, each stored as PNG).

    python build/tools/svg-ico.py build/office-gtk/starling-writer.svg build/win/Office.ico

The SVG is drawn by a headless browser (Edge or Chrome, whichever is found)
at four times its size on a clear ground, and Pillow scales that down to each
size. Not PyMuPDF, which is on the box and looks like the obvious tool: it
drops a userSpaceOnUse gradient, so these icons came out on black.
"""
import os, shutil, subprocess, sys, tempfile, time
from PIL import Image

SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def browser():
    names = ["msedge", "chrome", "google-chrome", "chromium", "chromium-browser"]
    fixed = [r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
             r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
             r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
    for n in names:
        found = shutil.which(n)
        if found:
            return found
    for p in fixed:
        if os.path.exists(p):
            return p
    sys.exit("svg-ico: no Edge or Chrome to draw the SVG with")


def draw(src, tmp):
    """The SVG at 4x on a clear ground, as a PNG path."""
    shot = os.path.join(tmp, "icon.png")
    url = "file:///" + src.replace("\\", "/")
    # Its own profile each time: a browser already running would take the
    # request and write nothing. And more than one try: the first launch of
    # a fresh profile sometimes exits before the picture is written.
    for attempt in range(4):
        subprocess.run([browser(), "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--user-data-dir=" + os.path.join(tmp, "profile%d" % attempt),
                        "--force-device-scale-factor=4", "--window-size=256,256",
                        "--default-background-color=00000000", "--screenshot=" + shot, url],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        for _ in range(20):
            if os.path.exists(shot) and os.path.getsize(shot) > 0:
                return shot
            time.sleep(0.25)
    sys.exit("svg-ico: the browser wrote no picture")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    tmp = tempfile.mkdtemp(prefix="svg-ico-")
    try:
        big = Image.open(src if src.lower().endswith(".png") else draw(src, tmp)).convert("RGBA")
        big.load()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if big.getpixel((0, 0))[3] != 0:
        print("svg-ico: note, the corner is not clear: the icon will sit on a box")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    big.save(dst, format="ICO", sizes=[(s, s) for s in SIZES])
    print("==>", dst, os.path.getsize(dst), "bytes,", len(SIZES), "sizes")


if __name__ == "__main__":
    main()
