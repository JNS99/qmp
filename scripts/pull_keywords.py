#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
ARCHIVO_JSON = Path(os.environ.get("QMP_ARCHIVO_JSON", str(REPO_ROOT / "archivo.json")))

def load_entries():
    data = json.loads(ARCHIVO_JSON.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        return data.get("entries", [])
    if isinstance(data, list):
        return data
    raise ValueError("archivo.json: formato inesperado (ni dict ni list)")

def main():
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("Usage: pull_keywords.py YYYY-MM-DD [output_path]", file=sys.stderr)
        return 2

    date = sys.argv[1]
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
        print(f"Invalid date: {date}", file=sys.stderr)
        return 2

    out = Path(sys.argv[2]) if len(sys.argv) == 3 else Path(f"/tmp/qmp_keywords_{date}.json")

    entries = load_entries()
    entry = next((e for e in entries if isinstance(e, dict) and e.get("date") == date), None)
    if not entry:
        print(f"No entry found for {date} in archivo.json", file=sys.stderr)
        return 1

    payload = {
        "date": date,
        "keywords": entry.get("keywords", []),
    }
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(str(out))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
