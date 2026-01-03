#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import datetime as dt
import json
import os
import re
import sys
import unicodedata
from pathlib import Path

from google import genai
from google.genai import types

SYSTEM_PROMPT = """
Integra los tres bloques juntos (POEMA, POEMA_CITADO, TEXTO), con esta prioridad semántica:
1) POEMA = núcleo conceptual soberano
2) POEMA_CITADO = resonancia
3) TEXTO (análisis) = lente de lectura, no fuente dominante

REGLAS DE SALIDA:
- Devuelve SOLO JSON.
- Formato permitido (elige uno):
  A) [{"word":"...", "weight":3}, ...]
  B) {"keywords":[{"word":"...", "weight":3}, ...]}
- Máximo 30 keywords.
- Minúsculas, sin acentos.
- Pesos: 3 (núcleo), 2 (tensiones), 1 (campo semántico).
- No expliques nada.
""".strip()


def die(msg: str, code: int = 1) -> None:
    print(f"[qk] {msg}", file=sys.stderr)
    raise SystemExit(code)


def strip_accents(s: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", s)
        if unicodedata.category(c) != "Mn"
    )


def normalize_word(s: str) -> str:
    s = (s or "").strip().lower()
    s = strip_accents(s)
    s = re.sub(r"\s+", " ", s)
    return s


def clamp_weight(w) -> int:
    try:
        w = int(w)
    except Exception:
        w = 1
    return 3 if w > 3 else 1 if w < 1 else w


def parse_keywords_json(text: str):
    """
    Acepta:
      - [{"word": "...", "weight": 3}, ...]
      - {"keywords": [...]}
    Devuelve lista de dicts.
    """
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        # A veces el modelo devuelve espacios extra o fences; intentamos recortar.
        t = text.strip()
        # intenta extraer el primer bloque JSON
        m = re.search(r"(\{.*\}|\[.*\])", t, flags=re.DOTALL)
        if m:
            data = json.loads(m.group(1))
        else:
            raise e

    if isinstance(data, dict) and "keywords" in data:
        data = data["keywords"]

    if not isinstance(data, list):
        die("La respuesta JSON no es una lista de keywords.")

    cleaned = []
    for item in data:
        if not isinstance(item, dict):
            continue
        word = normalize_word(str(item.get("word", "")))
        if not word:
            continue
        weight = clamp_weight(item.get("weight", 1))
        cleaned.append({"word": word, "weight": weight})

    return cleaned


def dedupe_keep_best(keywords):
    """
    Si hay repetidos, nos quedamos con el peso más alto.
    Conserva un orden razonable (primera aparición).
    """
    seen = {}
    order = []
    for k in keywords:
        w = k["word"]
        if w not in seen:
            seen[w] = k["weight"]
            order.append(w)
        else:
            seen[w] = max(seen[w], k["weight"])

    out = [{"word": w, "weight": seen[w]} for w in order]
    # opcional: ordenar por peso desc, y luego alfabético, pero mantengo orden editorial
    return out


def backup_file(path: Path) -> None:
    if not path.exists():
        return
    ts = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    bak = path.with_name(path.name + f".bak-{ts}")
    bak.write_bytes(path.read_bytes())


def main():
    ap = argparse.ArgumentParser(description="Genera keywords sugeridas para QMP.")
    ap.add_argument("--input", required=True, help="Ruta a textos/YYYY-MM-DD.txt")
    ap.add_argument("--output", required=True, help="Ruta a scripts/pending_keywords.txt")
    ap.add_argument("--model", default="gemini-2.5-flash", help="Modelo Gemini (default: gemini-2.5-flash)")
    args = ap.parse_args()

    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not api_key:
        die("Falta GEMINI_API_KEY en el entorno (export GEMINI_API_KEY='...').")

    in_path = Path(args.input)
    out_path = Path(args.output)

    if not in_path.exists():
        die(f"No existe el archivo de entrada: {in_path}")

    text = in_path.read_text(encoding="utf-8").strip()
    if not text:
        die("El archivo de texto está vacío.")

    client = genai.Client(api_key=api_key)

    try:
        resp = client.models.generate_content(
            model=args.model,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                response_mime_type="application/json",
                temperature=0.2,
            ),
            contents=text,
        )
    except Exception as e:
        die(f"Error llamando la API: {e}")

    raw = (resp.text or "").strip()
    if not raw:
        die("La API devolvió una respuesta vacía.")

    try:
        kws = parse_keywords_json(raw)
    except Exception as e:
        die(f"No pude parsear el JSON devuelto: {e}\n---\nRAW:\n{raw}\n---")

    kws = dedupe_keep_best(kws)
    kws = kws[:30]  # máximo 30

    # backup y escritura
    out_path.parent.mkdir(parents=True, exist_ok=True)
    backup_file(out_path)

    out_path.write_text(json.dumps(kws, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"[qk] OK → {out_path} ({len(kws)} keywords)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
