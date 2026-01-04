#!/usr/bin/env bash
set -e

DRY=""
APPLY_KW=0
TXT=""

for arg in "$@"; do
  case "$arg" in
    --dry-run|--dry|-n) DRY="--dry-run" ;;
    --kw) APPLY_KW=1 ;;
    *.txt) TXT="$arg" ;;
  esac
done

if [[ -z "$TXT" ]]; then
  echo "Uso: q [--dry-run] [--kw] textos/YYYY-MM-DD.txt"
  exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

OUT="$(python3 scripts/merge_pending.py "$TXT" $DRY $( [[ "$APPLY_KW" == "1" ]] && echo "--apply-keywords" ))"
echo "$OUT"

STATUS_LINE="$(echo "$OUT" | awk -F= '/^STATUS_JSON=/{print $2}')"
if [[ -z "$STATUS_LINE" ]]; then
  echo "❌ merge_pending.py no emitió STATUS_JSON"
  exit 1
fi

DATE="$(echo "$STATUS_LINE" | jq -r '.date')"
EXISTS="$(echo "$STATUS_LINE" | jq -r '.exists_before')"
CONTENT_CHANGED="$(echo "$STATUS_LINE" | jq -r '.content_changed')"
KW_CHANGED="$(echo "$STATUS_LINE" | jq -r '.keywords_changed')"
TITLE="$(echo "$STATUS_LINE" | jq -r '.title')"
SNIPPET="$(echo "$STATUS_LINE" | jq -r '.snippet')"

LABEL="$TITLE"
[[ -z "$LABEL" ]] && LABEL="$SNIPPET"

BASE=""
if [[ "$EXISTS" == "false" ]]; then
  BASE="entrada"
elif [[ "$CONTENT_CHANGED" == "true" && "$KW_CHANGED" == "true" ]]; then
  BASE="edicion texto + keywords"
elif [[ "$KW_CHANGED" == "true" ]]; then
  BASE="edicion de palabras clave"
elif [[ "$CONTENT_CHANGED" == "true" ]]; then
  BASE="edicion de metadatos/escritos"
else
  echo "ℹ️ No hay cambios reales. Abortando."
  exit 0
fi

MSG="$BASE $DATE — $LABEL"

if [[ -n "$DRY" ]]; then
  echo "OK (dry-run): $MSG"
  exit 0
fi

# ---------- aplicar pending_entry.json ----------
python3 - <<'PY'
import json
from pathlib import Path

repo = Path(".")
data = json.loads((repo/"archivo.json").read_text(encoding="utf-8"))
entries = data.get("entries", []) if isinstance(data, dict) else data

pending = json.loads((repo/"scripts/pending_entry.json").read_text(encoding="utf-8"))
date = pending["date"]

entries = [e for e in entries if e.get("date") != date]
entries.append(pending)
entries.sort(key=lambda e: e.get("date",""), reverse=True)

(repo/"archivo.json").write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "
", encoding="utf-8")
PY

git add archivo.json
git commit -m "$MSG"
git push

echo "✅ Publicado: $MSG"
