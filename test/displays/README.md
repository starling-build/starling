`test/run.sh` checks each display's centered lens and agreement between rendered
pixels and pointer rays, including portrait displays and negative origins.

GPU regression (does not need a free display or stop the desktop):

```sh
build/build-room.sh
clang++ -std=c++20 -O2 -o /tmp/starling-independent-scenes \
  test/displays/independent-scenes.cpp -Ishell/Sources/StarlingRoom \
  -L.build-shared -lstarling_room -lGLESv2 -lEGL -lgbm \
  -Wl,-rpath,"$PWD/.build-shared"
timeout 30 /tmp/starling-independent-scenes
```

This creates two scenes of different sizes in the same EGL context, moves their
cameras separately, verifies pixel independence, and destroys one while the other
continues rendering, then recreates scenes after releasing the last one. It caught a teardown hang with separate Filament engines;
the scenes now share only the backend engine.

With two displays connected and the city open, run the real-input check:

```sh
sudo python3 test/displays/navigation-test.py
```

It moves the pointer to each display, turns that camera using Alt+Q, verifies the
other display's camera and parallax are unchanged, and reverses the turn. It also
moves the pointer within each display and checks that only that display leans.

For window chrome, open Chrome on each output in turn, move the camera back with
Alt+S until its outer title bar is visible, and double-click that bar. Check that
the window centers and only its output's camera changes. Repeat with a window on
the other output: both title bars must retain their buttons and text. Title-bar
textures share a cache, so pruning it inside one output's layout would delete
the other output's bar.
