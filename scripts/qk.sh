#!/usr/bin/env bash
set -euo pipefail

# encontrar la raíz del repo
REPO_ROOT="$(git rev-parse --show-toplevel)"

# python del proyecto
PYTHON="$REPO_ROOT/.venv/bin/python"

if [ ! -x "$PYTHON" ]; then
  echo "❌ No existe .venv. Crea el entorno primero:"
  echo "   python3 -m venv .venv"
  echo "   pip install -r requirements.txt"
  exit 1
fi


DATE="${1:-}"
if [[ -z "$DATE" ]]; then
  echo "Uso: qk YYYY-MM-DD" >&2
  exit 1
fi
if ! [[ "${DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "[qk] Fecha inválida: ${DATE} (usa YYYY-MM-DD)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

IN_FILE="textos/${DATE}.txt"
GEN="scripts/gen_keywords.py"
OUT_ACTIVE="scripts/pending_keywords.txt"
TMP_OUT="$(mktemp)"

if [[ ! -f "$IN_FILE" ]]; then
  echo "[qk] No encuentro ${IN_FILE}. (Usa qd primero)" >&2
  exit 1
fi
if [[ ! -f "$GEN" ]]; then
  echo "[qk] No encuentro ${GEN}" >&2
  exit 1
fi
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "[qk] Falta OPENAI_API_KEY en el entorno." >&2
  exit 1
fi

# 1) generar keywords (a temp)
TMP_GEN="$(mktemp)"
"$PYTHON" "$GEN" "$IN_FILE" "$TMP_GEN"


# 2) envolver con date y validar no-vacío (a temp final)
"$PYTHON" - "$DATE" "$TMP_GEN" "$TMP_OUT" <<'PY'

import json, sys, pathlib

date = sys.argv[1]
src_path = pathlib.Path(sys.argv[2])
out_path = pathlib.Path(sys.argv[3])

data = json.loads(src_path.read_text(encoding="utf-8"))

if isinstance(data, dict) and "keywords" in data:
    kws = data["keywords"]
elif isinstance(data, list):
    kws = data
else:
    raise SystemExit("gen_keywords.py output format not recognized")

if not isinstance(kws, list) or len(kws) == 0:
    raise SystemExit("keywords vacías: abortando para no tocar pending_keywords.txt")

payload = {"date": date, "keywords": kws}
out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

rm -f "$TMP_GEN"

# 3) move atómico: sólo ahora tocamos pending_keywords.txt
mv "$TMP_OUT" "$OUT_ACTIVE"

echo "[qk] OK: ${OUT_ACTIVE}"
