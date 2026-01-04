#!/usr/bin/env bash
set -euo pipefail

DATE="${1:-$(date +%F)}"

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
TMP_OUT="/tmp/qmp_keywords_${DATE}.json"

if [[ ! -f "$IN_FILE" ]]; then
  echo "[qk] No encuentro ${IN_FILE}" >&2
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

# Generate keywords payload (expected: {"keywords":[...]} or [...] etc.)
TMP_GEN="$(mktemp)"
python3 "$GEN" "$IN_FILE" "$TMP_GEN"

# Wrap with date into scripts/pending_keywords.txt
python3 - "$DATE" "$TMP_GEN" "$OUT_ACTIVE" <<'PY'
import json, sys, pathlib

date = sys.argv[1]
src = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").strip()
out = pathlib.Path(sys.argv[3])

# accept array or object
data = json.loads(src)
if isinstance(data, dict) and "keywords" in data:
    kws = data["keywords"]
elif isinstance(data, list):
    kws = data
else:
    raise SystemExit("gen_keywords.py output format not recognized")

payload = {"date": date, "keywords": kws}
out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

rm -f "$TMP_GEN"

# Copy to /tmp view
cp "$OUT_ACTIVE" "$TMP_OUT"

echo "[qk] OK: ${OUT_ACTIVE}"
echo "[qk] Vista: ${TMP_OUT}"
