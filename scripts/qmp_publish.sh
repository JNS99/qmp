#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/qmp_publish.sh [--dry-run|--dry|-n] textos/YYYY-MM-DD.txt ["mensaje commit opcional"]

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "--dry" || "${1:-}" == "-n" ]]; then
  DRY_RUN=1
  shift
fi

TXT_PATH="${1:-}"
COMMIT_MSG="${2:-}"

# Repo root basado en la ubicación del script (funciona desde cualquier directorio)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d ".git" ]]; then
  echo "Error: $REPO_ROOT no parece ser un repo git (no hay .git)."
  exit 1
fi

if [[ -z "$TXT_PATH" ]]; then
  echo "Uso: scripts/qmp_publish.sh [--dry-run] textos/YYYY-MM-DD.txt \"Mensaje opcional\""
  exit 2
fi

if [[ ! -f "$TXT_PATH" ]]; then
  echo "Error: no existe $TXT_PATH"
  exit 1
fi

[[ -f "scripts/make_pending_entry.py" ]] || { echo "Error: falta scripts/make_pending_entry.py"; exit 1; }
[[ -f "scripts/merge_pending.py" ]] || { echo "Error: falta scripts/merge_pending.py"; exit 1; }
[[ -f "scripts/pending_keywords.txt" ]] || { echo "Error: falta scripts/pending_keywords.txt"; exit 1; }
[[ -f "archivo.json" ]] || { echo "Error: falta archivo.json en el root del repo"; exit 1; }

# Sanity: txt has # TEXTO
if ! grep -qE '^\s*#\s*TEXTO\s*$' "$TXT_PATH"; then
  echo "Error: $TXT_PATH no contiene el header '# TEXTO'."
  exit 1
fi

echo "→ Generando pending_entry.json desde $TXT_PATH"
python3 scripts/make_pending_entry.py "$TXT_PATH"

[[ -f "scripts/pending_entry.json" ]] || { echo "Error: no se generó scripts/pending_entry.json"; exit 1; }

ENTRY_DATE="$(python3 - <<'PY'
import json
d=json.load(open("scripts/pending_entry.json","r",encoding="utf-8"))
print((d.get("date") or "").strip())
PY
)"
if [[ -z "$ENTRY_DATE" ]]; then
  echo "Error: pending_entry.json no tiene 'date'."
  exit 1
fi

# ¿Existe ya la fecha?
EXISTS="$(python3 - "$ENTRY_DATE" <<'PY'
import json, sys
entry_date = sys.argv[1]
d = json.load(open("archivo.json","r",encoding="utf-8"))
print("1" if any(e.get("date")==entry_date for e in d) else "0")
PY
)"

ACTION_WORD="Entrada"
if [[ "$EXISTS" == "1" ]]; then
  ACTION_WORD="Edición"
fi

echo "→ Merge keywords + upsert en archivo.json"
if [[ "$DRY_RUN" == "1" ]]; then
  python3 scripts/merge_pending.py --dry-run
else
  python3 scripts/merge_pending.py
fi

echo "→ Validando JSON..."
python3 -m json.tool archivo.json >/dev/null
python3 -m json.tool scripts/pending_entry.json >/dev/null

KW_COUNT="$(python3 - <<'PY'
import json
d=json.load(open("scripts/pending_entry.json","r",encoding="utf-8"))
print(len(d.get("keywords",[]) or []))
PY
)"
if [[ "$KW_COUNT" -lt 10 ]]; then
  echo "Error: keywords muy pocas (${KW_COUNT}). No hago commit/push."
  exit 1
fi

# Commit semántico si no se pasó mensaje
if [[ -z "$COMMIT_MSG" ]]; then
  TITLE="$(python3 - <<'PY'
import json
try:
    d=json.load(open("scripts/pending_entry.json","r",encoding="utf-8"))
    t=(d.get("my_poem_title") or "").strip()
    if not t:
        t=(d.get("my_poem_snippet") or "").strip()
    t=" ".join(t.split())
    print(t)
except Exception:
    print("")
PY
)"
  TITLE="${TITLE:0:80}"

  if [[ -n "$TITLE" ]]; then
    COMMIT_MSG="${ACTION_WORD} ${ENTRY_DATE} — ${TITLE}"
  else
    COMMIT_MSG="${ACTION_WORD} ${ENTRY_DATE}"
  fi
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN: no hago commit ni push."
  echo "Mensaje commit sería: $COMMIT_MSG"
  exit 0
fi

# → Append log (solo si NO es dry-run; y solo si hubo cambios reales)
mkdir -p logs
python3 - <<PY
import json, datetime, pathlib

entry = json.load(open("scripts/pending_entry.json","r",encoding="utf-8"))

date = (entry.get("date") or "").strip()
title = (entry.get("my_poem_title") or "").strip() or (entry.get("my_poem_snippet") or "").strip()
kw_count = len(entry.get("keywords") or [])

log_line = {
  "date": date,
  "file": "${TXT_PATH}",
  "title": " ".join(title.split())[:120],
  "keywords": kw_count,
  "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z")
}

p = pathlib.Path("logs/publish_log.jsonl")
with p.open("a", encoding="utf-8") as f:
  f.write(json.dumps(log_line, ensure_ascii=False) + "\n")
PY

if [[ -z "$(git status --porcelain)" ]]; then
  echo "No hay cambios para commitear. Salgo."
  exit 0
fi

echo "→ Git add/commit/push"
git add archivo.json "$TXT_PATH" logs/publish_log.jsonl scripts/pending_entry.json scripts/pending_keywords.txt || true
git commit -m "$COMMIT_MSG"
git push

# Limpieza: borrar pending_entry (pending_keywords se queda)
rm -f scripts/pending_entry.json

echo "✅ Listo: publicado."
