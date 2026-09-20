# Starling 0.5.0 — a desktop you can walk into

Starling keeps the familiar 2D desktop and adds a walkable 3D waterfront city.
Open the control panel and choose **3D Desktop** to change perspectives. The
city includes moving boats, traffic and clouds, a clock tower, sunset lighting,
and cream, bronze and sage window chrome.

## Your apps, in the city

Chrome, Video Player, Files, Terminal and the other desktop apps remain real
windows. Switch between them with **Alt + Tab**, or bring a live preview forward
from the rail. Double-click a window's outer title bar to center the view on it.
Popups follow their parent window in the scene.

Each display has its own scene and camera. Walking, turning or pointer-driven
parallax on one display leaves the other display's view unchanged. Scene
rendering shares a backend while keeping each output's camera and render target
independent.

## Remote desktops

The city also runs in WSL through RDP display mode. When the RDP viewer leaves,
ambient animation stops; connecting again resumes it. The release gate checks
idle CPU before and after a connection, visible city motion, and motion after
reconnecting.

## Website and demo

The website is now a single desktop showcase, styled with the city's palette.
It includes real 2D/3D captures, a narrated demo with original music and captions,
and Ubuntu installation instructions. The film walks from an empty desktop to
the waterfront, then launches and switches between Chrome, Video Player, Files
and Terminal.

## Install

The package targets **Ubuntu 26.04 LTS, amd64**. Download
`starling_0.5.0_amd64.deb` from the release assets, open a terminal in its folder,
and run:

```sh
sudo apt install ./starling_0.5.0_amd64.deb
```

Log out, select **Starling** from the login screen's session menu, and sign in.
See the [installation guide](../../INSTALL.md) for requirements, WSL setup,
upgrades and troubleshooting.

## Release branches and validation

Use **`release-0.5.0` in both the desktop and engine repositories** for the
matching sources. The package version is `0.5.0`.

Gate results and the tested package checksum are recorded in [GATES.md](GATES.md).
