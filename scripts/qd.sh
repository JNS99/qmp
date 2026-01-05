#!/usr/bin/env bash
set -euo pipefail

DATE="${1:-}"
if [[ -z "$DATE" ]]; then
  echo "Uso: qd YYYY-MM-DD" >&2
  exit 1
fi
if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "[qd] Fecha inválida: $DATE (usa YYYY-MM-DD)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"

TXT="$REPO/textos/${DATE}.txt"
TEMPLATE="$REPO/textos/templateTEXT.txt"
ARCHIVO="$REPO/archivo.json"

CURRENT="$REPO/scripts/current_keywords.txt"
PENDING="$REPO/scripts/pending_keywords.txt"

PULL="$REPO/scripts/pull_keywords.py"

# crear txt si no existe
if [[ ! -f "$TXT" ]]; then
  if [[ ! -f "$TEMPLATE" ]]; then
    echo "[qd] No encuentro template: $TEMPLATE" >&2
    exit 1
  fi
  cp "$TEMPLATE" "$TXT"
fi

# Regenerar current_keywords desde archivo.json (snapshot).
# Si no existe entry, current queda vacío (pero con date).
if [[ -f "$ARCHIVO" && -f "$PULL" ]]; then
  if python3 "$PULL" "$DATE" "$CURRENT" >/dev/null 2>&1; then
    :
  else
    # entry no existe => current vacío para simplicidad
    cat > "$CURRENT" <<EOF
{
  "date": "$DATE",
  "keywords": []
}
EOF
  fi
else
  # fallback mínimo
  cat > "$CURRENT" <<EOF
{
  "date": "$DATE",
  "keywords": []
}
EOF
fi

# elegir editor
if [[ -n "${EDITOR_CMD:-}" ]]; then
  CMD=("$EDITOR_CMD")
elif [[ -n "${EDITOR:-}" ]]; then
  CMD=("$EDITOR")
elif command -v subl >/dev/null 2>&1; then
  CMD=(subl)
elif command -v code >/dev/null 2>&1; then
  CMD=(code)
else
  echo "[qd] No encuentro editor. Define EDITOR_CMD o EDITOR." >&2
  exit 1
fi

# abrir (IMPORTANTE: pending se abre pero NO se toca)
if [[ "${CMD[0]}" == "subl" ]]; then
  "${CMD[@]}" -a "$TXT" "$CURRENT" "$PENDING" "$ARCHIVO"
elif [[ "${CMD[0]}" == "code" ]]; then
  "${CMD[@]}" -r "$TXT" "$CURRENT" "$PENDING" "$ARCHIVO"
else
  "${CMD[@]}" "$TXT" "$CURRENT" "$PENDING" "$ARCHIVO"
fi
