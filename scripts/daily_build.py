#!/usr/bin/env python3
"""
scripts/daily_build.py (v2)

Compatibilidad:
- Soporta tus archivos existentes que SOLO tienen:
    # POEMA
    # POEMA_CITADO
    # TEXTO
  (sin metadatos arriba)
- Si agregas metadatos tipo "CLAVE: valor" antes de # POEMA, los usa.

Recomendación mínima (sin cambiar tu estilo con #):
  FECHA: 2025-12-24          (opcional si el nombre del archivo ya tiene fecha)
  POETA: ...
  POEM_TITLE: ...
  BOOK_TITLE: ...
  MY_POEM_TITLE: ...
  MY_POEM_SNIPPET: ...       (opcional)
  POEM_SNIPPET: ...          (opcional)

Carpetas (como dijiste):
- textos/  (los .txt)
- scripts/ (este script)
- archivo.json en la raíz del repo (fallback: data/archivo.json)

Uso:
  python3 scripts/daily_build.py textos/2025-12-24.txt
  python3 scripts/daily_build.py textos/2025-12-24.txt --poeta "..." --poem-title "..." --my-poem-title "..."

Seguridad:
- La key va en variable de entorno OPENAI_API_KEY (NO en git)
"""

import argparse
import json
import os
import re
import sys
import unicodedata
from pathlib import Path
from typing import Dict, List, Tuple

from openai import OpenAI


# ---------- CONFIG ----------
REPO_ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = (REPO_ROOT / "archivo.json") if (REPO_ROOT / "archivo.json").exists() else (REPO_ROOT / "data" / "archivo.json")
MODEL = os.getenv("OPENAI_MODEL", "gpt-5")
# ---------------------------


SECTION_HEADERS = ["POEMA", "POEMA_CITADO", "TEXTO"]

META_ALIASES = {
    "FECHA": "date",
    "DATE": "date",
    "POETA": "poet",
    "POET": "poet",
    "POEM_TITLE": "poem_title",
    "TITULO_POEMA": "poem_title",
    "POEM_SNIPPET": "poem_snippet",
    "FRAGMENTO_POEMA": "poem_snippet",
    "BOOK_TITLE": "book_title",
    "TITULO_LIBRO": "book_title",
    "MY_POEM_TITLE": "my_poem_title",
    "MI_TITULO": "my_poem_title",
    "MY_POEM_SNIPPET": "my_poem_snippet",
    "MI_FRAGMENTO": "my_poem_snippet",
}

def _strip_bom(s: str) -> str:
    return s.lstrip("\ufeff")

def parse_txt(txt_path: Path) -> Tuple[Dict[str, str], Dict[str, str]]:
    """
    Devuelve (meta, sections)

    meta: dict con keys normalizadas (date, poet, poem_title, poem_snippet, book_title, my_poem_title, my_poem_snippet)
    sections: dict con keys POEMA / POEMA_CITADO / TEXTO
    """
    raw = _strip_bom(txt_path.read_text(encoding="utf-8")).replace("\r\n", "\n")

    # 1) meta: líneas "CLAVE: valor" antes del primer header de sección
    meta: Dict[str, str] = {}
    first_header_pos = len(raw)
    for h in SECTION_HEADERS:
        m = re.search(rf"(?m)^\s*#\s*{re.escape(h)}\s*$", raw)
        if m:
            first_header_pos = min(first_header_pos, m.start())

    meta_block = raw[:first_header_pos]
    for line in meta_block.splitlines():
        m = re.match(r"^\s*([A-Za-zÁÉÍÓÚÑ_]+)\s*:\s*(.*?)\s*$", line)
        if not m:
            continue
        k = m.group(1).strip().upper()
        v = m.group(2).strip()
        if not v:
            continue
        if k in META_ALIASES:
            meta[META_ALIASES[k]] = v

    # 2) sections: texto entre headers "# NAME" y el siguiente header
    sections: Dict[str, str] = {}
    header_re = r"(?m)^\s*#\s*(POEMA|POEMA_CITADO|TEXTO)\s*$"
    matches = list(re.finditer(header_re, raw))
    for i, m in enumerate(matches):
        name = m.group(1)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(raw)
        sections[name] = raw[start:end].strip()

    # 3) fallbacks
    if "date" not in meta:
        m = re.search(r"\d{4}-\d{2}-\d{2}", txt_path.name)
        if m:
            meta["date"] = m.group(0)

    # snippets opcionales: si no vienen, intenta primera línea útil de la sección
    if "my_poem_snippet" not in meta:
        poem = sections.get("POEMA", "")
        for line in poem.splitlines():
            line = line.strip()
            if line:
                meta["my_poem_snippet"] = line
                break

    if "poem_snippet" not in meta:
        cited = sections.get("POEMA_CITADO", "")
        for line in cited.splitlines():
            line = line.strip()
            if line:
                meta["poem_snippet"] = line
                break

    return meta, sections


# ---------- KEYWORDS ----------
def normalize_no_accents(s: str) -> str:
    s = s.strip().lower()
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    s = re.sub(r"\s+", " ", s)
    return s

def enforce_keyword_rules(items: List[dict]) -> List[dict]:
    cleaned = []
    seen = set()
    for it in items:
        word = it.get("word") or it.get("k") or ""
        w = it.get("weight") or it.get("w") or 1
        try:
            w = int(w)
        except Exception:
            w = 1
        w = 3 if w >= 3 else (2 if w == 2 else 1)
        word = normalize_no_accents(str(word))
        if not word:
            continue
        if word in seen:
            continue
        seen.add(word)
        cleaned.append({"word": word, "weight": w})
    cleaned.sort(key=lambda x: -x["weight"])
    return cleaned[:30]

def redistribute_weights(kws: List[dict]) -> List[dict]:
    """
    Aplica tu regla simple:
      - 3–5 (w=3)
      - 6–10 (w=2)
      - resto (w=1)
    Usamos el orden actual como ranking.
    """
    n = len(kws)
    if n == 0:
        return kws
    top3 = min(5, n)
    top3 = max(3, top3) if n >= 3 else n
    remaining = n - top3
    mid2 = min(10, remaining)
    mid2 = max(6, mid2) if remaining >= 6 else remaining

    out = []
    for i, kw in enumerate(kws):
        if i < top3:
            w = 3
        elif i < top3 + mid2:
            w = 2
        else:
            w = 1
        out.append({"word": kw["word"], "weight": w})
    return out

def call_openai_keywords(analysis_text: str, context: dict) -> List[dict]:
    client = OpenAI()

    prompt = f"""
Genera keywords EN ESPAÑOL a partir del análisis.

Reglas:
- Ideal: 15–25 keywords por texto. Máximo absoluto: 30.
- Minúsculas.
- Sin acentos (ej: “ilusión” -> “ilusion”).
- Conceptos buscables (palabras que alguien escribiría en el buscador), no citas literales.
- Evita duplicados y variantes redundantes.
- Puedes usar 1–3 palabras si hace falta (tu JSON histórico ya usa frases).

Pesos (weight):
- 3–5 keywords con weight=3: núcleo temático.
- 6–10 keywords con weight=2: ideas fuertes / motivos recurrentes.
- El resto con weight=1: campo semántico / atmósfera.

Devuelve SOLO JSON válido con esta forma exacta:
{{"keywords":[{{"word":"...","weight":3}},{{"word":"...","weight":2}},{{"word":"...","weight":1}}]}}

Contexto (si falta algo, déjalo tal cual):
FECHA: {context.get("date","")}
MI_TITULO: {context.get("my_poem_title","")}
POETA: {context.get("poet","")}
POEMA_CITADO: {context.get("poem_title","")}

ANALISIS:
{analysis_text}
""".strip()

    resp = client.responses.create(
        model=MODEL,
        input=prompt,
        text={"format": {"type": "json_object"}},
    )

    data = json.loads(resp.output_text)
    kws = data.get("keywords", [])
    if not isinstance(kws, list):
        return []
    kws = enforce_keyword_rules(kws)
    kws = redistribute_weights(kws)
    return kws


# ---------- JSON UPDATE ----------
def load_entries(path: Path) -> List[dict]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"{path} no contiene una lista JSON en la raíz.")
    return data

def sort_entries_desc(entries: List[dict]) -> List[dict]:
    return sorted(entries, key=lambda e: e.get("date", ""), reverse=True)

def build_entry(meta: dict, txt_relpath: str, keywords: List[dict]) -> dict:
    date = meta.get("date", "").strip()
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", date):
        raise ValueError(f"FECHA inválida o ausente: '{date}' (esperado YYYY-MM-DD). "
                         f"Tip: nombra el archivo como YYYY-MM-DD.txt o agrega 'FECHA: YYYY-MM-DD' arriba.")

    return {
        "date": date,
        "month": date[:7],
        "file": txt_relpath,
        "my_poem_title": meta.get("my_poem_title", "").strip(),
        "my_poem_snippet": meta.get("my_poem_snippet", "").strip(),
        "analysis": {
            "poet": meta.get("poet", "").strip(),
            "poem_title": meta.get("poem_title", "").strip(),
            "poem_snippet": meta.get("poem_snippet", "").strip(),
            "book_title": meta.get("book_title", "").strip(),
        },
        "keywords": keywords,
    }

def warn_missing(meta: dict):
    missing = []
    for k in ["my_poem_title", "poet", "poem_title"]:
        if not meta.get(k, "").strip():
            missing.append(k)
    if missing:
        print("⚠️  Aviso: faltan metadatos:", ", ".join(missing))
        print("    Puedes añadirlos arriba del archivo .txt como 'CLAVE: valor' (sin cambiar tus headers #),")
        print("    o pasarlos por flags: --my-poem-title, --poeta, --poem-title.\n")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("txt", help="Ruta al .txt (ej: textos/2025-12-24.txt)")
    ap.add_argument("--fecha", help="Override FECHA (YYYY-MM-DD)")
    ap.add_argument("--poeta", help="Override POETA (analysis.poet)")
    ap.add_argument("--poem-title", help="Override POEM_TITLE (analysis.poem_title)")
    ap.add_argument("--book-title", help="Override BOOK_TITLE (analysis.book_title)")
    ap.add_argument("--my-poem-title", help="Override MY_POEM_TITLE (my_poem_title)")
    ap.add_argument("--my-poem-snippet", help="Override MY_POEM_SNIPPET (my_poem_snippet)")
    ap.add_argument("--poem-snippet", help="Override POEM_SNIPPET (analysis.poem_snippet)")
    args = ap.parse_args()

    txt_path = (REPO_ROOT / args.txt).resolve()
    if not txt_path.exists():
        print(f"No existe: {txt_path}", file=sys.stderr)
        sys.exit(1)

    meta, sections = parse_txt(txt_path)

    # overrides desde CLI
    if args.fecha: meta["date"] = args.fecha
    if args.poeta: meta["poet"] = args.poeta
    if args.poem_title: meta["poem_title"] = args.poem_title
    if args.book_title: meta["book_title"] = args.book_title
    if args.my_poem_title: meta["my_poem_title"] = args.my_poem_title
    if args.my_poem_snippet: meta["my_poem_snippet"] = args.my_poem_snippet
    if args.poem_snippet: meta["poem_snippet"] = args.poem_snippet

    analysis_text = sections.get("TEXTO", "")
    if not analysis_text.strip():
        raise ValueError("No encuentro contenido bajo '# TEXTO' (tu análisis).")

    warn_missing(meta)

    keywords = call_openai_keywords(analysis_text, meta)

    txt_relpath = str(txt_path.relative_to(REPO_ROOT)).replace("\\", "/")
    entry = build_entry(meta, txt_relpath, keywords)

    entries = load_entries(JSON_PATH)
    if any(e.get("date") == entry["date"] for e in entries):
        raise ValueError(f"Ya existe una entrada con date={entry['date']} en {JSON_PATH}")

    entries.append(entry)
    entries = sort_entries_desc(entries)

    JSON_PATH.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"OK: añadida entrada {entry['date']} a {JSON_PATH}")
    top = [k["word"] for k in entry["keywords"] if k["weight"] == 3][:5]
    print("Top keywords (w=3):", ", ".join(top))
    print("Total keywords:", len(entry["keywords"]))

if __name__ == "__main__":
    main()
