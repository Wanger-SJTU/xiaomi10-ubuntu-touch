#!/bin/sh
# Enable the repository's git hooks (auto co-authorship trailer etc.).
# Run once per clone:  sh scripts/enable-git-hooks.sh
set -eu
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true
echo "core.hooksPath -> $(git config core.hooksPath)"
