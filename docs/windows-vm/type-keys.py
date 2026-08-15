#!/usr/bin/env python3
"""Type a string into a libvirt guest's console with virsh send-key.

    type-keys.py <domain> 'Administrator' TAB 'Starling-Rail0!' ENTER

There is no send-text in virsh, so each character becomes a keycode and the
shifted ones become a two-key chord. Written because the alternative --
changing the guest's password to something easy to type -- would have edited
a VM whose RAIL work depends on that password.
"""
import subprocess
import sys
import time

PLAIN = {c: "KEY_" + c.upper() for c in "abcdefghijklmnopqrstuvwxyz"}
PLAIN.update({c: "KEY_" + c for c in "0123456789"})
PLAIN.update({
    "-": "KEY_MINUS", "=": "KEY_EQUAL", "[": "KEY_LEFTBRACE",
    "]": "KEY_RIGHTBRACE", ";": "KEY_SEMICOLON", "'": "KEY_APOSTROPHE",
    "`": "KEY_GRAVE", "\\": "KEY_BACKSLASH", ",": "KEY_COMMA",
    ".": "KEY_DOT", "/": "KEY_SLASH", " ": "KEY_SPACE",
})
SHIFTED = {
    "!": "KEY_1", "@": "KEY_2", "#": "KEY_3", "$": "KEY_4", "%": "KEY_5",
    "^": "KEY_6", "&": "KEY_7", "*": "KEY_8", "(": "KEY_9", ")": "KEY_0",
    "_": "KEY_MINUS", "+": "KEY_EQUAL", "{": "KEY_LEFTBRACE",
    "}": "KEY_RIGHTBRACE", ":": "KEY_SEMICOLON", '"': "KEY_APOSTROPHE",
    "~": "KEY_GRAVE", "|": "KEY_BACKSLASH", "<": "KEY_COMMA",
    ">": "KEY_DOT", "?": "KEY_SLASH",
}
NAMED = {"TAB": ["KEY_TAB"], "ENTER": ["KEY_ENTER"], "ESC": ["KEY_ESC"],
         "DELETE": ["KEY_DELETE"], "CAD": ["KEY_LEFTCTRL", "KEY_LEFTALT", "KEY_DELETE"]}


def send(dom, keys):
    subprocess.run(["sudo", "-n", "virsh", "send-key", dom, "--codeset", "linux"] + keys,
                   check=False, capture_output=True)
    time.sleep(0.06)


def type_str(dom, s):
    for ch in s:
        if ch in PLAIN:
            send(dom, [PLAIN[ch]])
        elif ch.isupper():
            send(dom, ["KEY_LEFTSHIFT", PLAIN[ch.lower()]])
        elif ch in SHIFTED:
            send(dom, ["KEY_LEFTSHIFT", SHIFTED[ch]])
        else:
            print("skip unmappable %r" % ch, file=sys.stderr)


def main():
    dom = sys.argv[1]
    for tok in sys.argv[2:]:
        if tok in NAMED:
            send(dom, NAMED[tok])
        else:
            type_str(dom, tok)


if __name__ == "__main__":
    main()
