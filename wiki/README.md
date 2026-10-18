# wiki-server

The server half of the documentation site (`docs/plans/wiki.md`): Swift,
Hummingbird 2, Postgres through PostgresNIO. It stores pages as the Writer's
document model (JSON), never renders them as HTML, and serves the wasm
Office build that draws them. It links neither the suite nor the engine:
conversions shell out to the headless `OfficeApp` binary.

## Dev loop (macOS or Linux)

    createdb starling_wiki                       # Postgres 14+ running locally
    cd wiki && swift build
    .build/debug/wiki-server migrate
    .build/debug/wiki-server add-user dev --name "Dev" --password devpass --admin
    .build/debug/wiki-server create-space ENG --name Engineering
    # the app, native and web:
    (cd .. && swift build --package-path apps/OfficeApp)        # see docs/BUILDING.md for the engine env vars
    (cd .. && build/web-app.sh OfficeApp --package apps/OfficeApp)
    .build/debug/wiki-server serve --port 8080 \
        --web-root ../.stage-web-OfficeApp \
        --office-app ../apps/OfficeApp/.build/debug/OfficeApp \
        --public-url http://127.0.0.1:8080

Then http://127.0.0.1:8080/s/ENG in a browser, or natively
`apps/OfficeApp/.build/debug/OfficeApp --wiki http://127.0.0.1:8080/s/ENG`.
`WIKI_DATABASE_URL` (default `postgres://localhost/starling_wiki`) or
`--database` names the database; `LOG_LEVEL=debug` shows every request.
For a phone on the LAN: `--host 0.0.0.0 --public-url http://<lan-ip>:8080`,
and `--dev-user dev` makes every visitor without a session that user
(development only: there is no sign-in at all).

Import files from the command line:

    .build/debug/wiki-server import --space ENG --office-app ../apps/OfficeApp/.build/debug/OfficeApp a.docx b.md

## Gates

- `swift test` here — WikiModel's operational transform (14 tests).
- `test/wiki-api.sh` — the whole API against a throwaway database.
- `test/wiki-web.sh` — the wasm build in headless Chrome: sign in, open a
  page by URL, edit, save.
- `test/wiki-codec.sh` — the suite side: every corpus .docx survives the
  page encoding exactly.

## Layout

    Sources/WikiModel/     PageOp, Transform, PageSequencer, PendingOps (pure)
    Sources/WikiServer/    Schema (migrations), Store (Postgres), App (routes),
                           Shell (index.html + meta tags), Convert (OfficeApp),
                           WikiServerCommand (serve | migrate | add-user |
                           create-space | import)
    Tests/WikiModelTests/  convergence tests on a toy document
