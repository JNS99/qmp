#!/usr/bin/env zsh
set -e
set -u
setopt pipefail

die() { print -u2 -- "[qk] $*"; exit 1; }

confirm_yn() {
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

# --- repo/env ---
[[ -n "${QMP_REPO:-}" ]] || die "QMP_REPO no está definido. ¿sourceaste qmp_shell.zsh?"
cd "$QMP_REPO" || die "No puedo entrar a QMP_REPO=$QMP_REPO"

PYTHON="$QMP_REPO/.venv/bin/python"
[[ -x "$PYTHON" ]] || die "No existe Python del proyecto: $PYTHON (crea .venv en este entorno)"

ARCHIVO="archivo.json"
GEN="scripts/gen_keywords.py"
OUT_ACTIVE="scripts/pending_keywords.txt"

[[ -f "$ARCHIVO" ]] || die "Falta $ARCHIVO"
[[ -f "$GEN" ]] || die "Falta $GEN"
[[ -n "${OPENAI_API_KEY:-}" ]] || die "Falta OPENAI_API_KEY en el entorno."

# --- args: 0 or 1 ---
DATE=""
if (( $# == 0 )); then
  DATE=""
elif (( $# == 1 )); then
  DATE="$1"
else
  die "Uso: qk [YYYY-MM-DD]  (0 o 1 argumento solamente)"
fi

# --- compute next_date if needed ---
if [[ -z "$DATE" ]]; then
  NEXT_DATE="$("$PYTHON" - <<'PY' 2>/dev/null
import json
from datetime import date, timedelta

data = json.load(open("archivo.json", encoding="utf-8"))
entries = data["entries"] if isinstance(data, dict) and isinstance(data.get("entries"), list) else data
if not isinstance(entries, list):
    raise SystemExit(1)

dates = sorted({e.get("date","") for e in entries if isinstance(e, dict) and e.get("date")})
if not dates:
    raise SystemExit(1)

y,m,d = map(int, dates[-1].split("-"))
print((date(y,m,d) + timedelta(days=1)).isoformat())
PY
)" || die "archivo.json no tiene entradas. Usa: qk YYYY-MM-DD"

  IN_FILE="textos/${NEXT_DATE}.txt"
  [[ -f "$IN_FILE" ]] || die "No encuentro ${IN_FILE}. (Usa qd primero)"
  confirm_yn "¿Generar palabras clave para ${NEXT_DATE}?" || exit 0
  DATE="$NEXT_DATE"
fi

# --- validate YYYY-MM-DD and real date (silent) ---
[[ "$DATE" == <->-<->-<-> ]] || die "Fecha inválida: $DATE (usa YYYY-MM-DD)"

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

IN_FILE="textos/${DATE}.txt"
[[ -f "$IN_FILE" ]] || die "No encuentro ${IN_FILE}. (Usa qd primero)"

# --- validate txt structure/content + date matches filename ---
if ! "$PYTHON" - "$DATE" "$IN_FILE" >/dev/null 2>&1 <<'PY'
import re, sys, pathlib
from datetime import date as dt

DATE = sys.argv[1]
path = pathlib.Path(sys.argv[2])
raw = path.read_text(encoding="utf-8")

# Required metadata keys (existence). Only FECHA must be non-empty.
required_keys = ["FECHA", "MY_POEM_TITLE", "POETA", "POEM_TITLE", "BOOK_TITLE"]

# Split into lines and find headers
lines = raw.splitlines()

# Parse metadata until first section header
meta = {}
i = 0
while i < len(lines):
    line = lines[i]
    if re.match(r"^\s*#\s*(POEMA_CITADO|POEMA|TEXTO)\s*$", line):
        break
    if ":" in line:
        k, v = line.split(":", 1)
        meta[k.strip().upper()] = v.strip()
    i += 1

for k in required_keys:
    if k not in meta:
        raise SystemExit(1)

file_fecha = meta.get("FECHA","").strip()
if not file_fecha:
    raise SystemExit(1)

# validate real date and match
try:
    dt.fromisoformat(file_fecha)
except Exception:
    raise SystemExit(1)

if file_fecha != DATE:
    raise SystemExit(1)

# Extract sections in order and require non-empty content (not just whitespace)
def grab_section(name: str) -> str:
    pat = re.compile(rf"^\s*#\s*{re.escape(name)}\s*$", re.M)
    m = pat.search(raw)
    if not m:
        return ""
    start = m.end()
    # find next header
    m2 = re.search(r"^\s*#\s*(POEMA_CITADO|POEMA|TEXTO)\s*$", raw[start:], flags=re.M)
    end = start + m2.start() if m2 else len(raw)
    return raw[start:end].strip()

poema = grab_section("POEMA")
citado = grab_section("POEMA_CITADO")
texto = grab_section("TEXTO")

# Require headers exist and contain content
if not poema or not citado or not texto:
    raise SystemExit(1)

# Require order: POEMA then POEMA_CITADO then TEXTO
pos_poema = raw.find("\n# POEMA") if "\n# POEMA" in raw else raw.find("# POEMA")
pos_citado = raw.find("\n# POEMA_CITADO") if "\n# POEMA_CITADO" in raw else raw.find("# POEMA_CITADO")
pos_texto = raw.find("\n# TEXTO") if "\n# TEXTO" in raw else raw.find("# TEXTO")
if not (pos_poema != -1 and pos_citado != -1 and pos_texto != -1 and pos_poema < pos_citado < pos_texto):
    raise SystemExit(1)
PY
then
  die "Formato inválido en ${IN_FILE}. Requiere metadatos (keys) + FECHA==${DATE} + secciones con contenido (# POEMA, # POEMA_CITADO, # TEXTO) en orden."
fi

# --- guard: avoid overwriting an existing pending_keywords for a different date ---
if [[ -f "$OUT_ACTIVE" ]]; then
  local PEND_DATE PEND_LEN
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
  if [[ -n "$PEND_DATE" && "$PEND_DATE" != "$DATE" && "$PEND_LEN" -gt 0 ]]; then
    confirm_yn "pending_keywords ya tiene $PEND_LEN palabras para $PEND_DATE. ¿Sobrescribir con $DATE?" || exit 0
  fi
fi


# --- generate keywords (tmp) ---
TMP_GEN="$(mktemp)"
TMP_OUT="$(mktemp)"

"$PYTHON" "$GEN" "$IN_FILE" "$TMP_GEN"

# Wrap with date and ensure non-empty keywords (no traceback to user)
if ! "$PYTHON" - "$DATE" "$TMP_GEN" "$TMP_OUT" >/dev/null 2>&1 <<'PY'
import json, sys, pathlib

date = sys.argv[1]
src = pathlib.Path(sys.argv[2])
out = pathlib.Path(sys.argv[3])

data = json.loads(src.read_text(encoding="utf-8"))

if isinstance(data, dict) and "keywords" in data:
    kws = data["keywords"]
elif isinstance(data, list):
    kws = data
else:
    raise SystemExit(1)

if not isinstance(kws, list) or len(kws) == 0:
    raise SystemExit(1)

payload = {"date": date, "keywords": kws}
out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
then
  rm -f "$TMP_GEN" "$TMP_OUT"
  die "Keywords vacías o formato inválido: no toco pending_keywords.txt"
fi

rm -f "$TMP_GEN"

# Atomic move
mv "$TMP_OUT" "$OUT_ACTIVE"
print -- "[qk] OK: ${OUT_ACTIVE} (date: ${DATE})"
