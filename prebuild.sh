#!/usr/bin/env bash
# Build content/ from ../knowledge-base/knowledge into bilingual en/ and ko/ trees.
# Override SRC env var to point elsewhere (used by CI).
#
# Mode:
#   default                   — public build; excludes methodology/ (private)
#   QUARTZ_LOCAL_FULL=1       — local LAN build; includes methodology/
#                               (use together with scripts/serve-local.sh)
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

# Folders excluded from the public site (private working assets).
# In local-full mode, this list is empty so every curated doc is exposed.
PRIVATE_EXCLUDES=()
if [[ "${QUARTZ_LOCAL_FULL:-0}" != "1" ]]; then
  PRIVATE_EXCLUDES+=( --exclude='methodology/' )
fi

# en/: mirror source, drop *_ko.md, CLAUDE.md, tooling state, and private folders
rsync -a \
  --exclude='CLAUDE.md' \
  --exclude='*_ko.md' \
  --exclude='.omc/' \
  --exclude='.claude/' \
  ${PRIVATE_EXCLUDES[@]+"${PRIVATE_EXCLUDES[@]}"} \
  "$SRC/" "$EN/"

# ko/: mirror source (English files act as fallback when no _ko pair exists)
rsync -a \
  --exclude='CLAUDE.md' \
  --exclude='.omc/' \
  --exclude='.claude/' \
  ${PRIVATE_EXCLUDES[@]+"${PRIVATE_EXCLUDES[@]}"} \
  "$SRC/" "$KO/"

# In ko/: rename foo_ko.md -> foo.md, overwriting any English partner
find "$KO" -type f -name '*_ko.md' -print0 | while IFS= read -r -d '' f; do
  mv -f "$f" "${f%_ko.md}.md"
done

# Generate landing page from frontmatter
python3 "$SCRIPT_DIR/scripts/generate_index.py" "$EN" "$SCRIPT_DIR/content/index.md"

echo "prebuild: en=$(find "$EN" -type f -name '*.md' | wc -l) md, ko=$(find "$KO" -type f -name '*.md' | wc -l) md (local_full=${QUARTZ_LOCAL_FULL:-0})"
