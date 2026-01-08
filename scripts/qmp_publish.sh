#!/usr/bin/env zsh
set -e
set -u
setopt pipefail

die()  { print -u2 -- "[q] ERROR: $*"; exit 1; }
warn() { print -u2 -- "[q] WARN: $*"; }

confirm_yn() {
  local prompt="$1"
  local ans
  print -n -u2 -- "[q] $prompt [y/N]: "
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
[[ -n "${PENDING_ENTRY:-}" ]] || die "PENDING_ENTRY no está definido. ¿sourceaste scripts/qmp_shell.zsh?"

cd "$QMP_REPO" || die "No puedo entrar a QMP_REPO=$QMP_REPO"

PYTHON="${QMP_PY:-$QMP_REPO/.venv/bin/python}"
[[ -x "$PYTHON" ]] || die "No existe Python del proyecto: $PYTHON"

ARCHIVO="$ARCHIVO_JSON"
MERGE="$QMP_REPO/qmp/merge_pending.py"
VALID="$QMP_REPO/qmp/validate_entry.py"

[[ -f "$ARCHIVO" ]] || die "Falta $ARCHIVO"
[[ -f "$MERGE"   ]] || die "Falta $MERGE"
[[ -f "$VALID"   ]] || die "Falta $VALID"

txt_path_for_date() {
  local d="$1"
  local y="${d[1,4]}"
  local m="${d[6,7]}"

  local p_new="${QMP_TEXTOS}/${y}/${m}/${d}.txt"
  local p_old="${QMP_TEXTOS}/${d}.txt"

  if [[ -f "$p_new" ]]; then
    print -r -- "$p_new"
  else
    print -r -- "$p_old"
  fi
}

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

# --- args ---
DRY=0
APPLY_KW=0
DATE=""

for arg in "$@"; do
  case "$arg" in
    --dry-run|--dry|-n) DRY=1 ;;
    --kw) APPLY_KW=1 ;;
    -*)
      die "Opción inválida: $arg. Uso: q [--kw] [--dry-run|-n] [YYYY-MM-DD]"
      ;;
    *)
      if [[ -z "$DATE" ]]; then
        DATE="$arg"
      else
        die "Uso: q [--kw] [--dry-run|-n] [YYYY-MM-DD]"
      fi
      ;;
  esac
done

# If no DATE: propose next_date with confirmation
if [[ -z "$DATE" ]]; then
  typeset NEXT_DATE
  NEXT_DATE="$(next_date_from_archivo 2>/dev/null)" || NEXT_DATE=""
  [[ -n "$NEXT_DATE" ]] || die "archivo.json no tiene entradas. Usa: q YYYY-MM-DD"
  confirm_yn "¿Publicar $NEXT_DATE?" || exit 0
  DATE="$NEXT_DATE"
fi

[[ "$DATE" == <->-<->-<-> ]] || die "Fecha inválida: $DATE (usa YYYY-MM-DD)"
validate_real_date "$DATE" || die "Fecha inválida (no existe): $DATE"

TXT="$(txt_path_for_date "$DATE")"
[[ -f "$TXT" ]] || die "No existe $TXT (usa qd primero)"

# --- Validate + normalize (idempotente) ---
NORM_JSON="$("$PYTHON" "$VALID" --mode normalize "$DATE" "$TXT" 2>/dev/null)" || die "Formato inválido en $TXT"

CHANGED="$("$PYTHON" - "$NORM_JSON" <<'PY'
import json, sys
d=json.loads(sys.argv[1])
print("1" if d.get("changed_formatting") else "0")
PY
)"
if [[ "$CHANGED" == "1" ]]; then
  "$PYTHON" - "$NORM_JSON" "$TXT" <<'PY'
import json, sys
payload=json.loads(sys.argv[1])
path=sys.argv[2]
open(path, "w", encoding="utf-8").write(payload["normalized_text"])
PY
fi

# --- If --kw: require valid pending_keywords for this date and non-empty ---
if (( APPLY_KW == 1 )); then
  [[ -f "$PENDING_KW" ]] || die "Falta $PENDING_KW (necesario para --kw)"
  if ! "$PYTHON" - "$DATE" "$PENDING_KW" >/dev/null 2>&1 <<'PY'
import json, sys
date=sys.argv[1]
p=sys.argv[2]
d=json.load(open(p, encoding="utf-8"))
if not isinstance(d, dict): raise SystemExit(1)
if (d.get("date","") or "").strip() != date: raise SystemExit(1)
k=d.get("keywords", [])
if not isinstance(k, list) or len(k)==0: raise SystemExit(1)
PY
  then
    die "pending_keywords.txt inválido: requiere date==$DATE y keywords no vacías"
  fi
fi

# --- Branch check ---
QMP_BRANCH="${QMP_BRANCH:-main}"
CUR_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
[[ -n "$CUR_BRANCH" ]] || die "No parece ser un repo git."
if [[ "$CUR_BRANCH" != "$QMP_BRANCH" ]]; then
  die "Branch actual: $CUR_BRANCH (esperado: $QMP_BRANCH)"
fi

# --- Staged junk check ---
if [[ -n "$(git diff --cached --name-only)" ]]; then
  confirm_yn "Hay cambios staged no relacionados. ¿Continuar igual?" || exit 0
fi

# --- Run merge_pending ---
typeset -a merge_args
merge_args=(
  "$MERGE" "$TXT"
  --archivo "$ARCHIVO"
  --pending-kw "$PENDING_KW"
  --pending-entry "$PENDING_ENTRY"
)
(( APPLY_KW == 1 )) && merge_args+=("--apply-keywords")
(( DRY == 1 )) && merge_args+=("--dry-run")

OUT="$("$PYTHON" "${merge_args[@]}" 2>&1)" || { print -u2 -- "$OUT"; exit 1; }

STATUS_LINE="$(print -- "$OUT" | awk -F= '/^STATUS_JSON=/{print $2; exit}')"
[[ -n "$STATUS_LINE" ]] || die "merge_pending.py no emitió STATUS_JSON"

EXISTS_BEFORE="$("$PYTHON" - "$STATUS_LINE" <<'PY'
import json, sys
print("1" if json.loads(sys.argv[1]).get("exists_before") else "0")
PY
)"
CONTENT_CHANGED="$("$PYTHON" - "$STATUS_LINE" <<'PY'
import json, sys
print("1" if json.loads(sys.argv[1]).get("content_changed") else "0")
PY
)"
KW_CHANGED="$("$PYTHON" - "$STATUS_LINE" <<'PY'
import json, sys
print("1" if json.loads(sys.argv[1]).get("keywords_changed") else "0")
PY
)"
MY_TITLE="$("$PYTHON" - "$STATUS_LINE" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("my_poem_title","") or "")
PY
)"
MY_SNIPPET="$("$PYTHON" - "$STATUS_LINE" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("my_poem_snippet","") or "")
PY
)"

LABEL="$MY_TITLE"; [[ -n "$LABEL" ]] || LABEL="$MY_SNIPPET"; [[ -n "$LABEL" ]] || LABEL="(sin título/snippet)"

# commit type
MSG_TYPE=""
if [[ "$EXISTS_BEFORE" == "0" ]]; then
  MSG_TYPE="entrada"
else
  if [[ "$CONTENT_CHANGED" == "1" && "$KW_CHANGED" == "1" ]]; then
    MSG_TYPE="edicion texto + keywords"
  elif [[ "$CONTENT_CHANGED" == "1" ]]; then
    MSG_TYPE="edicion de metadatos/escritos"
  elif [[ "$KW_CHANGED" == "1" ]]; then
    MSG_TYPE="edicion de palabras clave"
  else
    print -- "ℹ️  No cambió texto ni keywords → no hay commit."
    exit 0
  fi
fi

MSG="${MSG_TYPE} ${DATE} — ${LABEL}"

if (( DRY == 1 )); then
  print -- "DRY RUN ✅"
  print -- "Commit: $MSG"
  print -- "exists_before=$EXISTS_BEFORE content_changed=$CONTENT_CHANGED keywords_changed=$KW_CHANGED apply_kw=$APPLY_KW"
  exit 0
fi

# --- Final confirmation ---
print -u2 -- "[q] Fecha: $DATE"
print -u2 -- "[q] Commit: $MSG"
confirm_yn "¿Confirmar publish (commit + push)?" || exit 0

# --- Apply pending_entry.json into archivo.json (sorted desc) ---
[[ -f "$PENDING_ENTRY" ]] || die "No existe $PENDING_ENTRY"
"$PYTHON" - "$DATE" "$PENDING_ENTRY" "$ARCHIVO" <<'PY'
import json, sys
from pathlib import Path

date = sys.argv[1]
pending_path = Path(sys.argv[2])
archivo_path = Path(sys.argv[3])

pending = json.loads(pending_path.read_text(encoding="utf-8"))
if not isinstance(pending, dict) or pending.get("date") != date:
    raise SystemExit("pending_entry.json inválido o fecha no coincide")

data = json.loads(archivo_path.read_text(encoding="utf-8"))
entries = data["entries"] if isinstance(data, dict) and isinstance(data.get("entries"), list) else data
if not isinstance(entries, list):
    raise SystemExit("archivo.json inválido: raíz no es lista")

entries = [e for e in entries if isinstance(e, dict) and e.get("date") != date]
entries.append(pending)
entries.sort(key=lambda e: e.get("date",""), reverse=True)

archivo_path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

# --- Git commit/push ---
git add "$ARCHIVO" "$TXT" "$PENDING_ENTRY"
git commit -m "$MSG"
git push

print -- "✅ Publicado: $MSG"

# --- Post-success: clear pending_keywords if we applied keywords ---
if (( APPLY_KW == 1 )); then
  cat > "$PENDING_KW" <<EOF
{
  "date": "",
  "keywords": []
}
EOF
fi
