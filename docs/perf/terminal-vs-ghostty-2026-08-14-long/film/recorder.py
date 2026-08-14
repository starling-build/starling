import sys, time, os
from gi.repository import Gio, GLib
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
proxy = Gio.DBusProxy.new_sync(bus, 0, None, 'org.gnome.Shell.Screencast',
    '/org/gnome/Shell/Screencast', 'org.gnome.Shell.Screencast', None)
res = proxy.call_sync('Screencast', GLib.Variant('(sa{sv})', (sys.argv[1],
    {'framerate': GLib.Variant('i', 30), 'draw-cursor': GLib.Variant('b', False)})),
    0, -1, None)
ok, path = res.unpack()
print('recording', ok, path, flush=True)
while not os.path.exists(sys.argv[2]):
    time.sleep(0.5)
print('stopping', proxy.call_sync('StopScreencast', None, 0, -1, None).unpack(), flush=True)
