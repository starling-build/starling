[Starling App]
Id=windows
Name=Windows
Kind=vm
Order=230
Glyph=externalApp
Color=2E6FCC
# No process to launch: the shell opens the guest's display in-process over
# QEMU's p2p D-Bus socket, so there is no Exec recipe and app-run is not
# involved. Bins is the cheapest honest "libvirt is here" — whether the domain
# exists is answered by the launch arm, where a notice can be shown.
Domain=windows
Bins=/usr/bin/virsh
Category=Work
Publisher=Microsoft
Subtitle=Windows, in a window
Size=—
Description=A Windows virtual machine on this desktop, in an ordinary window — dock icon, spaces, Mission Control, resize. The guest's own cursor rides the hardware cursor plane and its scanout is imported as a dma-buf, so there is no copy between the VM and the screen. Closing the window detaches; the VM keeps running until you shut it down from the dock menu.
