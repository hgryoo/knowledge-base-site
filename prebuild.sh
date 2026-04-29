#!/usr/bin/env bash
# Build content/ from ../knowledge-base/knowledge into bilingual en/ and ko/ trees.
# Override SRC env var to point elsewhere (used by CI).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$SCRIPT_DIR/../knowledge-base/knowledge}"
EN="$SCRIPT_DIR/content/en"
KO="$SCRIPT_DIR/content/ko"

if [[ ! -d "$SRC" ]]; then
  echo "ERROR: source $SRC not found" >&2
  exit 1
fi

rm -rf "$SCRIPT_DIR/content"
mkdir -p "$EN" "$KO"

# en/: mirror source, drop *_ko.md, CLAUDE.md, and tooling state dirs
rsync -a \
  --exclude='CLAUDE.md' \
  --exclude='*_ko.md' \
  --exclude='.omc/' \
  --exclude='.claude/' \
  "$SRC/" "$EN/"

# ko/: mirror source (English files act as fallback when no _ko pair exists)
rsync -a \
  --exclude='CLAUDE.md' \
  --exclude='.omc/' \
  --exclude='.claude/' \
  "$SRC/" "$KO/"

# In ko/: rename foo_ko.md -> foo.md, overwriting any English partner
find "$KO" -type f -name '*_ko.md' -print0 | while IFS= read -r -d '' f; do
  mv -f "$f" "${f%_ko.md}.md"
done

# Top-level landing page that links into the two language trees
cat > "$SCRIPT_DIR/content/index.md" <<'EOF'
---
title: Knowledge Base
---

- [English](en/)
- [한국어](ko/)
EOF

echo "prebuild: en=$(find "$EN" -type f -name '*.md' | wc -l) md, ko=$(find "$KO" -type f -name '*.md' | wc -l) md"
