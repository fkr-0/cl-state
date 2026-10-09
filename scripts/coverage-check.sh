#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf coverage
mkdir -p coverage
clpm bundle exec --with-client sbcl -- --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval '(require :sb-cover)' \
  --eval '(declaim (optimize sb-cover:store-coverage-data))' \
  --eval '(asdf:compile-system "cl-state" :force t)' \
  --eval '(asdf:load-system "cl-state-tests")' \
  --eval '(asdf:test-system "cl-state-tests")' \
  --eval '(sb-cover:report #P"coverage/" :if-matches (lambda (path) (search "/src/state/" path)))'
python3 scripts/coverage_gate.py --min 85
