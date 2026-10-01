#!/usr/bin/env bash
# Publish an app's browser build to a GitHub Pages site.
#
#   build/web-deploy.sh [app] [--no-build] [--host NAME] [--repo URL]
#
# Default app OfficeApp (apps/OfficeApp), published as writer.starling.build
# from the site repo git@github.com:starling-build/writer.git — ui/deploy.sh's
# shape, for the same host. The subdomain needs a DNS CNAME `writer` ->
# starling-build.github.io (DNS only, not proxied, so GitHub can issue the
# certificate) and the custom domain set in the repo's Pages settings, which
# GitHub records as a CNAME file it commits itself. (starling.build/writer/
# would need no DNS, but only if the root site's repo were named
# starling-build.github.io; it is `www`, so project paths 404 there —
# measured, 2026-09-30.)
#
# GitHub Pages serves a branch as static files and nothing else, so the
# page gets no Content-Encoding for a precompressed module. The tree pushed
# here therefore carries `app.wasm.gz` in place of `app.wasm`, and
# web/host/starling.js inflates a `.gz` module itself (4 MB over the wire,
# not 12). Everything else is build/web-app.sh's stage as is; every asset
# is referenced relative to index.html, so a subpath is fine.
#
# One-time setup on the site repo: Settings -> Pages -> source `main` / root.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

APP="OfficeApp"
BUILD=1
HOST="writer.starling.build"
SITE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-build) BUILD=0 ;;
        --host) HOST="$2"; shift ;;
        --repo) SITE="$2"; shift ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) APP="$1" ;;
    esac
    shift
done
if [ -z "$SITE" ]; then
    SITE="${STARLING_WRITER_SITE_REPO:-}"
fi
if [ -z "$SITE" ]; then
    # The protocol this repo's origin uses is the one with working
    # credentials (ui/deploy.sh learned that twice).
    if git -C "$REPO_ROOT" remote get-url origin 2>/dev/null | grep -q '^https://'; then
        SITE="https://github.com/starling-build/writer.git"
    else
        SITE="git@github.com:starling-build/writer.git"
    fi
fi

PACKAGE="apps/$APP"
[ -d "$REPO_ROOT/$PACKAGE" ] || { echo "error: no app package at $PACKAGE" >&2; exit 1; }
STAGE="$REPO_ROOT/.stage-web-$APP"

if [ "$BUILD" = 1 ]; then
    "$REPO_ROOT/build/web-app.sh" "$APP" --package "$PACKAGE"
fi
[ -f "$STAGE/app.wasm.gz" ] || { echo "error: no release build staged at $STAGE (build/web-app.sh $APP --package $PACKAGE)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --depth 1 "$SITE" "$WORK/site" 2>/dev/null || {
    echo "error: cannot clone $SITE — create it (public) first" >&2; exit 1
}
find "$WORK/site" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +

# The stage, minus the raw and brotli modules, plus the gzip one the page
# will inflate; index.html points at it.
cp -R "$STAGE"/. "$WORK/site/"
rm -f "$WORK/site/app.wasm" "$WORK/site/app.wasm.br"
sed -i '' "s|app: 'app.wasm'|app: 'app.wasm.gz'|" "$WORK/site/index.html"
grep -q "app: 'app.wasm.gz'" "$WORK/site/index.html" || { echo "error: index.html has no app: 'app.wasm' to repoint" >&2; exit 1; }
if [ -n "$HOST" ]; then echo "$HOST" > "$WORK/site/CNAME"; fi
# Pages runs Jekyll by default, which drops files and folders it does not
# like (anything starting with an underscore); this turns it off.
touch "$WORK/site/.nojekyll"

cd "$WORK/site"
git symbolic-ref HEAD refs/heads/main
if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
    echo "no changes to publish"; exit 0
fi
git add -A
git commit -q -m "site: $APP @ $(git -C "$REPO_ROOT" rev-parse --short HEAD)${HOST:+ for $HOST}"
git push -u origin main
echo "published -> $SITE${HOST:+ ($HOST)}"
