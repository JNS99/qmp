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
die() { print -u2 -- "[qd] ERROR: $*"; exit 1; }

warn() { print -u2 -- "[qd] WARN: $*"; }

confirm_yn() {
  # Default = NO (Enter -> no)
  local prompt="$1"
  local ans
  print -n -u2 -- "[qd] $prompt [y/N]: "
  read ans || true
  ans="${${ans:-}:l}"
  case "$ans" in
    y|yes|s|si|sí) return 0 ;;
    *) return 1 ;;
  esac
}


txt_path_for_date() {
  local d="$1"
  local y="${d[1,4]}"
  local m="${d[6,7]}"

  local p_new="${QMP_TEXTOS}/${y}/${m}/${d}.txt"
  local p_old="${QMP_TEXTOS}/${d}.txt"

  # Prefer new layout. Only fall back to old layout if it exists and new doesn't.
  if [[ -f "$p_old" && ! -f "$p_new" ]]; then
    print -r -- "$p_old"
  else
    print -r -- "$p_new"
  fi
}

lint_template() {
  local tpl="$1"
  [[ -f "$tpl" ]] || die "Template no existe: $tpl"

  # Essential: FECHA line and placeholder
  if ! grep -qE '^FECHA:' "$tpl"; then
    die "Template falta campo obligatorio FECHA: ($tpl)"
  fi
  if ! grep -q '{{DATE}}' "$tpl"; then
    die "Template no tiene placeholder {{DATE}} en FECHA: ($tpl)"
  fi

  # Essential: section headers
  local h
  for h in "# POEMA" "# POEMA_CITADO" "# TEXTO"; do
    if ! grep -qF "$h" "$tpl"; then
      die "Template falta header obligatorio: $h ($tpl)"
    fi
  done

  # Optional metadata keys (warn if missing)
  local k
  for k in "MY_POEM_TITLE" "POETA" "POEM_TITLE" "BOOK_TITLE"; do
    if ! grep -qE "^${k}:" "$tpl"; then
      warn "Template no tiene el campo de metadato (puede estar vacío, pero debería existir): ${k}: ($tpl)"
    fi
  done
}

lint_txt() {
  local txt="$1"
  local expected_date="$2"
  local archivo="$3"
  local exists_flag="$4"  # "1" if published entry exists in archivo.json

  "$PYTHON" - "$txt" "$expected_date" "$archivo" "$exists_flag" <<'PY' | while IFS=$'\t' read -r level msg; do
import json, re, sys
from pathlib import Path

txt_path = Path(sys.argv[1])
expected_date = sys.argv[2]
archivo = Path(sys.argv[3])
published = (sys.argv[4] == "1")

text = txt_path.read_text(encoding="utf-8")
lines = text.splitlines()

def emit(level, msg):
    print(f"{level}\t{msg}")

# --- parse metadata (KEY: value) until first section header
meta = {}
for line in lines:
    if line.startswith("# "):
        break
    m = re.match(r"^([A-Z_]+):\s*(.*)$", line.strip())
    if m:
        meta[m.group(1)] = m.group(2)

# Required metadata keys (can be empty)
required_keys = ["FECHA", "MY_POEM_TITLE", "POETA", "POEM_TITLE", "BOOK_TITLE"]

for k in required_keys:
    if k not in meta:
        emit("WARN", f"Falta campo de metadato {k}: (puede estar vacío, pero debe existir)")

# FECHA must match expected_date (if present)
if meta.get("FECHA") and meta["FECHA"].strip() != expected_date:
    emit("WARN", f"FECHA interna no coincide: FECHA={meta['FECHA']!r} vs esperado={expected_date!r}")

# Required section headers
headers = ["# POEMA", "# POEMA_CITADO", "# TEXTO"]
for h in headers:
    if h not in text:
        emit("WARN", f"Falta header obligatorio: {h}")

# --- If published: sections should not be empty
def section_body(hdr):
    # capture text between hdr and next "# " header
    m = re.search(re.escape(hdr) + r"\n(.*?)(\n# [A-Z_]+|\Z)", text, flags=re.S)
    if not m:
        return ""
    return m.group(1).strip()

if published:
    bodies = {
        "POEMA": section_body("# POEMA"),
        "POEMA_CITADO": section_body("# POEMA_CITADO"),
        "TEXTO": section_body("# TEXTO"),
    }
    for k, body in bodies.items():
        if not body:
            emit("WARN", f"Entrada ya publicada pero sección {k} está vacía")

    # Compare metadata with archivo.json if present
    try:
        data = json.loads(archivo.read_text(encoding="utf-8"))
        entries = data.get("entries") if isinstance(data, dict) else data
        if isinstance(entries, list):
            entry = next((e for e in entries if isinstance(e, dict) and e.get("date") == expected_date), None)
        else:
            entry = None

        if isinstance(entry, dict):
            expected = {
                "MY_POEM_TITLE": (entry.get("my_poem_title") or ""),
                "POETA": ((entry.get("analysis") or {}).get("poet") or ""),
                "POEM_TITLE": ((entry.get("analysis") or {}).get("poem_title") or ""),
                "BOOK_TITLE": ((entry.get("analysis") or {}).get("book_title") or ""),
            }
            for k, json_val in expected.items():
                txt_val = meta.get(k, "")
                if (txt_val or "").strip() != (json_val or "").strip():
                    emit("WARN", f"Metadato {k} no coincide con archivo.json: txt={txt_val!r} vs json={json_val!r}")
    except Exception:
        pass
PY
    if [[ -n "$msg" && "$level" == "WARN" ]]; then
      warn "$msg"
    fi
  done
}


# -------------------------
# Repo / env
# -------------------------
[[ -n "${QMP_REPO:-}" ]] || die "QMP_REPO no está definido. ¿sourceaste qmp_shell.zsh?"
cd "$QMP_REPO" || die "No puedo entrar a QMP_REPO=$QMP_REPO"

local PYTHON="${QMP_PY:-$QMP_REPO/.venv/bin/python}"
[[ -x "$PYTHON" ]] || die "No existe Python del proyecto: $PYTHON (crea .venv en este entorno)"

local ARCHIVO="${ARCHIVO_JSON:-$QMP_DATA/archivo.json}"
local TEMPLATE="$QMP_DATA/templateTEXT.txt"
local PULL="$QMP_REPO/qmp/pull_keywords.py"
[[ -f "$ARCHIVO" ]] || die "Falta $ARCHIVO"
[[ -f "$TEMPLATE" ]] || die "Falta $TEMPLATE"
[[ -f "$PULL" ]] || die "Falta $PULL"

lint_template "$TEMPLATE"

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
# -------------------------
# Read min/max/next (may be empty if archivo.json has no entries)
# -------------------------
local MIN_DATE="" MAX_DATE="" NEXT_DATE=""
local HAS_PUBLISHED_ENTRIES=0

{
  local out
  out="$("$PYTHON" - "$ARCHIVO" <<'PY' 2>/dev/null
import json, sys
from datetime import date, timedelta

archivo = sys.argv[1]
data = json.load(open(archivo, encoding="utf-8"))

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

# True iff archivo.json has at least 1 published entry
[[ -n "$MAX_DATE" ]] && HAS_PUBLISHED_ENTRIES=1


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
  confirm_yn "Fecha $DATE es anterior a la primera fecha publicada ($MIN_DATE). ¿Continuar igual?" || exit 0
fi

# -------------------------
# Determine if entry exists
# -------------------------
local EXISTS="0"
EXISTS="$("$PYTHON" - "$ARCHIVO" "$DATE" <<'PY' 2>/dev/null
import json, sys
archivo = sys.argv[1]
date_str = sys.argv[2]
data = json.load(open(archivo, encoding="utf-8"))
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
local TXT="$(txt_path_for_date "$DATE")"
local CURRENT="${CURRENT_KW:-${QMP_STATE:-${QMP_SCRIPTS:-$QMP_REPO/scripts}}/current_keywords.txt}"
local PENDING="${PENDING_KW:-${QMP_STATE:-${QMP_SCRIPTS:-$QMP_REPO/scripts}}/pending_keywords.txt}"

# Ensure parent dirs exist (new layout)
mkdir -p "${TXT:h}" || die "No pude crear carpeta: ${TXT:h}"

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

lint_txt "$TXT" "$DATE" "$ARCHIVO" "$EXISTS"



# Regenerate current (snapshot). NEVER touch pending.
# Ensure state dirs exist (so we can write CURRENT)
# -------------------------
# Current keywords snapshot (single-date payload)
# -------------------------
# -------------------------
# Current keywords snapshot
# - EXISTING entry: pull keywords for that date
# - NEW entry: current_keywords should be empty []
# -------------------------
mkdir -p "${CURRENT:h}" || die "No pude crear carpeta de state: ${CURRENT:h}"

if [[ "$EXISTS" == "1" ]]; then
  if ! QMP_ARCHIVO_JSON="$ARCHIVO" "$PYTHON" "$PULL" "$DATE" "$CURRENT" >/dev/null 2>&1; then
    warn "No pude regenerar current_keywords.txt para $DATE (pull_keywords.py falló). Escribo []..."
    echo "[]" > "$CURRENT"
  fi
else
  # Nueva entrada (no publicada): current_keywords debe ser vacío
  echo "[]" > "$CURRENT"
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
