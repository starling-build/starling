# starling-termd — one static binary to scp to a server.
#
# No dependencies beyond libc and libutil (forkpty). The emulator core is
# deliberately NOT linked in: v0 ships the pty byte stream and never renders,
# so the daemon needs no terminal knowledge at all.

CC      ?= cc
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra -Wno-unused-parameter
LDLIBS   = -lutil
PREFIX  ?= /usr/local

all: starling-termd

starling-termd: termd.c protocol.h
	$(CC) $(CFLAGS) -o $@ termd.c $(LDLIBS)

# What you actually copy to a server that has no toolchain.
static: termd.c protocol.h
	$(CC) $(CFLAGS) -static -o starling-termd termd.c $(LDLIBS)

test: starling-termd
	./test-termd.sh

install: starling-termd
	install -Dm755 starling-termd $(DESTDIR)$(PREFIX)/bin/starling-termd

clean:
	rm -f starling-termd

.PHONY: all static test install clean
