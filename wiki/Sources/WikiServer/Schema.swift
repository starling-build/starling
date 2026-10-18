// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The database, as the ordered list of migrations that make it. Each runs
// once; `schema_migrations` remembers which. Append, never edit.

enum Schema {
    static let migrations: [String] = [
        // 1: the W1 tables (docs/plans/wiki.md).
        """
        CREATE TABLE users (
            id          UUID PRIMARY KEY,
            login       TEXT NOT NULL UNIQUE,
            name        TEXT NOT NULL,
            password    TEXT,                 -- salt$rounds$hash, NULL for SSO-only
            is_admin    BOOLEAN NOT NULL DEFAULT FALSE,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE TABLE sessions (
            token       TEXT PRIMARY KEY,
            user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            expires_at  TIMESTAMPTZ NOT NULL
        );
        CREATE TABLE spaces (
            id          UUID PRIMARY KEY,
            key         TEXT NOT NULL UNIQUE,
            name        TEXT NOT NULL,
            home_page   UUID,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE TABLE pages (
            id          UUID PRIMARY KEY,
            space_id    UUID NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
            parent_id   UUID REFERENCES pages(id) ON DELETE SET NULL,
            position    BIGINT NOT NULL DEFAULT 0,
            title       TEXT NOT NULL,
            slug        TEXT NOT NULL,
            tip         BIGINT NOT NULL DEFAULT 0,   -- the current version number
            created_by  UUID REFERENCES users(id),
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ
        );
        CREATE INDEX pages_space_parent ON pages(space_id, parent_id, position);
        CREATE TABLE page_versions (
            page_id     UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            version     BIGINT NOT NULL,
            base        BIGINT,                        -- the version the author edited from
            title       TEXT NOT NULL,
            body        TEXT NOT NULL,                 -- RichDocumentEnvelope JSON, opaque here
            plain_text  TEXT NOT NULL DEFAULT '',      -- for search and the shell's description
            links       TEXT NOT NULL DEFAULT '[]',    -- JSON: page ids this version links to
            author_id   UUID REFERENCES users(id),
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (page_id, version)
        );
        CREATE TABLE page_locks (
            page_id     UUID PRIMARY KEY REFERENCES pages(id) ON DELETE CASCADE,
            user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            token       TEXT NOT NULL,
            expires_at  TIMESTAMPTZ NOT NULL
        );
        CREATE TABLE page_ops (
            page_id     UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            version     BIGINT NOT NULL,               -- the version these ops produced
            seq         BIGINT NOT NULL,
            op          TEXT NOT NULL,                 -- PageOp JSON
            author_id   UUID REFERENCES users(id),
            PRIMARY KEY (page_id, version, seq)
        );
        CREATE TABLE attachments (
            id           UUID PRIMARY KEY,
            page_id      UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            name         TEXT NOT NULL,
            content_type TEXT NOT NULL,
            size         BIGINT NOT NULL,
            sha256       TEXT NOT NULL,                -- the blob's name on disk
            author_id    UUID REFERENCES users(id),
            created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE TABLE audit (
            id          BIGSERIAL PRIMARY KEY,
            at          TIMESTAMPTZ NOT NULL DEFAULT now(),
            user_id     UUID,
            action      TEXT NOT NULL,
            subject     TEXT NOT NULL,
            detail      TEXT NOT NULL DEFAULT '{}'
        );
        """,
        // 2: search over the tip version's title and text. `simple` makes no
        // language assumptions (a Chinese tokeniser such as pg_jieba can
        // replace it later); the trigram-free ILIKE fallback in the query
        // covers scripts the tokeniser leaves whole.
        """
        CREATE INDEX page_versions_fts ON page_versions USING GIN (to_tsvector('simple', title || ' ' || plain_text));
        """,
    ]
}
