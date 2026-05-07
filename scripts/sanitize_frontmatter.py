#!/usr/bin/env python3
"""Quote YAML frontmatter scalars that start with a reserved indicator.

The site is built from upstream content (../knowledge-base) that
occasionally lands with frontmatter like:

    title: [KO] CUBRID 락프리 비트맵 — ...
    summary: `unloaddb` 의 end-to-end 분석 ...

Both fail js-yaml's strict parse: `[` opens a flow sequence (and the
trailing `]` is far away), and `` ` `` is one of YAML's reserved
indicators at scalar start. We can't fix upstream from here (their
own automation rewrites the files), so we sanitize the rsync'd
content/ tree in place between prebuild rsync and quartz build.

Scope:
  - Single-line plain scalars on top-level frontmatter keys only.
  - Single-quote-wrap if the value starts with `[`, `` ` ``, `@`, `{`.
  - Skip multi-line block scalars (`|`, `>`) and already-quoted values.
  - Skip the `references:` and `tags:` keys — those are real flow
    sequences that should stay parsed as lists.

Idempotent: re-running on already-quoted content is a no-op.
"""

import argparse
import pathlib
import re
import sys

# Top-level keys that legitimately carry inline flow sequences/maps and
# must NOT be touched.
LIST_KEYS = {"references", "tags", "sources", "aliases"}

# Free-form prose keys: always quote when plain. Their values can contain
# arbitrary punctuation (including `: ` mid-string, which YAML otherwise
# parses as a nested mapping, and reserved leading indicators).
PROSE_KEYS = {"title", "summary", "description"}

# Reserved/unsafe leading characters that force quoting when a plain
# scalar would otherwise start with them. Applied to non-prose keys too.
UNSAFE_LEADS = ("[", "`", "@", "{")

# `^key: value` on a single line. value group is everything after the
# first ": " up to end-of-line. Captures only top-level keys (no
# leading indent).
KV_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*): (.*)$")


def needs_quote(key: str, value: str) -> bool:
    if not value:
        return False
    # Already quoted (single or double) — skip.
    if value.startswith("'") or value.startswith('"'):
        return False
    # Block scalar markers — skip.
    if value in ("|", ">") or value.startswith(("|", ">")):
        return False
    # Free-form prose keys: always quote when plain.
    if key in PROSE_KEYS:
        return True
    return value.startswith(UNSAFE_LEADS)


def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sanitize_frontmatter(text: str) -> tuple[str, int]:
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\n") != "---":
        return text, 0
    end = None
    for i in range(1, len(lines)):
        if lines[i].rstrip("\n") == "---":
            end = i
            break
    if end is None:
        return text, 0

    fixes = 0
    for i in range(1, end):
        line = lines[i]
        if not line.endswith("\n"):
            line_body, nl = line, ""
        else:
            line_body, nl = line[:-1], "\n"
        m = KV_RE.match(line_body)
        if not m:
            continue
        key, value = m.group(1), m.group(2)
        if key in LIST_KEYS:
            continue
        if not needs_quote(key, value):
            continue
        lines[i] = f"{key}: {quote(value)}{nl}"
        fixes += 1

    return "".join(lines), fixes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=pathlib.Path,
                    help="content/ directory to walk")
    args = ap.parse_args()

    if not args.root.is_dir():
        print(f"sanitize: {args.root} is not a directory", file=sys.stderr)
        return 1

    total_files = 0
    total_fixes = 0
    for p in args.root.rglob("*.md"):
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as e:
            print(f"sanitize: skip {p}: {e}", file=sys.stderr)
            continue
        new_text, fixes = sanitize_frontmatter(text)
        if fixes:
            p.write_text(new_text, encoding="utf-8")
            total_files += 1
            total_fixes += fixes

    print(f"sanitize: {total_fixes} scalar(s) quoted across "
          f"{total_files} file(s) under {args.root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
