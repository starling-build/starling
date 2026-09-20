"""Live two-display navigation regression. Run with sudo against the desktop.

Uses real input, checks the broker's per-output cameras, and reverses each turn.
"""
import importlib.util
import json
from pathlib import Path
import socket
import time

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("drive", root / "build/shell-drive.py")
drive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drive)


def query():
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(10)
        sock.connect(drive.broker_socket())
        sock.sendall(b'{"id":1,"op":"desktop_3d","query":true}\n')
        with sock.makefile("rb") as stream:
            result = json.loads(stream.readline())
    assert result["ok"] and result["t"] == 1, "Enter the city before testing"
    return result


def views():
    return {o["id"]: o for o in query()["outputs"]}


initial = query()
assert len(initial["outputs"]) >= 2, "Connect at least two displays"
assert len({o["texture"] for o in initial["outputs"]}) == len(initial["outputs"])
assert all(o["texture"] >= 0 for o in initial["outputs"])
mouse, keyboard = drive.RelMouse(), drive.Keyboard()
try:
    for output in initial["outputs"]:
        left, top, width, height = output["rect"]
        target = (left + width / 2, top + height / 2)
        def move_to(target):
            for _ in range(30):
                x, y = query()["pointer"]
                dx, dy = target[0] - x, target[1] - y
                if abs(dx) < 25 and abs(dy) < 25:
                    break
                mouse.rel(round(dx * 0.8), round(dy * 0.8))
                time.sleep(0.15)
            else:
                raise AssertionError(f"Pointer did not reach output {output['id']}")
            time.sleep(1)
        move_to(target)
        active = output["id"]
        before_pointer = views()
        move_to((target[0] + width * 0.2, target[1]))
        after_pointer = views()
        assert before_pointer[active]["eye"] != after_pointer[active]["eye"], "Active display did not lean"
        for other in before_pointer:
            assert before_pointer[other]["camera"] == after_pointer[other]["camera"]
            if other != active:
                assert before_pointer[other]["eye"] == after_pointer[other]["eye"], "Pointer moved another display's view"
        before = views()
        keyboard.combo("alt+q")
        time.sleep(0.5)
        after = views()
        active = output["id"]
        try:
            assert after[active]["camera"] != before[active]["camera"], f"Camera {active} did not move"
            for other in before:
                if other != active:
                    assert after[other]["camera"] == before[other]["camera"], f"Camera {other} moved with {active}"
                    assert after[other]["eye"] == before[other]["eye"], f"Parallax on {other} changed with {active}"
        finally:
            keyboard.combo("alt+e")
            time.sleep(0.3)
        print(f"output {active}: navigation independent", flush=True)
finally:
    mouse.close()
    keyboard.close()
print("independent display navigation passed")
