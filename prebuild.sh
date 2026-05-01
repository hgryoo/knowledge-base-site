#!/usr/bin/env bash
# Build content/ from ../knowledge-base/knowledge into bilingual en/ and ko/ trees.
# Override SRC env var to point elsewhere (used by CI).
#
# Source layout (kb side, since 2026-05-01):
#   $SRC/<category>/<...>/<doc>.md          — English (primary).
#   $SRC/<category>/<...>/<doc>.assets/     — figures (shared).
#   $SRC/ko/<category>/<...>/<doc>.md       — Korean mirror (parallel composition).
#
# Site layout (this side):
#   content/en/<category>/<...>/<doc>.md    — English tree.
#   content/ko/<category>/<...>/<doc>.md    — Korean override; English fallback
#                                             where no Korean mirror exists yet.
#
# Mode:
#   default                   — public build; excludes methodology/ (private).
#   QUARTZ_LOCAL_FULL=1       — local LAN build; includes methodology/
#                               (use together with scripts/serve-local.sh).
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

# Common exclusions: CLAUDE.md (rule files), tooling state, leftover
# `_ko.md` files from the old co-located convention, and the meta
# folder (`.meta/<doc>.yaml` is decision context, not site content).
COMMON_EXCLUDES=(
  --exclude='CLAUDE.md'
  --exclude='*_ko.md'
  --exclude='.omc/'
  --exclude='.claude/'
  --exclude='.meta/'
)

# en/: copy the primary tree and drop the Korean mirror subtree
# (knowledge/ko/) along with the common exclusions.
rsync -a \
  --exclude='ko/' \
  "${COMMON_EXCLUDES[@]}" \
  ${PRIVATE_EXCLUDES[@]+"${PRIVATE_EXCLUDES[@]}"} \
  "$SRC/" "$EN/"

# ko/: start from the same English tree as a fallback (so any
# untranslated page still resolves to readable English text and
# every <doc>.assets/ folder is present), then overlay the Korean
# mirror on top. The overlay step copies every file under
# knowledge/ko/<category>/... to content/ko/<category>/...,
# overwriting the English fallback wherever a Korean mirror exists.
rsync -a \
  --exclude='ko/' \
  "${COMMON_EXCLUDES[@]}" \
  ${PRIVATE_EXCLUDES[@]+"${PRIVATE_EXCLUDES[@]}"} \
  "$SRC/" "$KO/"

if [[ -d "$SRC/ko" ]]; then
  # --copy-unsafe-links dereferences any symlink in $SRC/ko/ whose
  # target points outside the source tree. The bilingual figure
  # convention (since 2026-05-01) uses such symlinks: every
  # `knowledge/ko/<...>/<doc>.assets` is a relative symlink to the
  # canonical EN folder at `knowledge/<...>/<doc>.assets` (3 ups).
  # This flag turns each symlink into a real copy of its referent
  # so the built `content/ko/` tree carries real PNG files
  # regardless of what the EN-baseline rsync above did.
  rsync -a --copy-unsafe-links \
    "${COMMON_EXCLUDES[@]}" \
    ${PRIVATE_EXCLUDES[@]+"${PRIVATE_EXCLUDES[@]}"} \
    "$SRC/ko/" "$KO/"
fi

# Sanity: refuse the build if any *_ko.md files leaked through (the
# mirror tree should be the only Korean source path now) or if the
# Korean mirror subtree leaked into either built tree.
leaked_ko_md="$(find "$EN" "$KO" -type f -name '*_ko.md' | head -5 || true)"
if [[ -n "$leaked_ko_md" ]]; then
  echo "ERROR: stray _ko.md files in built content; old convention" >&2
  echo "$leaked_ko_md" >&2
  exit 1
fi

if [[ -d "$EN/ko" || -d "$KO/ko" ]]; then
  echo "ERROR: knowledge/ko/ subtree leaked into built content" >&2
  exit 1
fi

{ grep -RIl '^summary: "|"$' content || true; } | xargs -r sed -i 's/^summary: "|"$/summary: |/'

# Generate landing page from frontmatter
python3 "$SCRIPT_DIR/scripts/generate_index.py" "$EN" "$SCRIPT_DIR/content/index.md"

echo "prebuild: en=$(find "$EN" -type f -name '*.md' | wc -l) md, ko=$(find "$KO" -type f -name '*.md' | wc -l) md (local_full=${QUARTZ_LOCAL_FULL:-0})"
