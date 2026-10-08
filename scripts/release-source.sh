#!/usr/bin/env bash
# Reproducible, tracked-source-only archive; never publishes anything.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
version="$(sed -n 's/.*:version "\([^"]*\)".*/\1/p' cl-state.asd | head -1)"
test -n "$version"
out="${1:-$PWD/cl-state-$version.tar.gz}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
test ! -e "$out" || { echo "Refusing to overwrite $out" >&2; exit 2; }
git diff --quiet && git diff --cached --quiet || {
  echo "Commit scoped changes before creating an archive" >&2; exit 2;
}
git archive --format=tar --prefix="cl-state-$version/" HEAD | gzip -n > "$out"
sha256sum "$out"
if [[ "${COLD_TEST:-0}" == 1 ]]; then
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  tar -xzf "$out" -C "$scratch"
  cd "$scratch/cl-state-$version"
  clpm bundle exec --with-client sbcl -- --noinform --non-interactive \
    --eval '(require :asdf)' --eval '(asdf:test-system "cl-state")'
fi
