# starling-termd — one static binary to scp to a server.
#
# No dependencies beyond libc, libutil (forkpty) and pthreads. The emulator
# core is deliberately NOT linked in: v0 ships the pty byte stream and never
# renders, so the daemon needs no terminal knowledge at all.
#
# Windows is not built here — it has no make. Use build-windows.ps1, which
# compiles the same termd.c against plat_win32.c instead.

CC      ?= cc
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra -Wno-unused-parameter
LDLIBS   = -lutil -lpthread
PREFIX  ?= /usr/local
SRC      = termd.c plat_posix.c
HDRS     = protocol.h plat.h

all: starling-termd

starling-termd: $(SRC) $(HDRS)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDLIBS)

# What you actually copy to a server that has no toolchain.
static: $(SRC) $(HDRS)
	$(CC) $(CFLAGS) -static -o starling-termd $(SRC) $(LDLIBS)

test: starling-termd
	./test-termd.py

install: starling-termd
	install -Dm755 starling-termd $(DESTDIR)$(PREFIX)/bin/starling-termd

clean:
	rm -f starling-termd

.PHONY: all static test install clean
