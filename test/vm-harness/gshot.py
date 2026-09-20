#!/usr/bin/env python3
# Native Starling capture (same protocol as build/shell-drive.py `shot`):
# SIGUSR1 asks the engine for a screenshot; SIGRTMIN+2 forces a presented frame
# so the request is consumed. Engine writes /tmp/drm_screenshot_*.ppm. Runs as
# the session user (the shell is its own process). Leaves the PPM at ~/starling-shot.ppm.
import glob, os, signal, subprocess, sys, time
before = {p: os.stat(p).st_mtime_ns for p in glob.glob("/tmp/drm_screenshot_*.ppm")}
pid = int(subprocess.check_output(["pgrep", "-x", "DesktopShellApp"]).split()[0])
os.kill(pid, signal.SIGUSR1)
deadline = time.time() + 8
new = None
while time.time() < deadline and not new:
    try:
        os.kill(pid, signal.SIGRTMIN + 2)
    except Exception:
        pass
    time.sleep(0.25)
    # A restarted shell reuses screenshot_0: detect replacement as well as a new name.
    new = next((p for p in glob.glob("/tmp/drm_screenshot_*.ppm")
                if os.stat(p).st_mtime_ns != before.get(p)), None)
if not new:
    sys.exit("screenshot never appeared")
time.sleep(0.5)  # let the ~33MB write finish
dst = os.path.expanduser("~/starling-shot.ppm")
subprocess.run(["cp", new, dst], check=True)
try:
    os.remove(new)
except Exception:
    pass
print("wrote", dst, os.path.getsize(dst), "bytes")
