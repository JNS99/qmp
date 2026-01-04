#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import unicodedata
from pathlib import Path
from typing import Any, Dict, List, Tuple


def _repo_root_from_txt(txt_path: Path) -> Path:
    # textos/YYYY-MM-DD.txt -> repo root = textos/.. = parent
    # but user might pass absolute/relative; be robust
    p = txt_path.resolve()
    if p.parent.name == "textos":
        return p.parent.parent
    # fallback: assume scripts lives in ../scripts relative to txt
    return p.parent.parent


def load_archivo(path: Path) -> Tuple[Dict[str, Any] | List[Any], List[Dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data.get("entries", []) if isinstance(data, dict) else data
    if not isinstance(entries, list):
        raise SystemExit("archivo.json: entries no es una lista")
    # normalize: ensure dicts
    out: List[Dict[str, Any]] = []
    for e in entries:
        if isinstance(e, dict):
            out.append(e)
    return data, out


def strip_accents(s: str) -> str:
    s = unicodedata.normalize("NFKD", s)
    return "".join(ch for ch in s if not unicodedata.combining(ch))


def norm_word(s: str) -> str:
    s = strip_accents(s).lower().strip()
    s = " ".join(s.split())
    return s


def normalize_keywords(kws: Any) -> List[Dict[str, Any]]:
    """
    Accepts:
      - list[{"word":..., "weight":...}]
      - {"keywords": [...]}
      - {"date": "...", "keywords":[...]}
    Returns stable, deduped, sorted list (desc weight, asc word).
    """
    if kws is None:
        raw = []
    elif isinstance(kws, dict):
        raw = kws.get("keywords", [])
    else:
        raw = kws

    if not isinstance(raw, list):
        raw = []

    best: Dict[str, int] = {}
    for item in raw:
        if not isinstance(item, dict):
            continue
        w = norm_word(str(item.get("word", "")))
        if not w:
            continue
        try:
            weight = int(item.get("weight", 1))
        except Exception:
            weight = 1
        weight = max(1, min(3, weight))
        best[w] = max(best.get(w, 0), weight)

    out = [{"word": w, "weight": best[w]} for w in best]
    out.sort(key=lambda d: (-d["weight"], d["word"]))
    return out


def keywords_equal(a: Any, b: Any) -> bool:
    return normalize_keywords(a) == normalize_keywords(b)


def build_pending_entry_via_script(repo: Path, txt_path: Path, out_path: Path) -> Dict[str, Any]:
    script = repo / "scripts" / "make_pending_entry.py"
    if not script.exists():
        raise SystemExit("No existe scripts/make_pending_entry.py (necesario para parsear el .txt con schema histórico)")
    cmd = [sys.executable, str(script), str(txt_path), "--out", str(out_path)]
    subprocess.check_call(cmd)
    entry = json.loads(out_path.read_text(encoding="utf-8"))
    if not isinstance(entry, dict) or entry.get("date") is None:
        raise SystemExit("pending_entry.json inválido (make_pending_entry.py no devolvió un entry correcto)")
    # archivo.json debe ser índice: NO guardamos sections completas
    entry.pop("sections", None)
    return entry


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("txt_path", help="Path a textos/YYYY-MM-DD.txt")
    ap.add_argument("--apply-keywords", action="store_true", help="Aplicar keywords desde scripts/pending_keywords.txt")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    txt_path = Path(args.txt_path)
    if not txt_path.exists():
        raise SystemExit(f"No existe: {txt_path}")

    repo = _repo_root_from_txt(txt_path)
    archivo = repo / "archivo.json"
    pending_kw_path = repo / "scripts" / "pending_keywords.txt"
    pending_entry_path = repo / "scripts" / "pending_entry.json"

    data, entries = load_archivo(archivo)

    # Parsear contenido con el schema histórico (single source of truth)
    entry = build_pending_entry_via_script(repo, txt_path, pending_entry_path)
    date = entry["date"]

    old_entry = next((e for e in entries if e.get("date") == date), None)
    exists_before = old_entry is not None

    # keywords logic
    applied_keywords = False
    if args.apply_keywords:
        if not pending_kw_path.exists():
            raise SystemExit("Falta scripts/pending_keywords.txt (necesario para --apply-keywords)")
        pending_payload = json.loads(pending_kw_path.read_text(encoding="utf-8"))
        new_kws = normalize_keywords(pending_payload)
        entry["keywords"] = new_kws
        applied_keywords = True
    else:
        # preserve existing keywords
        entry["keywords"] = old_entry.get("keywords", []) if old_entry else []

    # Enforce contract: una entrada nueva NO se publica sin keywords
    if not exists_before and not entry.get("keywords"):
        raise SystemExit("Entrada nueva sin keywords. Usa: q --kw YYYY-MM-DD (o ejecuta qk primero).")

    # Change detection
    def without_keywords(e: Dict[str, Any]) -> Dict[str, Any]:
        d = dict(e)
        d.pop("keywords", None)
        return d

    content_changed = True
    if old_entry:
        content_changed = without_keywords(old_entry) != without_keywords(entry)

    keywords_changed = True
    if old_entry:
        keywords_changed = not keywords_equal(old_entry.get("keywords", []), entry.get("keywords", []))
    else:
        # new entry: treat as changed if it has any keywords
        keywords_changed = bool(entry.get("keywords"))

    # Write pending_entry.json (already created; rewrite to ensure keywords are final)
    pending_entry_path.write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    status = {
        "dry_run": bool(args.dry_run),
        "date": date,
        "exists_before": exists_before,
        "content_changed": bool(content_changed),
        "keywords_changed": bool(keywords_changed),
        "applied_keywords": bool(applied_keywords),
        # for commit message (must be from poema propio)
        "my_poem_title": entry.get("my_poem_title", "") or "",
        "my_poem_snippet": entry.get("my_poem_snippet", "") or "",
    }

    print("STATUS_JSON=" + json.dumps(status, ensure_ascii=False))
    if args.dry_run:
        return


if __name__ == "__main__":
    main()
