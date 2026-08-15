// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The remote-terminal wire format (docs/plans/remote-terminal.md).
//
// Frames are length-prefixed and little-endian. The payload of a DATA frame
// is the pty byte stream verbatim — the server never re-encodes a screen,
// which is the whole point of the design, so this file describes framing
// and almost nothing else.

#ifndef STARLING_TERMD_PROTOCOL_H
#define STARLING_TERMD_PROTOCOL_H

#include <stdint.h>

// 2 added session names: LIST_REPLY entries are variable-length now, and
// OPEN carries a name before its command, so a v1 client cannot read a v2
// reply. Both ends ship together; the version is here to make a mismatch a
// clean refusal rather than a misparse.
#define TERMD_PROTOCOL_VERSION 2

// struct frame { u8 type; u8 flags; u16 pad; u32 len; u8 payload[len]; }
#define TERMD_HEADER_LEN 8
// A DATA payload never exceeds this, so a client can size one buffer.
#define TERMD_MAX_PAYLOAD (1u << 20)

// A session name, NUL excluded. Names are how humans address a session —
// "iOS dev" rather than 12 — and the daemon treats them as opaque bytes
// apart from dropping control characters and trimming edge whitespace.
#define TERMD_MAX_NAME 64

enum termd_type {
    TERMD_HELLO = 1,       // → version u16, name
    TERMD_HELLO_OK = 2,    // ← version u16, session count u16
    TERMD_LIST = 3,        // →
    TERMD_LIST_REPLY = 4,  // ← count u16, then count × { id u32, cols u16,
                           //   rows u16, alive u8, seq u64, name_len u16,
                           //   name[name_len] } — entries are variable-length
    TERMD_OPEN = 5,        // → cols u16, rows u16, name_len u16, name[name_len],
                           //   command (rest, may be empty). A named OPEN is
                           //   idempotent: if a session already has that name
                           //   the daemon attaches to it — from the oldest byte
                           //   it still holds — instead of forking a second
                           //   shell, and answers ATTACHED either way. That is
                           //   what makes a name a durable handle: a client
                           //   that lost its id reconnects with the name alone.
    TERMD_ATTACH = 6,      // → id u32, from_seq u64, cols u16, rows u16
    TERMD_ATTACHED = 7,    // ← id u32, from_seq u64 (what will actually be sent)
    TERMD_DATA = 8,        // ← seq u64, bytes
    TERMD_INPUT = 9,       // → bytes
    TERMD_RESIZE = 10,     // → cols u16, rows u16
    TERMD_ACK = 11,        // → seq u64 consumed through
    TERMD_EXIT = 12,       // ← id u32, status i32
    TERMD_DETACH = 13,     // →
    TERMD_ERROR = 14,      // ← code u16, message
    TERMD_PING = 15,       // ↔ (either side; the other answers PONG)
    TERMD_PONG = 16,       // ↔
};

enum termd_error {
    TERMD_ERR_NO_SESSION = 1,
    TERMD_ERR_BAD_FRAME = 2,
    TERMD_ERR_VERSION = 3,
    TERMD_ERR_OPEN_FAILED = 4,
};

#endif  // STARLING_TERMD_PROTOCOL_H
