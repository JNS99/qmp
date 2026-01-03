#!/usr/bin/env bash
set -euo pipefail

# qk YYYY-MM-DD
# Genera sugerencias de keywords en scripts/pending_keywords.txt
# No toca git. No toca archivo.json.

DATE="${1:-}"

if [[ -z "${DATE}" ]]; then
  echo "[qk] Uso: qk YYYY-MM-DD" >&2
  exit 2
fi

# Validación simple de fecha
if ! [[ "${DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "[qk] Fecha inválida: ${DATE} (usa YYYY-MM-DD)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IN_FILE="${ROOT_DIR}/textos/${DATE}.txt"
OUT_FILE="${ROOT_DIR}/scripts/pending_keywords.txt"
PY_SCRIPT="${ROOT_DIR}/scripts/gen_keywords.py"

if [[ ! -f "${IN_FILE}" ]]; then
  echo "[qk] No existe: ${IN_FILE}" >&2
  exit 1
fi

if [[ ! -f "${PY_SCRIPT}" ]]; then
  echo "[qk] No existe: ${PY_SCRIPT}" >&2
  exit 1
fi

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "[qk] Falta GEMINI_API_KEY en el entorno." >&2
  echo "     Ejemplo: export GEMINI_API_KEY='...'" >&2
  exit 1
fi

python3 "${PY_SCRIPT}" --input "${IN_FILE}" --output "${OUT_FILE}"

echo "[qk] Revisa/edita: ${OUT_FILE}"
