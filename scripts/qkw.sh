#!/usr/bin/env bash
set -euo pipefail

DATE="${1:-}"
if [[ -z "$DATE" ]]; then
  echo "Uso: qkw YYYY-MM-DD" >&2
  exit 1
fi
if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "[qkw] Fecha inválida: $DATE (usa YYYY-MM-DD)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"

CURRENT="$REPO/scripts/current_keywords.txt"
PENDING="$REPO/scripts/pending_keywords.txt"

if [[ ! -f "$CURRENT" ]]; then
  echo "[qkw] No existe current_keywords.txt. Corre qd $DATE primero." >&2
  exit 1
fi

# Validar que current.date coincide (candado anti-cagadas)
CUR_DATE="$(python3 -c 'import json; import sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(d.get("date",""))' "$CURRENT")"
if [[ "$CUR_DATE" != "$DATE" ]]; then
  echo "[qkw] current_keywords.date ($CUR_DATE) != $DATE. Corre qd $DATE primero." >&2
  exit 1
fi

cp "$CURRENT" "$PENDING"
echo "[qkw] OK: pending_keywords.txt actualizado desde current_keywords.txt"
