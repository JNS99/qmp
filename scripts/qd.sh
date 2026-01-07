#!/usr/bin/env zsh
# QMP — qd (zsh-only)
# Contract:
# - qd [YYYY-MM-DD]
#   - 0 args: propose NEXT_DATE (max_date + 1 day) from archivo.json, ask (y/N)
#   - 1 arg: validate date; if new and not NEXT_DATE -> ask (y/N)
# - Always regenerates scripts/current_keywords.txt from archivo.json (snapshot)
# - NEVER touches scripts/pending_keywords.txt
# - Opens files with TXT focused (VS Code/Sublime supported)

set -e
set -u
setopt pipefail

# -------------------------
# Helpers
# -------------------------
die() { print -u2 -- "[qd] $*"; exit 1; }

confirm_yn() {
  # Default = NO (Enter -> no)
  local prompt="$1"
  local ans
  print -n -u2 -- "$prompt (y/N) "
  read ans || true
  ans="${${ans:-}:l}"
  case "$ans" in
    y|yes|s|si|sí) return 0 ;;
    *) return 1 ;;
  esac
}

# -------------------------
# Repo / env
# -------------------------
[[ -n "${QMP_REPO:-}" ]] || die "QMP_REPO no está definido. ¿sourceaste qmp_shell.zsh?"
cd "$QMP_REPO" || die "No puedo entrar a QMP_REPO=$QMP_REPO"

local PYTHON="$QMP_REPO/.venv/bin/python"
[[ -x "$PYTHON" ]] || die "No existe Python del proyecto: $PYTHON (crea .venv en este entorno)"

local ARCHIVO="archivo.json"
local TEMPLATE="textos/templateTEXT.txt"
local PULL="scripts/pull_keywords.py"
[[ -f "$ARCHIVO" ]] || die "Falta $ARCHIVO"
[[ -f "$TEMPLATE" ]] || die "Falta $TEMPLATE"
[[ -f "$PULL" ]] || die "Falta $PULL"

# -------------------------
# Args (0 or 1)
# -------------------------
local DATE=""
if (( $# == 0 )); then
  DATE=""
elif (( $# == 1 )); then
  DATE="$1"
else
  die "Uso: qd [YYYY-MM-DD]  (0 o 1 argumento solamente)"
fi

# -------------------------
# Read min/max/next (may be empty if archivo.json has no entries)
# -------------------------
local MIN_DATE="" MAX_DATE="" NEXT_DATE=""
{
  local out
  out="$("$PYTHON" - <<'PY' 2>/dev/null
import json
from datetime import date, timedelta

data = json.load(open("archivo.json", encoding="utf-8"))
entries = data["entries"] if isinstance(data, dict) and isinstance(data.get("entries"), list) else data
if not isinstance(entries, list):
    print("", "", "")
    raise SystemExit(0)

dates = sorted({e.get("date","") for e in entries if isinstance(e, dict) and e.get("date")})
if not dates:
    print("", "", "")
    raise SystemExit(0)

min_d = dates[0]
max_d = dates[-1]
y,m,d = map(int, max_d.split("-"))
next_d = (date(y,m,d) + timedelta(days=1)).isoformat()
print(min_d, max_d, next_d)
PY
)"
  MIN_DATE="${out%% *}"
  out="${out#* }"
  MAX_DATE="${out%% *}"
  NEXT_DATE="${out#* }"
} || true

# If archivo.json empty and no DATE provided -> must be explicit
if [[ -z "$MIN_DATE" || -z "$MAX_DATE" || -z "$NEXT_DATE" ]]; then
  if [[ -z "$DATE" ]]; then
    die "archivo.json no tiene entradas. Usa: qd YYYY-MM-DD"
  fi
fi

# -------------------------
# If no DATE: propose NEXT_DATE with confirmation
# -------------------------
if [[ -z "$DATE" ]]; then
  confirm_yn "¿Crear/abrir entrada para $NEXT_DATE?" || exit 0
  DATE="$NEXT_DATE"
fi

# -------------------------
# Validate date format + real date (silent)
# -------------------------
[[ "$DATE" == <->-<->-<-> ]] || die "Fecha inválida: $DATE (usa YYYY-MM-DD)"

# Real calendar date validation (no traceback)
if ! "$PYTHON" - "$DATE" >/dev/null 2>&1 <<'PY'
from datetime import date
import sys
try:
    date.fromisoformat(sys.argv[1])
except Exception:
    raise SystemExit(1)
PY
then
  die "Fecha inválida (no existe): $DATE"
fi

# Reject dates earlier than earliest published
if [[ -n "$MIN_DATE" && "$DATE" < "$MIN_DATE" ]]; then
  die "Fecha $DATE es anterior a la primera fecha publicada ($MIN_DATE)"
fi

# -------------------------
# Determine if entry exists
# -------------------------
local EXISTS="0"
EXISTS="$("$PYTHON" - "$DATE" <<'PY' 2>/dev/null
import json, sys
date_str = sys.argv[1]
data = json.load(open("archivo.json", encoding="utf-8"))
entries = data["entries"] if isinstance(data, dict) and isinstance(data.get("entries"), list) else data
if not isinstance(entries, list):
    print("0"); raise SystemExit(0)
print("1" if any(isinstance(e, dict) and e.get("date")==date_str for e in entries) else "0")
PY
)" || EXISTS="0"

# Non-strict confirmation: new date but not NEXT_DATE
if [[ "$EXISTS" == "0" && -n "${NEXT_DATE:-}" && "$DATE" != "$NEXT_DATE" ]]; then
  confirm_yn "Fecha no esperada (siguiente: $NEXT_DATE). ¿Continuar igual?" || exit 0
fi

# -------------------------
# Paths for this date
# -------------------------
local TXT="textos/${DATE}.txt"
local CURRENT="scripts/current_keywords.txt"
local PENDING="scripts/pending_keywords.txt"

# Ensure txt exists
# Ensure txt exists
if [[ ! -f "$TXT" ]]; then
  cp "$TEMPLATE" "$TXT"
fi

# Si aún queda el placeholder {{DATE}}, reemplazarlo (idempotente)
if grep -q '{{DATE}}' "$TXT"; then
  "$PYTHON" - "$DATE" "$TXT" >/dev/null 2>&1 <<'PY' || true
import sys, pathlib
date_str = sys.argv[1]
p = pathlib.Path(sys.argv[2])
t = p.read_text(encoding="utf-8")
t2 = t.replace("{{DATE}}", date_str)
if t2 != t:
    p.write_text(t2, encoding="utf-8")
PY
fi



# Regenerate current (snapshot). NEVER touch pending.
if ! "$PYTHON" "$PULL" "$DATE" "$CURRENT" >/dev/null 2>&1; then
  cat > "$CURRENT" <<EOF
{
  "date": "$DATE",
  "keywords": []
}
EOF
fi

# -------------------------
# Open files (TXT focused)
# -------------------------
# Determine editor
local -a CMD
if [[ -n "${EDITOR_CMD:-}" ]]; then
  # NOTE: prefer EDITOR (single command); EDITOR_CMD may contain spaces.
  CMD=(${=EDITOR_CMD})
elif [[ -n "${EDITOR:-}" ]]; then
  CMD=(${=EDITOR})
elif command -v code >/dev/null 2>&1; then
  CMD=(code)
elif command -v subl >/dev/null 2>&1; then
  CMD=(subl)
else
  die "No encuentro editor. Define EDITOR o EDITOR_CMD."
fi

if [[ "${CMD[1]}" == "code" ]]; then
  code -r "$CURRENT" "$PENDING" "$ARCHIVO" "$TXT"
  code -r -g "$TXT"
elif [[ "${CMD[1]}" == "subl" ]]; then
  subl -a "$CURRENT" "$PENDING" "$ARCHIVO" "$TXT"
else
  "${CMD[@]}" "$CURRENT" "$PENDING" "$ARCHIVO" "$TXT"
  "${CMD[@]}" "$TXT" >/dev/null 2>&1 || true
fi
