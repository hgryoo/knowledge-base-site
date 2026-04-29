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
    "code-analysis": "오픈소스 DBMS 내부 — 현재는 CUBRID 코드베이스를 storage / MVCC / lock manager 단위로 뜯어본 노트입니다.",
    "research": "교과서·논문에서 정리한 데이터베이스 시스템 노트.",
    "note": "작업 노트와 잡다한 캡처.",
    "experiment": "가설 기반 실험과 결과 정리.",
    "ideas": "당장은 설익었지만 살려두고 싶은 아이디어.",
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
        "DBMS 내부 구조와 코드 분석을 정리해 두는 곳입니다. CUBRID 코드베이스를 "
        "중심으로 storage, MVCC, lock manager 같은 핵심 모듈을 한 줄씩 뜯어보며 "
        "남긴 캡처와, 그 위에서 쌓아 올린 연구 노트를 모아둡니다."
    )
    out.append("")
    out.append(
        "사이드바의 explorer로 폴더를 탐색하거나, 우측 상단의 검색·그래프뷰를 "
        "이용해 문서 사이를 점프할 수 있습니다."
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

    out.append("## 한국어")
    out.append("")
    out.append("[/ko/](ko/) 트리에 한국어 버전이 있습니다. 영문판만 있는 문서는 ko/에서도 영문 그대로 노출됩니다.")
    out.append("")

    output.write_text("\n".join(out), encoding="utf-8")
    total = sum(len(e) for e in by_cat.values())
    print(f"generate_index: {total} entries across {len(by_cat)} categories")
    return 0


if __name__ == "__main__":
    sys.exit(main())
