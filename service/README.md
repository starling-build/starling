# Starling document service

A Swift/Hummingbird API shared by Writer, Slides and Sheets. This first backend
milestone provides personal/team workspaces, verified-email invitations,
workspace roles, per-document viewer/editor grants, revocable view links,
folders, private file storage, revision history, trash, audited administrator
recovery, and optimistic concurrency for saves. PostgreSQL owns metadata and
permissions. Disk or S3 storage owns immutable document bytes.

This is a backend API. The Office apps are not connected to it yet. Account
sign-in screens, a document-library UI, invitation email delivery, and deployment
to a public service are subsequent integration work. There is no real-time
collaborative editing in this service.

## Run locally

Requires Swift 6.2+, PostgreSQL 17+, and Python 3 for development helpers. From
this directory:

```sh
swift build
createdb starling_documents
python3 scripts/dev-identities.py
export PGHOST=/tmp PGUSER="$(id -un)" PGDATABASE=starling_documents
export STARLING_DEV_IDENTITIES="$PWD/.dev-identities.json"
export STARLING_STORAGE_PATH="$PWD/data/blobs"
swift run starling-documents
```

The API listens at `http://127.0.0.1:8090`. The identity helper writes two random
bearer tokens for Alice and Bob into a mode-0600 ignored file; it refuses to
replace an existing file. Use one token in `Authorization: Bearer <token>`.
Development identities are opt-in and the executable refuses to bind them to a
non-loopback address. They are for local testing, not production login.

For TCP PostgreSQL, set `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`.
TLS with certificate verification is the default. `PGSSLMODE=disable` is an
explicit local-only choice. A `PGHOST` beginning with `/` selects a Unix socket.
Migrations run transactionally under a database advisory lock before serving.

## Hosted configuration

Use an OIDC provider that issues **RS256 JWT access tokens** with a dedicated
API audience and `iss`, `sub`, `aud`, `exp` claims. Optional `nbf` is checked.
Verified email claims are required to accept invitations. Configure:

- `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` (HTTPS).
- `STARLING_HOST=0.0.0.0`, `PORT=8090`; terminate HTTPS at the ingress.
- `STARLING_ALLOWED_ORIGINS`: explicit comma-separated browser origins, e.g.
  `https://writer.starling.build,https://slides.starling.build,https://sheets.starling.build`.
- PostgreSQL credentials and a verified TLS endpoint.
- Either a durable, private `STARLING_STORAGE_PATH` volume or `S3_BUCKET`.

JWKS keys refresh every five minutes; allow an overlap of old/new keys during
rotation. Tokens with other algorithms, issuers, or audiences are rejected.
The API does not mint sessions or run an OAuth login flow. Native clients should
use their provider's authorization-code flow with PKCE, then send API access
tokens. Browser clients use the same bearer-token API. Missing identity settings
fail startup, rather than creating an anonymous or development service.

`S3_BUCKET` enables Soto's S3 adapter; `AWS_REGION` defaults to `us-east-1`.
Soto's standard credential chain supports environment credentials and workload
roles. `S3_ENDPOINT` selects a compatible provider. The bucket must be private,
and the provider must enforce conditional `PUT If-None-Match: *`. Only the
service account should have access to its `documents/` prefix. The service
proxies uploads/downloads in this milestone (32 MiB per file), which gives both
storage adapters the same permission/revocation behavior. Direct-to-storage
presigned uploads can be added later without changing revision commits.

Build the Docker image from this directory. `Dockerfile` runs as an unprivileged
user. `/health` is liveness; `/ready` checks PostgreSQL. Configure ingress limits
and rate limits, persistent storage backups, and PostgreSQL point-in-time
recovery for a hosted deployment. Keep storage and database backups consistent:
restoring database metadata without its referenced blobs is not a valid restore.
Do not log authorization headers or capability URLs.

## Core flows

All authenticated requests provision an identity keyed by `(issuer, subject)`
and its personal workspace. Identities with the same email are not merged.

1. `GET /v1/me` and `GET /v1/workspaces` locate the current user's resources.
2. `POST /v1/workspaces` with `{"name":"Team"}` creates a team.
3. `POST /v1/workspaces/{id}/invitations` with
   `{"email":"bob@example.test","role":"member"}` returns a one-time-disclosed
   invitation token. Deliver it through a trusted channel. The recipient sends
   `{"token":"..."}` to `POST /v1/invitations/accept`, authenticated with that
   verified email. Invitations expire after seven days and can be revoked.
4. `POST /v1/workspaces/{id}/documents` with
   `{"name":"Plan.docx","kind":"docx"}` creates an empty document record.
   Supported kinds are `docx`, `pptx`, `xlsx`. Clients produce the file bytes.
5. `POST /v1/documents/{id}/uploads` with
   `{"base_revision_id":null,"size":123,"sha256":"<64 hex digits>","idempotency_key":"<unique request id>"}`
   reserves quota and returns an upload ID. Subsequent saves supply the current
   revision ID instead of null. Retry with the same idempotency key and payload.
6. `PUT /v1/uploads/{id}/content` uploads raw bytes; size and SHA-256 must match.
7. `POST /v1/uploads/{id}/commit` returns the committed revision. Show **Saved**
   only after this response. Retrying commit returns the same revision.
8. `POST /v1/documents/{id}/grants` with
   `{"user_id":"...","permission":"viewer"}` or `editor` grants a teammate
   access. `GET /v1/workspaces/{id}/members` supplies recipient IDs.
9. `GET /v1/documents/{id}/content` downloads the current file;
   `/revisions/{revision}/content` downloads a historic one.

### Save conflicts and storage

Concurrent commits are serialized by a workspace lock. Exactly one save from a
base revision becomes current. The other receives **409** with an upload record
whose state is `conflict`; its bytes remain recoverable through
`GET /v1/uploads/{id}/content` by its authorized creator until expiry. The client
must preserve its own local copy too. Uploads expire 24 hours after preparation.
Starting a save from an already stale revision returns 409 before reserving quota.

Objects use server-generated UUID keys and cannot be overwritten. Files are
opaque to the server: it checks integrity and size, not Office-format validity.
Neither previews nor format conversion execute in the API process. Restoring an
old revision creates a new revision referencing its existing immutable blob;
it never rewrites old history. Storage usage counts physical revision blobs,
including historical versions, plus reservations for pending/conflicting uploads.
Each workspace initially has a 1 GiB quota. Backups and operational policy may
retain data beyond the application-level trash lifecycle.

The cleanup worker runs every five minutes. `starling-documents --cleanup` runs
one pass. Expiry and quota release are transactional; failed blob deletion is
retried using retained upload records. Multiple workers can run safely. Trash
is soft deletion and does not reclaim revision storage in this milestone.

### Access model

- Workspace **owner/admin/member** roles govern team administration. Only owners
  can invite admins; admins can invite/remove members. An owner cannot be removed
  through the member-removal endpoint.
- Document owners manage document grants and view links. Editors can save, rename,
  move, and restore revisions. Viewers can read/download history.
- Document grants require current workspace membership. Named external sharing
  begins with a team invitation; personal workspaces use view links in this version.
- Membership alone, including admin membership, does not grant document content.
  `POST /v1/documents/{id}/admin-recovery` explicitly transfers ownership to a
  workspace administrator and records `document.admin_recovery` in activity.
- Removing a member deletes their explicit document grants. Accepted invitations
  cannot be replayed to rejoin. Documents remain owned by the workspace's storage
  container and can be recovered by its administrator.
- Public share links grant **view/download only**. Tokens are randomly generated,
  stored as SHA-256 hashes, expire within 30 days, and never confer edit access.
  Revocation blocks new requests; already downloaded or in-flight bytes cannot
  be recalled. Trashing a document revokes its links permanently.
- Folders are flat organization within a workspace and do not inherit permissions.
  Moving a document cannot change its workspace or permissions.

## API reference

JSON field names use `snake_case`. Errors are JSON; unauthorized private resources
usually return 404. Invalid requests return 400, denied administrative actions
403, stale saves 409, and exceeded upload/quota limits 413. Responses disable
caching. Authenticated mutations and their audit event commit in one transaction.

| Method | Route | Purpose |
|---|---|---|
| GET | `/v1/workspaces/{id}/documents` | Authorized documents, including the caller's visible trash |
| GET/POST | `/v1/workspaces/{id}/folders` | List/create folders (`name`) |
| POST | `/v1/documents/{id}/move` | Set `folder_id`; null moves to root |
| GET/PATCH/DELETE | `/v1/documents/{id}` | Metadata / rename (`name`) / trash |
| POST | `/v1/documents/{id}/restore` | Restore from trash |
| GET | `/v1/documents/{id}/revisions` | Revision history |
| POST | `/v1/documents/{id}/revisions/{revision}/restore` | Restore history; supply `base_revision_id` |
| GET/POST | `/v1/documents/{id}/grants` | List/set named-user permissions |
| DELETE | `/v1/documents/{id}/grants/{user}` | Revoke a grant |
| GET/POST | `/v1/documents/{id}/shares` | List/create links (`expires_in_hours`, default 24) |
| DELETE | `/v1/documents/{id}/shares/{link}` | Revoke a link |
| GET | `/v1/shares/{token}` or `/content` | Public shared metadata or bytes |
| GET | `/v1/uploads/{id}` | Save-session status |
| DELETE | `/v1/workspaces/{id}/invitations/{invitation}` | Revoke invitation |
| DELETE | `/v1/workspaces/{id}/members/{user}` | Remove member |
| GET | `/v1/workspaces/{id}/activity` | Administrative audit events |

Library, workspace, revision and activity lists currently return at most 200
records, and member lists 1,000. Use `?offset=200` (or `1000` for members)
to fetch subsequent pages. Lists are live views, so refresh after concurrent
changes. Nested folders, group grants,
ownership transfer UI, invitation email delivery, preview rendering, retention
purging, a document search index, and browser/native client integration are
follow-on work. No sync algorithm is chosen by this storage protocol.

## Verification

```sh
swift test
# Uses the local PostgreSQL server; creates and drops only a unique temporary DB.
python3 scripts/integration.py
```

Tests cover JWT issuer/audience/expiry/algorithm/signature and email verification,
immutable local object publication, the HTTP permission boundaries, invitation
acceptance, concurrent commit races, retry idempotence, recovery of conflicting
uploads, revision restore, cross-document isolation, link revocation, trash,
quota cleanup, and persistence across restart.

The same integration suite can target an S3 emulator by setting `S3_BUCKET`,
`S3_ENDPOINT`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, and `AWS_SECRET_ACCESS_KEY` before
running it. Create a **disposable test bucket** first: committed test blobs remain
in that bucket after the temporary PostgreSQL database is dropped. The checked
implementation passed 82 HTTP checks with disk storage and the same 82 against a
local Moto S3 emulator, plus the Swift unit tests. Live cloud-provider behavior
and the Linux container build have not yet been verified.
