#!/usr/bin/env python3
"""A synthetic multitouch touchpad, for testing two-finger scroll.

libinput only treats a device as a touchpad (and so only emits scroll with
source=finger, which GTK reports as GDK_SOURCE_TOUCHPAD) when it advertises
the MT protocol B axes plus INPUT_PROP_POINTER. A plain REL_WHEEL device
takes the mouse path instead, which is exactly the difference this exists
to exercise.
"""
import fcntl, os, struct, sys, time

UI_SET_EVBIT   = 0x40045564
UI_SET_KEYBIT  = 0x40045565
UI_SET_ABSBIT  = 0x40045567
UI_SET_PROPBIT = 0x4004556E
UI_DEV_CREATE  = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN, EV_KEY, EV_ABS = 0x00, 0x01, 0x03
SYN_REPORT = 0
BTN_TOUCH, BTN_TOOL_FINGER, BTN_TOOL_DOUBLETAP, BTN_LEFT = 0x14a, 0x145, 0x14d, 0x110
ABS_X, ABS_Y = 0x00, 0x01
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2f, 0x35, 0x36, 0x39
INPUT_PROP_POINTER, INPUT_PROP_BUTTONPAD = 0x00, 0x02

W, H = 1200, 800

fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
for ev in (EV_KEY, EV_ABS):
    fcntl.ioctl(fd, UI_SET_EVBIT, ev)
for key in (BTN_TOUCH, BTN_TOOL_FINGER, BTN_TOOL_DOUBLETAP, BTN_LEFT):
    fcntl.ioctl(fd, UI_SET_KEYBIT, key)
for axis in (ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y,
             ABS_MT_TRACKING_ID):
    fcntl.ioctl(fd, UI_SET_ABSBIT, axis)
for prop in (INPUT_PROP_POINTER, INPUT_PROP_BUTTONPAD):
    fcntl.ioctl(fd, UI_SET_PROPBIT, prop)

# struct uinput_user_dev: name[80], id{bustype,vendor,product,version},
# ff_effects_max, absmax[64], absmin[64], absfuzz[64], absflat[64]
absmax = [0] * 64
absmin = [0] * 64
for axis, lo, hi in ((ABS_X, 0, W), (ABS_Y, 0, H),
                     (ABS_MT_POSITION_X, 0, W), (ABS_MT_POSITION_Y, 0, H),
                     (ABS_MT_SLOT, 0, 4), (ABS_MT_TRACKING_ID, 0, 65535)):
    absmin[axis], absmax[axis] = lo, hi
dev = struct.pack("80sHHHHi64i64i64i64i", b"starling-fake-touchpad",
                  0x03, 0x1234, 0x5679, 1, 0,
                  *absmax, *absmin, *([0] * 64), *([0] * 64))
os.write(fd, dev)
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(3.0)          # let udev/libinput/mutter adopt it


def emit(t, c, v):
    os.write(fd, struct.pack("llHHi", 0, 0, t, c, v))


def syn():
    emit(EV_SYN, SYN_REPORT, 0)


def two_finger_scroll(dy_total, steps=40):
    """Both fingers down, dragged dy_total units, then lifted."""
    x0, x1, y = 400, 560, 400
    emit(EV_ABS, ABS_MT_SLOT, 0)
    emit(EV_ABS, ABS_MT_TRACKING_ID, 100)
    emit(EV_ABS, ABS_MT_POSITION_X, x0)
    emit(EV_ABS, ABS_MT_POSITION_Y, y)
    emit(EV_ABS, ABS_MT_SLOT, 1)
    emit(EV_ABS, ABS_MT_TRACKING_ID, 101)
    emit(EV_ABS, ABS_MT_POSITION_X, x1)
    emit(EV_ABS, ABS_MT_POSITION_Y, y)
    emit(EV_KEY, BTN_TOUCH, 1)
    emit(EV_KEY, BTN_TOOL_DOUBLETAP, 1)
    syn()
    time.sleep(0.02)

    step = dy_total / steps
    for i in range(1, steps + 1):
        yy = int(y + step * i)
        emit(EV_ABS, ABS_MT_SLOT, 0)
        emit(EV_ABS, ABS_MT_POSITION_Y, yy)
        emit(EV_ABS, ABS_MT_SLOT, 1)
        emit(EV_ABS, ABS_MT_POSITION_Y, yy)
        syn()
        time.sleep(0.016)

    emit(EV_ABS, ABS_MT_SLOT, 0)
    emit(EV_ABS, ABS_MT_TRACKING_ID, -1)
    emit(EV_ABS, ABS_MT_SLOT, 1)
    emit(EV_ABS, ABS_MT_TRACKING_ID, -1)
    emit(EV_KEY, BTN_TOUCH, 0)
    emit(EV_KEY, BTN_TOOL_DOUBLETAP, 0)
    syn()


dy = int(sys.argv[1]) if len(sys.argv) > 1 else -300
print(f"[fakepad] two-finger scroll dy={dy}", flush=True)
two_finger_scroll(dy)
time.sleep(0.6)
fcntl.ioctl(fd, UI_DEV_DESTROY)
os.close(fd)
