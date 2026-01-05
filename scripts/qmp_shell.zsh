
# =========================
#  QMP — shortcuts & flow
# =========================

export OPENAI_MODEL="${OPENAI_MODEL:-gpt-5-mini}"
export OPENAI_REASONING="${OPENAI_REASONING:-low}"


# --- QMP repo path (Mac vs Codespaces) ---
if [ -n "${CODESPACES:-}" ]; then
  export QMP_REPO="${QMP_REPO:-/workspaces/qmp}"
else
  export QMP_REPO="${QMP_REPO:-$HOME/Desktop/qmp}"
fi

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

# Preparar día (crear/abrir txt desde template)
qd() {"$QMP_REPO/scripts/qd.sh" "$date"}

# Keywords (OpenAI)
qk() {"$QMP_REPO/scripts/qk.sh" "$date"}

# qk + dry-run
qdk() {
  echo "▶️ Generando palabras clave (qk $date)…"
  qk "$date" || { echo "❌ Error en qk. Aborto."; return 1; }
  echo ""
  echo "▶️ Dry run (q --dry-run $date)…"
  q --dry-run "$date"
}

# Publicar (o dry-run)
q() {
  local dry=""
  local msg=""
  local date=""

  for arg in "$@"; do
    case "$arg" in
      --dry-run|--dry|-n) dry="--dry-run" ;;
      ????-??-??)         date="$arg" ;;
      *.txt)
        local base="${arg:t}"   # basename en zsh
        date="${base%.txt}"
        ;;
      *)                  msg="$arg" ;;
    esac
  done

  if [[ -z "$date" ]]; then
    echo "Uso: q [--dry-run] YYYY-MM-DD [mensaje opcional]"
    return 2
  fi
  
  local txt="$QMP_REPO/textos/${date}.txt"
  "$QMP_REPO/scripts/qmp_publish.sh" $dry "$txt" "$msg"
}


qhelp() {
  cat <<'EOF'
QMP — comandos y flujo (resumen)

Comandos principales:
  qd [YYYY-MM-DD]
    - Abre el contexto del día en Sublime.
    - Crea textos/YYYY-MM-DD.txt desde template si no existe.
    - Siempre abre: archivo.json
    - Si la fecha ya existe en archivo.json: exporta keywords actuales a /tmp/qmp_keywords_YYYY-MM-DD.json y lo abre.
    - Si la fecha NO existe: abre scripts/pending_keywords.txt (para preparar keywords nuevas).

  qk [YYYY-MM-DD]
    - Genera keywords vía API.
    - Escribe scripts/pending_keywords.txt con formato:
        {"date":"YYYY-MM-DD","keywords":[{"word":"...","weight":3},...]}
    - Copia una vista a: /tmp/qmp_keywords_YYYY-MM-DD.json
    - No publica.

  q [--dry-run] YYYY-MM-DD [mensaje opcional]
    - Publica (upsert) la entrada del día.
    - Si pending_keywords.txt tiene date == YYYY-MM-DD:
        aplica keywords nuevas
      si no:
        preserva keywords existentes (para edits de texto/metadatos).
    - --dry-run: valida y muestra lo que haría, sin commit/push.

Flujos típicos:

1) Entrada nueva (texto + keywords)
  qd 2026-01-06
  qk 2026-01-06
  q --dry-run 2026-01-06
  q 2026-01-06

2) Editar texto/metadatos de una entrada existente (sin tocar keywords)
  qd 2026-01-03
  q --dry-run 2026-01-03
  q 2026-01-03

3) Regenerar / editar keywords de una entrada existente
  qk 2026-01-03
  # (opcional) editar scripts/pending_keywords.txt o /tmp/qmp_keywords_2026-01-03.json
  q --dry-run 2026-01-03
  q 2026-01-03

Mensajes de commit (automáticos si no das uno):
  entrada <fecha>
  edicion de metadatos/escritos <fecha>
  edicion de palabras clave <fecha>
  edicion texto + keywords <fecha>

EOF
}