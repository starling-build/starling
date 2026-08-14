#!/usr/bin/env python3
"""Switch GNOME to the Dell alone at scale 1 (or restore both, with 'restore').

The bench needs 201 columns at cell 8px = 1608 logical px, which no scale-2
panel here has; the atlas round set the same rig.
"""
import sys
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
state = bus.call_sync('org.gnome.Mutter.DisplayConfig',
                      '/org/gnome/Mutter/DisplayConfig',
                      'org.gnome.Mutter.DisplayConfig', 'GetCurrentState',
                      None, None, Gio.DBusCallFlags.NONE, 30000, None)
serial, monitors, logical, props = state.unpack()

mons = {}
for (connector, vendor, product, mon_serial), modes, mprops in monitors:
    cur = next((m[0] for m in modes if m[6].get('is-current', False)), None)
    pref = next((m[0] for m in modes if m[6].get('is-preferred', False)), None)
    mons[connector] = {'current': cur, 'preferred': pref,
                      'modes': [m[0] for m in modes]}
print('monitors:', {k: v['current'] for k, v in mons.items()})

dell = next((c for c in mons if c.startswith(('HDMI', 'DP'))), None)
edp = next((c for c in mons if c.startswith('eDP')), None)
if not dell:
    sys.exit('no external monitor')

if len(sys.argv) > 1 and sys.argv[1] == 'restore':
    logical_out = [
        (0, 0, 2.0, 0, True, [(edp, mons[edp]['preferred'], {})]),
        (1280, 0, 1.0, 0, False, [(dell, mons[dell]['preferred'], {})]),
    ]
else:
    logical_out = [(0, 0, 1.0, 0, True,
                    [(dell, mons[dell]['preferred'], {})])]

bus.call_sync('org.gnome.Mutter.DisplayConfig',
              '/org/gnome/Mutter/DisplayConfig',
              'org.gnome.Mutter.DisplayConfig', 'ApplyMonitorsConfig',
              GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})',
                           (serial, 1, logical_out, {})),
              None, Gio.DBusCallFlags.NONE, 30000, None)
print('applied')
