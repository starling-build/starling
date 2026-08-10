# A fake app, used only by test/functional.py. It is overlaid onto a COPY of
# the real catalog at test time (test/functional.sh) and never ships.
#
# It exists so PRIME render offload can be tested on any machine with a
# discrete GPU, rather than only one with Blender installed — Blender is the
# single shipped record carrying Gpu=discrete, and requiring it would make the
# offload path untestable almost everywhere.
#
# So this borrows Chrome's launch recipe and binary and adds the one key under
# test. That is the whole point: the record is IDENTICAL to chrome.app except
# for `Gpu=discrete`, which makes the pair a controlled experiment — launch
# both, and the only thing that can explain a difference in the child's
# environment is the key itself. `starlingnotgimp.app` shares GIMP's binary for
# the same reason.
[Starling App]
Id=starlingprime
Name=Starling Prime Test
Kind=host
Order=9001
Glyph=externalApp
Color=808080
Exec=chrome
Bins=/opt/google/chrome/chrome
Gpu=discrete
Category=System
Publisher=Starling
Subtitle=Not a real app
Description=A placeholder used by the functional test suite to exercise per-app GPU offload.
