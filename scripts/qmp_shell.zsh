
# =========================
#  QMP — shortcuts & flow
# =========================

export OPENAI_MODEL="${OPENAI_MODEL:-gpt-5-mini}"
export OPENAI_REASONING="${OPENAI_REASONING:-medium}"


# --- QMP repo path (Mac vs Codespaces) ---
if [ -n "${CODESPACES:-}" ]; then
  export QMP_REPO="${QMP_REPO:-/workspaces/qmp}"
else
  export QMP_REPO="${QMP_REPO:-$HOME/Desktop/qmp}"
fi

# --- QMP paths (single source of truth) ---
export QMP_SCRIPTS="$QMP_REPO/scripts"

# NOTE: Por ahora, "data" vive en la raíz. Más adelante lo moveremos a /data
export QMP_DATA="$QMP_REPO/data"
export QMP_TEXTOS="$QMP_DATA/textos"


# NOTE: Ahora "state" vive en /state
export QMP_STATE="$QMP_REPO/state"

# Python del proyecto (evita diferencias Mac/Codespaces)
export QMP_PY="$QMP_REPO/.venv/bin/python"

# --- Named files/dirs ---
export ARCHIVO_JSON="$QMP_DATA/archivo.json"
export PUBLISH_LOG="$QMP_REPO/logs/publish_log.jsonl"
export CURRENT_KW="$QMP_STATE/current_keywords.txt"
export PENDING_KW="$QMP_STATE/pending_keywords.txt"
export PENDING_ENTRY="$QMP_STATE/pending_entry.json"
export KEYWORDS_BACKUPS_DIR="$QMP_STATE/keywords_backups"



qmp() {
  cd "$QMP_REPO" || { echo "❌ No encuentro QMP_REPO: $QMP_REPO" >&2; return 1; }
}

_qmp_check() {
  if [ -z "${QMP_REPO:-}" ] || [ ! -d "$QMP_REPO/scripts" ]; then
    echo "❌ QMP_REPO no está bien configurado: ${QMP_REPO:-<vacío>}" >&2
    echo "   (esperaba ver: $QMP_REPO/scripts)" >&2
    return 1
  fi
}

qd()  { _qmp_check || return 1; "$QMP_SCRIPTS/qd.sh"  "$@"; }
qk()  { _qmp_check || return 1; "$QMP_SCRIPTS/qk.sh"  "$@"; }
qkw() { _qmp_check || return 1; "$QMP_SCRIPTS/qkw.sh" "$@"; }
q()   { _qmp_check || return 1; "$QMP_SCRIPTS/qmp_publish.sh" "$@"; }


qhelp() {
  cat <<'EOF'
QMP — Help (CLI)

REGLAS DEL PROYECTO
- ZSH only. No bash.
- QMP_REPO es la única fuente de verdad del repo:
  - Codespaces: /workspaces/qmp
  - Mac:       $HOME/Desktop/qmp
- Python SIEMPRE = $QMP_REPO/.venv/bin/python

ARCHIVOS IMPORTANTES
- archivo.json                      (verdad publicada; raíz = array)
- textos/YYYY-MM-DD.txt             (fuente del día)
- scripts/current_keywords.txt      (snapshot de keywords existentes para esa fecha)
- scripts/pending_keywords.txt      (propuesta de keywords; se aplica solo con --kw)

COMANDOS

qd [YYYY-MM-DD]
- 0 args:
  - propone la fecha siguiente (max_date + 1) desde archivo.json y pide confirmación (y/N)
- 1 arg:
  - valida fecha real
  - rechaza fechas < MIN_DATE (archivo.json)
  - si la fecha es "rara" (no existe y no es NEXT_DATE) pide confirmación (y/N)
- crea textos/YYYY-MM-DD.txt si no existe (usa templateTEXT.txt)
- rellena {{DATE}} si existe en el archivo (idempotente)
- regenera scripts/current_keywords.txt desde archivo.json
- NO toca scripts/pending_keywords.txt
- abre: TXT + current_keywords + pending_keywords + archivo.json (con TXT en foco)

qk [YYYY-MM-DD]
- 0 args:
  - usa la fecha siguiente (max_date + 1) y pide confirmación (y/N)
  - exige que textos/<next>.txt exista (usa qd primero)
- 1 arg:
  - valida fecha real
  - exige que textos/YYYY-MM-DD.txt exista
- valida estrictamente el TXT:
  - metadatos requeridos (keys existen): FECHA, MY_POEM_TITLE, POETA, POEM_TITLE, BOOK_TITLE
  - FECHA coincide con la fecha y el nombre del archivo
  - secciones existen/en orden y con contenido:
    # POEMA, # POEMA_CITADO, # TEXTO
- genera keywords y escribe SOLO scripts/pending_keywords.txt (escritura atómica)
- si pending_keywords ya tiene otra fecha con keywords -> pregunta antes de sobrescribir (y/N)

qkw YYYY-MM-DD
- copia current_keywords -> pending_keywords para editar keywords manualmente con seguridad
  (flujo típico: qd -> editar current_keywords -> qkw -> q --kw)

q [--dry-run] [--kw] [YYYY-MM-DD]
- 0 args:
  - usa la fecha siguiente (max_date + 1) y pide confirmación (y/N)
- valida TXT (mismas reglas estrictas que qk)
- normaliza SOLO metadatos + líneas vacías alrededor de headers (NO toca el contenido)
- si --kw:
  - exige pending_keywords.date == fecha y keywords no vacías
- hace dry-run mostrando commit si corresponde
- si no hay cambios de texto ni keywords -> no commit
- commit messages (obligatorio):
  - entrada YYYY-MM-DD — <titulo/snippet>
  - edicion de metadatos/escritos YYYY-MM-DD — <titulo/snippet>
  - edicion de palabras clave YYYY-MM-DD — <titulo/snippet>
  - edicion texto + keywords YYYY-MM-DD — <titulo/snippet>
- después de publicar con --kw: vacía scripts/pending_keywords.txt (date:"", keywords:[])

TIPS
- Entrada nueva típica:
  qd
  qk
  q --dry-run --kw
  q --kw
- Editar texto sin keywords:
  qd YYYY-MM-DD
  q --dry-run YYYY-MM-DD
  q YYYY-MM-DD
- Cambiar solo keywords:
  qd YYYY-MM-DD
  (editar current_keywords)
  qkw YYYY-MM-DD
  q --dry-run --kw YYYY-MM-DD
  q --kw YYYY-MM-DD

EOF
}

