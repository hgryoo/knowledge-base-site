#!/usr/bin/env python3
"""Generate the top-level content/index.md by walking content/en/ and reading
frontmatter (`title`, `summary`) from each curated markdown file. Invoked by
prebuild.sh.

Honors QUARTZ_LOCAL_FULL=1 to mirror quartz.config.ts: in public-build
mode only `code-analysis/` is published, so the landing page must list
that category alone (otherwise links to non-published pages 404).

Usage: generate_index.py <en_dir> <output_path>
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

LOCAL_FULL = os.environ.get("QUARTZ_LOCAL_FULL", "0") == "1"
PUBLISHED_CATEGORIES: set[str] | None = None if LOCAL_FULL else {"code-analysis"}

CATEGORY_DESCRIPTIONS = {
    "code-analysis": "Open-source DBMS internals — currently a line-by-line read of the CUBRID codebase, broken down by storage, MVCC, and lock manager.",
    "research": "Notes captured from textbooks and papers on database systems.",
    "note": "Working notes and miscellaneous captures.",
    "experiment": "Hypothesis-driven experiments and their write-ups.",
    "ideas": "Half-baked ideas worth keeping around.",
}

CATEGORY_ORDER = ["code-analysis", "research", "experiment", "ideas", "note"]

# Per-category sub-grouping. When a doc carries a `subcategory:` frontmatter
# field, it lands in the matching group below. Docs without `subcategory:`
# fall through to a flat list at the end.
#
# Each entry: (slug, display label). The order here is the display order.
SUBCATEGORY_ORDER: dict[str, list[tuple[str, str]]] = {
    "code-analysis": [
        ("overview",            "Overview & Reading Paths"),
        ("storage-engine",      "Storage Engine"),
        ("txn-recovery",        "Transaction & Recovery"),
        ("query-processing",    "Query Processing"),
        ("ddl-schema",          "DDL & Schema"),
        ("replication-ha",      "Replication & HA"),
        ("pl-language",         "Procedural Language"),
        ("server-architecture", "Server Architecture"),
        ("i18n-specialty",      "Internationalization & Specialty"),
    ],
}


def read_frontmatter(p: Path) -> dict[str, str]:
    text = p.read_text(encoding="utf-8").lstrip()
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

    # Per category: list of (title, summary, rel, subcategory) tuples.
    by_cat: dict[str, list[tuple[str, str, str, str]]] = {}
    for cat_dir in sorted(p for p in en_dir.iterdir() if p.is_dir()):
        if PUBLISHED_CATEGORIES is not None and cat_dir.name not in PUBLISHED_CATEGORIES:
            continue
        entries: list[tuple[str, str, str, str]] = []
        for md in sorted(cat_dir.rglob("*.md")):
            if md.name == "README.md":
                continue
            fm = read_frontmatter(md)
            title = fm.get("title") or md.stem
            summary = fm.get("summary", "")
            subcat = fm.get("subcategory", "")
            rel = md.relative_to(en_dir.parent).with_suffix("")
            entries.append((title, summary, rel.as_posix(), subcat))
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
    if LOCAL_FULL:
        out.append(
            "Notes on database internals and code analysis, mostly centered on "
            "CUBRID. The site captures storage, MVCC, lock manager, and similar "
            "core modules at a line-by-line level, alongside research notes "
            "built on top of those captures."
        )
    else:
        out.append(
            "Notes on database internals and code analysis, mostly centered on "
            "CUBRID. The site captures storage, MVCC, lock manager, and similar "
            "core modules at a line-by-line level."
        )
    out.append("")
    out.append(
        "Browse the folder explorer on the left, or use the search and "
        "graph view in the upper-right to jump between documents."
    )
    out.append("")
    out.append("## Categories")
    out.append("")

    # Emit a "Jump to:" anchor TOC for each category that has a defined
    # subcategory taxonomy. Anchors must match Quartz's github-slugger
    # behaviour: lowercase the label, drop `&`, replace spaces with `-`,
    # then suffix the live count from this build (so the anchor stays
    # in sync with the heading the script also emits below).
    def _slug(label: str) -> str:
        # `&` is stripped (becomes empty), surrounding spaces remain and
        # get hyphen-converted, producing the consecutive `--` that
        # github-slugger emits for tokens like "DDL & Schema".
        return label.lower().replace("&", "").replace(" ", "-")

    for cat in ordered:
        sub_taxonomy = SUBCATEGORY_ORDER.get(cat)
        if not sub_taxonomy:
            continue
        # Tally counts so we can suffix anchors and skip empty buckets.
        from collections import Counter
        counts = Counter(e[3] for e in by_cat[cat])
        chips: list[str] = []
        for slug, label in sub_taxonomy:
            n = counts.get(slug, 0)
            if not n:
                continue
            chips.append(f"[{label}](#{_slug(label)}-{n})")
        if chips:
            out.append(f"**Jump to {cat}:** " + " · ".join(chips))
            out.append("")

    for cat in ordered:
        entries = by_cat[cat]
        out.append(f"### [{cat}](en/{cat}/) ({len(entries)})")
        desc = CATEGORY_DESCRIPTIONS.get(cat)
        if desc:
            out.append("")
            out.append(desc)
        out.append("")

        # Group by subcategory if a taxonomy is defined for this category;
        # otherwise emit a flat list as before.
        sub_taxonomy = SUBCATEGORY_ORDER.get(cat)
        if sub_taxonomy:
            buckets: dict[str, list[tuple[str, str, str]]] = {
                slug: [] for slug, _ in sub_taxonomy
            }
            untagged: list[tuple[str, str, str]] = []
            for title, summary, rel, subcat in entries:
                if subcat in buckets:
                    buckets[subcat].append((title, summary, rel))
                else:
                    untagged.append((title, summary, rel))
            for slug, label in sub_taxonomy:
                bucket = buckets[slug]
                if not bucket:
                    continue
                out.append(f"#### {label} ({len(bucket)})")
                out.append("")
                for title, summary, rel in bucket:
                    line = f"- [{title}]({rel})"
                    if summary:
                        line += f" — {summary}"
                    out.append(line)
                out.append("")
            if untagged:
                out.append(f"#### Other ({len(untagged)})")
                out.append("")
                for title, summary, rel in untagged:
                    line = f"- [{title}]({rel})"
                    if summary:
                        line += f" — {summary}"
                    out.append(line)
                out.append("")
        else:
            for title, summary, rel, _ in entries:
                line = f"- [{title}]({rel})"
                if summary:
                    line += f" — {summary}"
                out.append(line)
            out.append("")

    out.append("## Languages")
    out.append("")
    if LOCAL_FULL:
        out.append(
            "Korean translations live under [/ko/](ko/). Documents that exist only "
            "in English are mirrored as-is in the Korean tree."
        )
    else:
        out.append(
            "Korean translations of the published pages live under "
            "[/ko/code-analysis/](ko/code-analysis/)."
        )
    out.append("")

    output.write_text("\n".join(out), encoding="utf-8")
    total = sum(len(e) for e in by_cat.values())
    print(f"generate_index: {total} entries across {len(by_cat)} categories")
    return 0


if __name__ == "__main__":
    sys.exit(main())
