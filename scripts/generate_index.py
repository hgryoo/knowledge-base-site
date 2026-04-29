#!/usr/bin/env python3
"""Generate the top-level content/index.md by walking content/en/ and reading
frontmatter (`title`, `summary`) from each curated markdown file. Invoked by
prebuild.sh.

Usage: generate_index.py <en_dir> <output_path>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

CATEGORY_DESCRIPTIONS = {
    "code-analysis": "Open-source DBMS internals — currently a line-by-line read of the CUBRID codebase, broken down by storage, MVCC, and lock manager.",
    "research": "Notes captured from textbooks and papers on database systems.",
    "note": "Working notes and miscellaneous captures.",
    "experiment": "Hypothesis-driven experiments and their write-ups.",
    "ideas": "Half-baked ideas worth keeping around.",
}

CATEGORY_ORDER = ["code-analysis", "research", "experiment", "ideas", "note"]


def read_frontmatter(p: Path) -> dict[str, str]:
    text = p.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    fm: dict[str, str] = {}
    for line in m.group(1).splitlines():
        kv = re.match(r"^(\w+):\s*(.*)$", line)
        if not kv:
            continue
        key, val = kv.group(1), kv.group(2).strip()
        if (val.startswith('"') and val.endswith('"')) or (
            val.startswith("'") and val.endswith("'")
        ):
            val = val[1:-1]
        fm[key] = val
    return fm


def main() -> int:
    en_dir = Path(sys.argv[1])
    output = Path(sys.argv[2])

    by_cat: dict[str, list[tuple[str, str, str]]] = {}
    for cat_dir in sorted(p for p in en_dir.iterdir() if p.is_dir()):
        entries: list[tuple[str, str, str]] = []
        for md in sorted(cat_dir.rglob("*.md")):
            if md.name == "README.md":
                continue
            fm = read_frontmatter(md)
            title = fm.get("title") or md.stem
            summary = fm.get("summary", "")
            rel = md.relative_to(en_dir.parent).with_suffix("")
            entries.append((title, summary, rel.as_posix()))
        if entries:
            by_cat[cat_dir.name] = entries

    ordered = [c for c in CATEGORY_ORDER if c in by_cat] + [
        c for c in by_cat if c not in CATEGORY_ORDER
    ]

    out: list[str] = []
    out.append("---")
    out.append("title: hgryoo's Knowledge Base")
    out.append("---")
    out.append("")
    out.append(
        "Notes on database internals and code analysis, mostly centered on "
        "CUBRID. The site captures storage, MVCC, lock manager, and similar "
        "core modules at a line-by-line level, alongside research notes "
        "built on top of those captures."
    )
    out.append("")
    out.append(
        "Browse the folder explorer on the left, or use the search and "
        "graph view in the upper-right to jump between documents."
    )
    out.append("")
    out.append("## Categories")
    out.append("")
    for cat in ordered:
        entries = by_cat[cat]
        out.append(f"### [{cat}](en/{cat}/) ({len(entries)})")
        desc = CATEGORY_DESCRIPTIONS.get(cat)
        if desc:
            out.append("")
            out.append(desc)
        out.append("")
        for title, summary, rel in entries:
            line = f"- [{title}]({rel})"
            if summary:
                line += f" — {summary}"
            out.append(line)
        out.append("")

    out.append("## Languages")
    out.append("")
    out.append(
        "Korean translations live under [/ko/](ko/). Documents that exist only "
        "in English are mirrored as-is in the Korean tree."
    )
    out.append("")

    output.write_text("\n".join(out), encoding="utf-8")
    total = sum(len(e) for e in by_cat.values())
    print(f"generate_index: {total} entries across {len(by_cat)} categories")
    return 0


if __name__ == "__main__":
    sys.exit(main())
