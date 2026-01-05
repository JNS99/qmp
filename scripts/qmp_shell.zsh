# =========================
#  ~/.zshrc — organizado
# =========================

# ---------- Helpers ----------
# Recarga rápida
alias sz='source ~/.zshrc'

# Editar zshrc
alias oz='subl ~/.zshrc'

# ---------- Dev quick aliases ----------
alias s='python3 -m http.server'

# Abrir repo remoto en navegador (GitHub)
alias hub='open "$(git config --get remote.origin.url | sed '\''s/git@github.com:/https:\/\/github.com\//;s/\.git$//'\'' )"'

# ---------- Secrets / API keys ----------
# NO hardcodear llaves aquí. Cargarlas desde un archivo ignorado por git.
# Crea: ~/.config/qmp/secrets.zsh  (ver plantilla al final)
[[ -f "$HOME/.config/qmp/secrets.zsh" ]] && source "$HOME/.config/qmp/secrets.zsh"

# Defaults “no secretos”
export OPENAI_MODEL="${OPENAI_MODEL:-gpt-5-mini}"

# ---------- Git helpers ----------
#lazy push
lp() {
  git add .
  if git commit -m "$1"; then
    git push
    echo "\033[0;32mSuccessfully pushed to GitHub!\033[0m"
  else
    echo "\033[0;31mCommit failed. Push aborted.\033[0m"
    return 1
  fi
}

# ---------- Date validation ----------
is_valid_date() {
  local d="$1"

  # formato básico YYYY-MM-DD
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1

  # validación real (macOS)
  date -j -f "%Y-%m-%d" "$d" "+%Y-%m-%d" >/dev/null 2>&1 || return 1
  return 0
}

# =========================
#  QMP — shortcuts & flow
# =========================

# Ajusta una sola vez acá
export QMP_REPO="${QMP_REPO:-$HOME/Desktop/qmp}"

alias qmp='cd "$QMP_REPO"'

# Preparar día (crear/abrir txt desde template)
qd() {
  local date="${1:-$(date +%F)}"
  if ! is_valid_date "$date"; then
    echo "❌ Fecha inválida: $date"
    return 1
  fi
  "$QMP_REPO/scripts/qd.sh" "$date"
}

# Keywords (OpenAI)
qk() {
  local date="${1:-$(date +%F)}"
  if ! is_valid_date "$date"; then
    echo "❌ Fecha inválida: $date"
    return 1
  fi
  "$QMP_REPO/scripts/qk.sh" "$date"
}

# qk + dry-run
qdk() {
  local date="${1:-$(date +%F)}"
  if ! is_valid_date "$date"; then
    echo "❌ Fecha inválida: $date"
    return 1
  fi

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

  if ! is_valid_date "$date"; then
    echo "❌ Fecha inválida: $date"
    echo "Formato esperado: YYYY-MM-DD (ej: 2025-12-27)"
    return 1
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

# =========================
#  End
# =========================