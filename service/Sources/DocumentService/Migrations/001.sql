CREATE TABLE IF NOT EXISTS users (
 id uuid PRIMARY KEY, issuer text NOT NULL, subject text NOT NULL, email text, name text NOT NULL,
 UNIQUE(issuer, subject)
);
-- statement
CREATE TABLE workspaces (
 id uuid PRIMARY KEY, name text NOT NULL, kind text NOT NULL CHECK(kind IN ('personal','team')),
 personal_owner uuid UNIQUE REFERENCES users(id), quota_bytes bigint NOT NULL DEFAULT 1073741824,
 used_bytes bigint NOT NULL DEFAULT 0 CHECK(used_bytes >= 0), reserved_bytes bigint NOT NULL DEFAULT 0 CHECK(reserved_bytes >= 0),
 CHECK(used_bytes + reserved_bytes <= quota_bytes)
);
-- statement
CREATE TABLE memberships (
 workspace_id uuid NOT NULL REFERENCES workspaces(id), user_id uuid NOT NULL REFERENCES users(id),
 role text NOT NULL CHECK(role IN ('owner','admin','member')), PRIMARY KEY(workspace_id,user_id)
);
-- statement
CREATE TABLE folders (
 id uuid PRIMARY KEY, workspace_id uuid NOT NULL REFERENCES workspaces(id), name text NOT NULL,
 UNIQUE(workspace_id,id)
);
-- statement
CREATE TABLE documents (
 id uuid PRIMARY KEY, workspace_id uuid NOT NULL REFERENCES workspaces(id), owner_id uuid NOT NULL REFERENCES users(id),
 name text NOT NULL, kind text NOT NULL CHECK(kind IN ('docx','pptx','xlsx')), current_revision_id uuid, folder_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz,
 FOREIGN KEY(workspace_id,folder_id) REFERENCES folders(workspace_id,id)
);
-- statement
CREATE TABLE document_grants (
 document_id uuid NOT NULL REFERENCES documents(id), user_id uuid NOT NULL REFERENCES users(id),
 permission text NOT NULL CHECK(permission IN ('viewer','editor')), PRIMARY KEY(document_id,user_id)
);
-- statement
CREATE TABLE revisions (
 id uuid PRIMARY KEY, document_id uuid NOT NULL REFERENCES documents(id), parent_id uuid REFERENCES revisions(id),
 blob_key uuid NOT NULL, size bigint NOT NULL CHECK(size >= 0), sha256 text NOT NULL,
 author_id uuid NOT NULL REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now()
);
-- statement
ALTER TABLE documents ADD CONSTRAINT current_revision_fk FOREIGN KEY(current_revision_id) REFERENCES revisions(id);
-- statement
CREATE TABLE uploads (
 id uuid PRIMARY KEY, document_id uuid NOT NULL REFERENCES documents(id), creator_id uuid NOT NULL REFERENCES users(id),
 base_revision_id uuid, size bigint NOT NULL CHECK(size > 0 AND size <= 33554432), sha256 text NOT NULL,
 idempotency_key text NOT NULL, state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','uploaded','committed','conflict','expired')),
 revision_id uuid REFERENCES revisions(id), expires_at timestamptz NOT NULL DEFAULT now() + interval '24 hours',
 UNIQUE(document_id,creator_id,idempotency_key)
);
-- statement
CREATE TABLE invitations (
 id uuid PRIMARY KEY, workspace_id uuid NOT NULL REFERENCES workspaces(id), email text NOT NULL,
 role text NOT NULL CHECK(role IN ('admin','member')), token_hash text NOT NULL UNIQUE,
 created_by uuid NOT NULL REFERENCES users(id), expires_at timestamptz NOT NULL, accepted_by uuid REFERENCES users(id), revoked_at timestamptz
);
-- statement
CREATE TABLE share_links (
 id uuid PRIMARY KEY, document_id uuid NOT NULL REFERENCES documents(id), token_hash text NOT NULL UNIQUE,
 created_by uuid NOT NULL REFERENCES users(id), expires_at timestamptz NOT NULL, revoked_at timestamptz
);
-- statement
CREATE TABLE activity (
 id bigserial PRIMARY KEY, workspace_id uuid NOT NULL REFERENCES workspaces(id), document_id uuid REFERENCES documents(id),
 actor_id uuid NOT NULL REFERENCES users(id), event text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
-- statement
CREATE INDEX documents_workspace ON documents(workspace_id);
-- statement
CREATE INDEX revisions_document ON revisions(document_id,created_at);
-- statement
CREATE INDEX uploads_expiry ON uploads(expires_at) WHERE state IN ('pending','uploaded','conflict');
-- statement
CREATE INDEX activity_workspace ON activity(workspace_id,id);
