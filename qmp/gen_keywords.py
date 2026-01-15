#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import re
import sys
import unicodedata
from openai import OpenAI

DEFAULT_INPUT_FILE = "test_file.txt"
DEFAULT_MODEL = os.getenv("OPENAI_MODEL", "gpt-5-mini")
MAX_KEYWORDS = 25
REASONING = os.getenv("OPENAI_REASONING", "medium")
MAX_TEXTO_CHARS = int(os.getenv("QMP_TEXTO_MAX_CHARS", "1800"))


INSTRUCTIONS = """
Eres un lector crítico de poesía y ensayo literario.
Tu tarea no es resumir ni describir textos, sino extraer núcleos conceptuales.

Recibirás un texto compuesto por hasta tres bloques:
- POEMA (núcleo semántico soberano)
- POEMA_CITADO (resonancia o contrapunto)
- TEXTO (lectura crítica; nunca fuente dominante)

REGLAS OBLIGATORIAS:

1. PRIORIDAD DEL POEMA  
El POEMA define el campo conceptual aunque sea breve.
El TEXTO solo puede articular, reforzar o afinar conceptos ya presentes,
directa o metafóricamente, en el POEMA.

2. PROHIBICIÓN DE LITERALIDAD CONCEPTUAL  
Palabras que designen objetos, acciones o situaciones literales
solo pueden aparecer con weight: 1.
Nunca pueden aparecer con weight: 3.

3. ABSTRACCIÓN FORZADA  
Las keywords con weight: 3 deben:
- ser conceptos abstractos
- explicar por qué ocurre algo, no qué ocurre
- justificar varias líneas o el gesto global del poema

4. INVERSIÓN POÉTICA  
Si el poema invierte un valor común
(ej.: vacío como potencia, daño como cuidado, silencio como acción),
esa inversión debe aparecer explícitamente en weight: 3.

5. EVITAR EMOCIONES GENÉRICAS  
No usar palabras vagas como “tristeza”, “calma”, “resiliencia”, “paciencia”,
salvo que estén conceptualmente trabajadas y sean estructurales.

6. ANCLAJE SIMBÓLICO  
Todo concepto abstracto debe poder rastrearse
en una operación corporal, material o lingüística del poema.

7. COHERENCIA DE CORPUS  
Mantén coherencia con un corpus que trabaja temas como:
cuerpo, poder, violencia, lenguaje, identidad, norma, deseo, vacío, incertidumbre.

DISTRIBUCIÓN DE PESOS:
- weight: 3 → núcleos conceptuales (máx. 6)
- weight: 2 → dinámicas, tensiones, procesos
- weight: 1 → campo semántico literal o figurativo

FORMATO DE SALIDA (OBLIGATORIO):
- Máximo 30 keywords, mínimo 10
- Minúsculas
- Sin acentos (o acentos indiferentes)
- Salida única en formato JSON exacto:

{
  "keywords": [
    { "word": "...", "weight": 3 },
    { "word": "...", "weight": 2 },
    { "word": "...", "weight": 1 }
  ]
}

RESTRICCIONES FINALES:
- No explicar
- No justificar
- No citar versos
- No incluir metadatos
- No repetir keywords con variaciones triviales

""".strip()

KEYWORDS_SCHEMA = {
    "name": "keywords_schema",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "keywords": {
                "type": "array",
                "minItems": 10,
                "maxItems": MAX_KEYWORDS,
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "word": {"type": "string", "minLength": 1, "maxLength": 80},
                        "weight": {"type": "integer", "enum": [1, 2, 3]},
                    },
                    "required": ["word", "weight"],
                },
            }
        },
        "required": ["keywords"],
    },
}

def strip_leading_metadata(raw: str) -> str:
    lines = raw.splitlines()
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s == "":
            i += 1
            continue
        if s.startswith("#"):
            break
        if ":" in s:
            key = s.split(":", 1)[0].strip()
            if key and key.replace("_", "").isupper():
                i += 1
                continue
        break
    return "\n".join(lines[i:]).lstrip("\n")

def strip_accents(s: str) -> str:
    return "".join(ch for ch in unicodedata.normalize("NFKD", s) if not unicodedata.combining(ch))

def normalize_word(w: str) -> str:
    w = " ".join(w.strip().lower().split())
    w = w.replace("_", " ")
    w = strip_accents(w)
    w = re.sub(r"[.,;:]+$", "", w).strip()
    return w

def trim_text_block(text: str) -> str:
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]

    if len(paragraphs) <= 3:
        return text.strip()

    return paragraphs[0] + "\n\n" + paragraphs[-1]


def trim_texto_section(full_text: str, max_chars: int = 1800) -> str:
    """
    If the input contains a '# TEXTO' section, reduce its token footprint:
      - If TEXTO has >3 paragraphs, keep only first + last paragraph.
      - Optionally cap to max_chars characters (soft cut).
    Other sections remain unchanged.
    """
    # Split by markdown-style headers: "# POEMA", "# POEMA_CITADO", "# TEXTO"
    header_re = re.compile(r"(?m)^(#\s*(POEMA|POEMA_CITADO|TEXTO)\s*)$", re.UNICODE)

    parts = []
    last = 0
    matches = list(header_re.finditer(full_text))
    if not matches:
        return full_text.strip()

    # Build list of (header, body) segments
    segments = []
    for idx, m in enumerate(matches):
        header_start = m.start()
        header_end = m.end()
        if idx == 0 and header_start > 0:
            # preamble before first header (keep as-is)
            pre = full_text[:header_start].rstrip()
            if pre:
                segments.append((None, pre))
        next_start = matches[idx + 1].start() if idx + 1 < len(matches) else len(full_text)
        header_line = m.group(1).rstrip()
        body = full_text[header_end:next_start].strip("\n")
        segments.append((header_line, body))

    out_segments = []
    for header, body in segments:
        if header is None:
            out_segments.append(body.strip())
            continue

        if re.search(r"(?i)^#\s*TEXTO\b", header):
            trimmed = trim_text_block(body)
            trimmed = trimmed.strip()
            if max_chars and len(trimmed) > max_chars:
                trimmed = trimmed[:max_chars].rstrip()
            out_segments.append(header.rstrip() + "\n\n" + trimmed)
        else:
            out_segments.append(header.rstrip() + ("\n\n" + body.strip() if body.strip() else ""))

    return "\n\n".join([s for s in out_segments if s.strip()]).strip()


def extract_output_text(resp) -> str:
    """
    Prefer resp.output_text (SDK helper). Fallback to traversing resp.output blocks.
    """
    ot = getattr(resp, "output_text", None)
    if isinstance(ot, str) and ot.strip():
        return ot.strip()

    parts = []
    output = getattr(resp, "output", None)
    if output:
        for item in output:
            content = getattr(item, "content", None)
            if not content:
                continue
            for c in content:
                # different SDK versions name these slightly differently
                ctype = getattr(c, "type", None)
                text = getattr(c, "text", None)
                if isinstance(text, str) and text.strip():
                    parts.append(text)
    return "\n".join(parts).strip()

def print_usage(resp):
    u = getattr(resp, "usage", None)
    if not u:
        return
    msg = (
        f"input_tokens={getattr(u,'input_tokens',None)} "
        f"output_tokens={getattr(u,'output_tokens',None)} "
        f"total_tokens={getattr(u,'total_tokens',None)}"
    )
    details = getattr(u, "input_tokens_details", None)
    if details and hasattr(details, "cached_tokens"):
        msg += f" cached_tokens={details.cached_tokens}"
    print(msg, file=sys.stderr)

def main() -> int:
    in_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INPUT_FILE
    out_path = sys.argv[2] if len(sys.argv) > 2 else None

    with open(in_path, "r", encoding="utf-8") as f:
        raw_text = f.read()

    text = strip_leading_metadata(raw_text).strip()
    text = trim_texto_section(text, MAX_TEXTO_CHARS)


    client = OpenAI()
    resp = client.responses.create(
        model=DEFAULT_MODEL,
        reasoning={"effort": REASONING},
        max_output_tokens=4000,
        input=[
            {"role": "system", "content": "Responde SOLO con JSON válido según el schema. Sin explicaciones."},
            {"role": "user", "content": INSTRUCTIONS + "\n\n---\n\nTEXTO COMPLETO:\n" + text},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": KEYWORDS_SCHEMA["name"],
                "schema": KEYWORDS_SCHEMA["schema"],
                "strict": True,
            }
        },
    )

    print_usage(resp)

    out_text = extract_output_text(resp)
    if not out_text:
        # Debug minimal: show what the API returned structurally
        print("ERROR: respuesta sin texto. Dump de resp.output (resumido):", file=sys.stderr)
        try:
            print(json.dumps(resp.model_dump(), ensure_ascii=False)[:2000], file=sys.stderr)
        except Exception:
            print(str(resp)[:2000], file=sys.stderr)
        return 1

    try:
        data = json.loads(out_text)
    except json.JSONDecodeError:
        print("ERROR: el modelo no devolvió JSON válido. Primera parte del output:", file=sys.stderr)
        print(out_text[:400], file=sys.stderr)
        return 1

    # normalize + dedupe
    seen = set()
    cleaned = []
    for kw in data["keywords"]:
        word = normalize_word(kw["word"])
        if not word or word in seen:
            continue
        seen.add(word)
        cleaned.append({"word": word, "weight": int(kw["weight"])})

    out = {"keywords": cleaned[:MAX_KEYWORDS]}

    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
    else:
        print(json.dumps(out, ensure_ascii=False, indent=2))

    return 0

if __name__ == "__main__":
    raise SystemExit(main())