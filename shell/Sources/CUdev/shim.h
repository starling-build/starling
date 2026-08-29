/* libudev, for Swift.
 *
 * The shell subscribes to the kernel's power_supply uevents instead of
 * re-reading sysfs on a timer: reading an AC adapter's `online` makes the
 * kernel interpret ACPI bytecode, which is why a five-second poll was the
 * most expensive thing an idle desktop still did.
 *
 * The monitor is opened on udev's REBROADCAST group ("udev", not "kernel"),
 * which any user can read. The kernel group needs CAP_NET_ADMIN and would
 * therefore work under the dev loop's sudo and fail in a real session --
 * exactly the shape of bug the project guide warns about. */
#include <libudev.h>
