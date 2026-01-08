#!/usr/bin/env zsh
# QMP — qk (zsh-only)
# Contract:
# - qk [YYYY-MM-DD]
#   - 0 args: propose NEXT_DATE (max_date + 1 day) from archivo.json, ask (y/N)
#   - 1 arg: generate for that date (still validates, still guard overwrite)
# - Validates TXT before generating keywords
# - Writes state/pending_keywords.txt atomically
# - Does NOT touch state/current_keywords.txt

set -e
set -u
setopt pipefail

die()  { print -u2 -- "[qk] ERROR: $*"; exit 1; }
warn() { print -u2 -- "[qk] WARN: $*"; }

confirm_yn() {
  # Default = NO (Enter -> no)
  local prompt="$1"
  local ans
  print -n -u2 -- "[qk] $prompt [y/N]: "
  read ans || true
  ans="${${ans:-}:l}"
  case "$ans" in
    y|yes|s|si|sí) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Hard requirements (sin fallbacks peligrosos) ---
[[ -n "${QMP_REPO:-}"     ]] || die "QMP_REPO no está definido. ¿sourceaste scripts/qmp_shell.zsh?"
[[ -n "${QMP_TEXTOS:-}"   ]] || die "QMP_TEXTOS no está definido. ¿sourceaste scripts/qmp_shell.zsh?"
[[ -n "${ARCHIVO_JSON:-}" ]] || die "ARCHIVO_JSON no está definido. ¿sourceaste scripts/qmp_shell.zsh?"
[[ -n "${PENDING_KW:-}"   ]] || die "PENDING_KW no está definido. ¿sourceaste scripts/qmp_shell.zsh?"

PYTHON="${QMP_PY:-$QMP_REPO/.venv/bin/python}"
ARCHIVO="$ARCHIVO_JSON"
GEN="$QMP_REPO/qmp/gen_keywords.py"
VALIDATE="$QMP_REPO/qmp/validate_entry.py"
OUT_ACTIVE="$PENDING_KW"

[[ -x "$PYTHON" ]] || die "No existe Python del proyecto: $PYTHON"
[[ -f "$ARCHIVO" ]] || die "Falta $ARCHIVO"
[[ -f "$GEN" ]] || die "Falta $GEN"
[[ -f "$VALIDATE" ]] || die "Falta $VALIDATE"

[[ -n "${OPENAI_API_KEY:-}" ]] || die "Falta OPENAI_API_KEY en el entorno."

txt_path_for_date() {
  local d="$1"
  local y="${d[1,4]}"
  local m="${d[6,7]}"

  local p_new="${QMP_TEXTOS}/${y}/${m}/${d}.txt"
  local p_old="${QMP_TEXTOS}/${d}.txt"

  if [[ -f "$p_old" && ! -f "$p_new" ]]; then
    print -r -- "$p_old"
  else
    print -r -- "$p_new"
  fi
}

# EXACTAMENTE el mismo criterio que qd para leer max_date + next_date
next_date_from_archivo() {
  "$PYTHON" - "$ARCHIVO" <<'PY'
import json, sys
from datetime import date, timedelta

archivo = sys.argv[1]
data = json.load(open(archivo, encoding="utf-8"))

entries = data["entries"] if isinstance(data, dict) and isinstance(data.get("entries"), list) else data
if not isinstance(entries, list):
    print("")
    raise SystemExit(0)

dates = sorted({e.get("date","") for e in entries if isinstance(e, dict) and e.get("date")})
if not dates:
    print("")
    raise SystemExit(0)

y,m,d = map(int, dates[-1].split("-"))
print((date(y,m,d) + timedelta(days=1)).isoformat())
PY
}

# Validate real calendar date (sin traceback)
validate_real_date() {
  local d="$1"
  "$PYTHON" - "$d" >/dev/null 2>&1 <<'PY'
from datetime import date
import sys
try:
    date.fromisoformat(sys.argv[1])
except Exception:
    raise SystemExit(1)
PY
}

# --- parse args (0 or 1) ---
typeset DATE=""
if (( $# == 0 )); then
  DATE=""
elif (( $# == 1 )); then
  DATE="$1"
else
  die "Uso: qk [YYYY-MM-DD]  (0 o 1 argumento solamente)"
fi

# --- no args => propose NEXT_DATE ---
if [[ -z "$DATE" ]]; then
  typeset NEXT_DATE
  NEXT_DATE="$(next_date_from_archivo 2>/dev/null)" || NEXT_DATE=""
  if [[ -z "$NEXT_DATE" ]]; then
    die "archivo.json no tiene entradas publicadas. Usa: qk YYYY-MM-DD"
  fi
  confirm_yn "¿Generar pending_keywords para $NEXT_DATE?" || exit 0
  DATE="$NEXT_DATE"
fi

[[ "$DATE" == <->-<->-<-> ]] || die "Fecha inválida: $DATE (usa YYYY-MM-DD)"
validate_real_date "$DATE" || die "Fecha inválida (no existe): $DATE"

IN_FILE="$(txt_path_for_date "$DATE")"
[[ -f "$IN_FILE" ]] || die "No encuentro ${IN_FILE}. (Usa qd primero)"

# --- VALIDATION BEFORE generating keywords (single source of truth) ---
if ! "$PYTHON" "$VALIDATE" --mode validate "$DATE" "$IN_FILE" >/dev/null; then
  print -u2 -- "[qk] WARN: validate_entry.py falló. Detalle:"
  "$PYTHON" "$VALIDATE" --mode validate "$DATE" "$IN_FILE" >&2 || true
  die "Formato inválido en ${IN_FILE}"
fi

# --- guard: avoid overwriting an existing pending_keywords for a different date ---
if [[ -f "$OUT_ACTIVE" ]]; then
  typeset PEND_DATE PEND_LEN

  PEND_DATE="$("$PYTHON" - "$OUT_ACTIVE" 2>/dev/null <<'PY'
import json, sys
p=sys.argv[1]
try:
    d=json.load(open(p, encoding="utf-8"))
    print(d.get("date","") if isinstance(d, dict) else "")
except Exception:
    print("")
PY
)"
  PEND_LEN="$("$PYTHON" - "$OUT_ACTIVE" 2>/dev/null <<'PY'
import json, sys
p=sys.argv[1]
try:
    d=json.load(open(p, encoding="utf-8"))
    kws = d.get("keywords", []) if isinstance(d, dict) else []
    print(len(kws) if isinstance(kws, list) else 0)
except Exception:
    print(0)
PY
)"
  if [[ -n "$PEND_DATE" && "$PEND_DATE" != "$DATE" ]]; then
    confirm_yn "pending_keywords ya existe para $PEND_DATE ($PEND_LEN keywords). ¿Sobrescribir con $DATE?" || exit 0
  fi
fi

# --- generate keywords to temp file (atomic write) ---
TMP_OUT="$(mktemp "${OUT_ACTIVE}.tmp.XXXXXX")"
trap 'rm -f "$TMP_OUT"' EXIT

if ! "$PYTHON" "$GEN" "$IN_FILE" "$TMP_OUT"; then
  die "gen_keywords.py falló"
fi

# --- wrap output to ensure {"date":..., "keywords":[...]} ---
"$PYTHON" - "$DATE" "$TMP_OUT" <<'PY'
import json, sys
date = sys.argv[1]
p = sys.argv[2]
data = json.loads(open(p, encoding="utf-8").read() or "{}")
if not isinstance(data, dict):
    data = {}
kws = data.get("keywords", [])
data = {"date": date, "keywords": kws}
with open(p, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PY

mkdir -p "${OUT_ACTIVE:h}" || die "No pude crear carpeta de state: ${OUT_ACTIVE:h}"
mv "$TMP_OUT" "$OUT_ACTIVE"
trap - EXIT

print -- "[qk] OK: generado $OUT_ACTIVE"
