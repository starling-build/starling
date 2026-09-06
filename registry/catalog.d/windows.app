[Starling App]
Id=windows
Name=Windows
Kind=vm
Order=230
Glyph=externalApp
Color=2E6FCC
# The store's Install button provisions the VM end to end — download the
# official ISO, run an unattended install, define the seamless-capable domain.
# See build/app-install.sh (windows recipe) and docs/plans/windows-store-install.md.
Install=windows
# "Installed" means the VM is provisioned AND has booted once (its guest agent
# answered) — not merely "libvirt is here". The recipe writes this marker only
# then, so the store tile and the launcher agree. It is chmod 0755 so both the
# store's file-exists check and the launcher's executable-file probe see it.
Bins=/var/lib/starling/vm/windows.installed
# No process to launch: the shell opens the guest's display in-process over
# QEMU's p2p D-Bus socket, so there is no Exec recipe and app-run is not
# involved.
Domain=windows
Category=Work
Publisher=Microsoft
Subtitle=Windows, in a window
Size=~6 GB download
Description=A Windows 11 virtual machine on this desktop, in an ordinary window — dock icon, spaces, Mission Control, resize. Install downloads ~6 GB from Microsoft and runs an unattended setup (20–40 minutes, no input needed). You need your own Windows license to activate it. The guest's cursor rides the hardware cursor plane and its scanout is imported as a dma-buf, so there is no copy between the VM and the screen. Closing the window detaches; the VM keeps running until you shut it down from the dock menu.
