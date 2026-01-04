#!/usr/bin/env bash
set -e

DATE="$1"
if [[ -z "$DATE" ]]; then
  echo "Uso: qd YYYY-MM-DD"
  exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TXT="$REPO/textos/$DATE.txt"
TEMPLATE="$REPO/textos/templateTEXT.txt"
ARCHIVO="$REPO/archivo.json"
PENDING="$REPO/scripts/pending_keywords.txt"

# crear txt si no existe
if [[ ! -f "$TXT" ]]; then
  cp "$TEMPLATE" "$TXT"
fi

# si la entrada existe, restaurar keywords reales
if jq -e --arg d "$DATE" '.entries[]? | select(.date==$d)' "$ARCHIVO" > /dev/null; then
  jq --arg d "$DATE" '
    .entries[] | select(.date==$d) | {keywords: .keywords}
  ' "$ARCHIVO" > "$PENDING"
fi

# abrir editor (Sublime)
EDITOR_CMD="${EDITOR_CMD:-${EDITOR:-subl}}"
"$EDITOR_CMD" -a "$ARCHIVO" "$PENDING" "$TXT"
