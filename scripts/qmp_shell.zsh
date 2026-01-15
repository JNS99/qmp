
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
}

