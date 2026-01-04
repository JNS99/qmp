#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Dict, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]
PENDING_ENTRY = REPO_ROOT / "scripts" / "pending_entry.json"

SECTION_HEADERS = ("POEMA", "POEMA_CITADO", "TEXTO")

META_ALIASES = {
    "FECHA": "date",
    "MY_POEM_TITLE": "my_poem_title",
    "POETA": "poet",
    "POEM_TITLE": "poem_title",
    "BOOK_TITLE": "book_title",
}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

def parse_meta_and_body(raw: str) -> Tuple[Dict[str, str], str]:
    """Parse optional metadata header (KEY: value) at top. Returns (meta, rest)."""
    meta: Dict[str, str] = {}
    lines = raw.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        if not line.strip():
            i += 1
            break
        m = re.match(r"^\s*([A-Z_]+)\s*:\s*(.*)\s*$", line)
        if not m:
            break
        k, v = m.group(1), m.group(2)
        if k in META_ALIASES:
            meta[META_ALIASES[k]] = v
        i += 1
    body = "\n".join(lines[i:]).strip()
    return meta, body

def extract_sections(body: str) -> Dict[str, str]:
    sections: Dict[str, str] = {}
    header_re = re.compile(r"(?m)^\s*#\s*(POEMA|POEMA_CITADO|TEXTO)\s*$")
    matches = list(header_re.finditer(body))
    for idx, m in enumerate(matches):
        name = m.group(1)
        start = m.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(body)
        sections[name] = body[start:end].strip()
    return sections

def first_nonempty_line(s: str) -> str:
    for line in s.splitlines():
        t = line.strip()
        if t:
            return t
    return ""


def snippet_if_no_title(title: str, section_text: str) -> str:
    """Return snippet only when title is empty; else return empty string."""
    return "" if (title or "").strip() else first_nonempty_line(section_text)

def month_from_date(d: str) -> str:
    return d[:7]

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("txt_path", help="Path a textos/YYYY-MM-DD.txt")
    ap.add_argument("--out", default=str(PENDING_ENTRY), help="Output pending_entry.json path")
    args = ap.parse_args()

    txt_path = Path(args.txt_path)
    if not txt_path.is_absolute():
        txt_path = (REPO_ROOT / txt_path).resolve()

    raw = txt_path.read_text(encoding="utf-8")

    meta, body = parse_meta_and_body(raw)
    sections = extract_sections(body)

    # date: from meta or filename
    date = meta.get("date")
    if not date:
        date = txt_path.stem
    if not DATE_RE.fullmatch(date):
        raise SystemExit(f"Invalid/missing date (FECHA:) and filename not YYYY-MM-DD: {date}")

    entry = {
        "date": date,
        "month": month_from_date(date),
        "file": f"textos/{date}.txt",
        "my_poem_title": meta.get("my_poem_title", "").strip(),
        "my_poem_snippet": snippet_if_no_title(meta.get("my_poem_title", ""), sections.get("POEMA", "")),
        "analysis": {
            "poet": meta.get("poet", "").strip(),
            "poem_title": meta.get("poem_title", "").strip(),
            "poem_snippet": snippet_if_no_title(meta.get("poem_title", ""), sections.get("POEMA_CITADO", "")),
            "book_title": meta.get("book_title", "").strip(),
        },
        # keywords are filled/kept in merge step
        "keywords": [],
        # carry full sections so the site can render from the txt file (your JS reads txt file).
        # We still include them in pending for validation/logging.
        "sections": {
            "POEMA": sections.get("POEMA", ""),
            "POEMA_CITADO": sections.get("POEMA_CITADO", ""),
            "TEXTO": sections.get("TEXTO", ""),
        },
    }

    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = (REPO_ROOT / out_path).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out_path}")

if __name__ == "__main__":
    main()
