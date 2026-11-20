#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: GIT (multi-remoto)
#  Repositorio activo: $REPO_DIR (cámbialo desde el menú o con PROM_REPO_DIR).
#  Todas las operaciones usan 'git -C "$REPO_DIR"': nunca dependen del cwd.
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

GIT_REMOTE=""

git_ok() {
    command -v git &>/dev/null || { need git || return 1; }
    if [[ -z "$REPO_DIR" ]] || ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        msg_err "No hay un repositorio Git en '${REPO_DIR:-(vacío)}'"
        msg_info "(Cambia el repositorio desde este menú o con: PROM_REPO_DIR=/ruta $SCRIPT_NAME)"
        return 1
    fi
}

git_branch_name() { git -C "$REPO_DIR" branch --show-current 2>/dev/null; }
git_remote_list() { git -C "$REPO_DIR" remote 2>/dev/null; }

# Etiqueta amigable: "origin (GitHub)"
git_remote_label() {
    local url; url=$(git -C "$REPO_DIR" remote get-url "$1" 2>/dev/null)
    case "$url" in
        *github.com*) print -r -- "$1 (GitHub)" ;;
        *gitlab*)     print -r -- "$1 (GitLab)" ;;
        *bitbucket*)  print -r -- "$1 (Bitbucket)" ;;
        *)            print -r -- "$1" ;;
    esac
}

# Panel bajo el título (SIN red: usa las referencias del último fetch)
git_panel() {
    print ""
    kv "Repositorio" "${REPO_DIR/#$HOME/~}"
    if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        kv "Estado" "${C_YEL}[!]${C_RST} no es un repositorio Git"; return 0
    fi
    local br ch r counts ahead behind
    local -a remotes
    br=$(git_branch_name); br="${br:-(HEAD desacoplado)}"
    ch=$(git -C "$REPO_DIR" status -s | wc -l | tr -d ' ')
    kv "Rama" "$br"
    kv "Cambios" "$ch archivo(s) sin commitear"
    remotes=( ${(f)"$(git_remote_list)"} )
    if (( ${#remotes} == 0 )); then kv "Remotos" "ninguno configurado"; return 0; fi
    for r in "${remotes[@]}"; do
        counts=$(git -C "$REPO_DIR" rev-list --left-right --count "HEAD...${r}/${br}" 2>/dev/null)
        if [[ -n "$counts" ]]; then
            ahead="${counts%%[[:space:]]*}"; behind="${counts##*[[:space:]]}"
            if (( ahead == 0 && behind == 0 )); then kv "$(git_remote_label "$r")" "${C_GRN}sincronizado${C_RST}"
            else kv "$(git_remote_label "$r")" "↑$ahead por subir / ↓$behind por bajar"; fi
        else
            kv "$(git_remote_label "$r")" "sin referencia de '$br' (usa fetch)"
        fi
    done
}

git_set_repo() {
    local d
    prompt_input "Ruta del repositorio [actual: $REPO_DIR]: " d
    [[ -z "$d" ]] && return 0
    if ! git -C "$d" rev-parse --is-inside-work-tree &>/dev/null; then
        msg_err "'$d' no es un repositorio Git."; return 0
    fi
    REPO_DIR="${d:A}"
    msg_ok "Repositorio activo: $REPO_DIR"
    log_action "Git: repositorio activo $REPO_DIR"
}

# Deja el remoto elegido en GIT_REMOTE. Con "all" agrega la opción [todos] (-> ALL).
git_pick_remote() {
    GIT_REMOTE=""
    local -a rems opts
    rems=( ${(f)"$(git_remote_list)"} )
    if (( ${#rems} == 0 )); then msg_err "Este repositorio no tiene remotos configurados."; return 1; fi
    if (( ${#rems} == 1 )); then GIT_REMOTE="${rems[1]}"; return 0; fi
    opts=("${rems[@]}")
    [[ "$1" == all ]] && opts+=("[todos los remotos]")
    pick_from_list "Remotos disponibles:" "${opts[@]}" || return 1
    GIT_REMOTE="$PICKED"
    [[ "$PICKED" == "[todos los remotos]" ]] && GIT_REMOTE="ALL"
    return 0
}

git_status() {
    git_ok || return 0
    msg_info "Rama actual: $(git_branch_name)"
    print ""
    msg_info "Estado del repositorio:"
    if [[ -z "$(git -C "$REPO_DIR" status -s)" ]]; then print "    (El árbol de trabajo está limpio)"
    else git -C "$REPO_DIR" status -sb; fi
    log_action "Git: status"
}

git_log() {
    git_ok || return 0
    msg_info "Últimos 8 commits:"
    git -C "$REPO_DIR" log --oneline --decorate --graph -n 8
    log_action "Git: log"
}

git_fetch() {
    git_ok || return 0
    msg_info "git fetch --all --prune ..."
    git -C "$REPO_DIR" fetch --all --prune && msg_ok "Referencias actualizadas." || msg_err "El fetch falló (red o credenciales)."
    log_action "Git: fetch --all"
}

# Prueba la autenticación SSH de cada remoto (bajo demanda: 1 conexión por remoto)
git_auth_check() {
    git_ok || return 0
    local r url host out
    for r in ${(f)"$(git_remote_list)"}; do
        url=$(git -C "$REPO_DIR" remote get-url "$r")
        if [[ "$url" == git@*:* || "$url" == ssh://* ]]; then
            host="${url#ssh://}"; host="${host#*@}"; host="${host%%[:/]*}"
            out=$(timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -T "git@$host" 2>&1)
            if [[ "$out" == *"successfully authenticated"* || "$out" == *"Welcome to GitLab"* || "$out" == *"Hi "* ]]; then
                msg_ok "$r ($host): autenticación SSH correcta"
            else
                msg_err "$r ($host): ${out%%$'\n'*}"
            fi
        else
            msg_info "$r: URL HTTPS ($url): usa token/credenciales, no hay prueba SSH."
        fi
    done
}

git_pull() {
    git_ok || return 0
    git_pick_remote || return 0
    local r="$GIT_REMOTE" br counts ahead behind choice
    br=$(git_branch_name)
    [[ -z "$br" ]] && { msg_err "HEAD desacoplado: cambia a una rama primero."; return 0; }
    msg_info "git pull --ff-only $r $br ..."
    if git -C "$REPO_DIR" pull --ff-only "$r" "$br"; then log_action "Git: pull ff-only $r/$br"; return 0; fi

    counts=$(git -C "$REPO_DIR" rev-list --left-right --count "HEAD...${r}/${br}" 2>/dev/null)
    ahead="${counts%%[[:space:]]*}"; behind="${counts##*[[:space:]]}"
    if [[ "$ahead" == <-> && "$behind" == <-> ]] && (( ahead > 0 && behind > 0 )); then
        msg_warn "Las ramas divergieron: $ahead commit(s) locales y $behind remoto(s)."
        print " 1) Merge  (git pull --no-rebase --no-edit)"
        print " 2) Rebase (git pull --rebase)"
        print " 3) Cancelar y revisar a mano"
        prompt_input "Elige [1-3]: " choice
        case "$choice" in
            1) git -C "$REPO_DIR" pull --no-rebase --no-edit "$r" "$br" ;;
            2) git -C "$REPO_DIR" pull --rebase "$r" "$br" ;;
            *) msg_info "Cancelado."; return 0 ;;
        esac
        (( $? != 0 )) && msg_err "Hay conflictos: resuélvelos en $REPO_DIR (git status) o aborta con git merge/rebase --abort."
        log_action "Git: pull divergente con $r (opción $choice)"
    else
        msg_err "El pull falló por otra causa (red, credenciales o cambios locales sin commitear)."
    fi
}

git_push_to() {
    local r="$1" br; br=$(git_branch_name)
    msg_info "Subiendo '$br' a '$r' ..."
    if git -C "$REPO_DIR" push "$r" "$br"; then msg_ok "Push a '$r' correcto."; return 0; fi
    msg_err "Falló el push a '$r'. Si el remoto tiene commits nuevos, haz 'pull' primero."
    return 1
}

git_push() {
    git_ok || return 0
    local br def_msg git_msg r
    br=$(git_branch_name)
    [[ -z "$br" ]] && { msg_err "HEAD desacoplado: cambia a una rama primero."; return 0; }

    if [[ -n "$(git -C "$REPO_DIR" status -s)" ]]; then
        msg_info "Archivos modificados:"
        git -C "$REPO_DIR" status -s
        print ""
        def_msg="Actualiza scripts ($(date +%F))"
        prompt_input "Mensaje para commit [Default: '$def_msg']: " git_msg
        git_msg="${git_msg:-$def_msg}"
        git -C "$REPO_DIR" add -A && git -C "$REPO_DIR" commit -m "$git_msg" || return 0
    else
        msg_warn "No hay cambios sin commitear."
        confirm "¿Subir solo los commits que ya están hechos?" || return 0
    fi

    git_pick_remote all || return 0
    if [[ "$GIT_REMOTE" == ALL ]]; then
        for r in ${(f)"$(git_remote_list)"}; do git_push_to "$r"; done
    else
        git_push_to "$GIT_REMOTE"
    fi
    log_action "Git: push a ${GIT_REMOTE} (${git_msg:-solo commits})"
}

git_branch() {
    git_ok || return 0
    local nb
    prompt_input "Nombre de la nueva rama (ej: feature-red): " nb
    [[ -z "$nb" ]] && return 0
    git -C "$REPO_DIR" check-ref-format --branch "$nb" &>/dev/null || { msg_err "Nombre de rama no válido."; return 0; }
    git -C "$REPO_DIR" checkout -b "$nb" && log_action "Git: nueva rama $nb"
}

git_restore() {
    git_ok || return 0
    if [[ -z "$(git -C "$REPO_DIR" status -s)" ]]; then msg_info "No hay cambios que descartar."; return 0; fi
    msg_warn "PELIGRO: se perderán TODOS los cambios sin commitear en archivos versionados:"
    git -C "$REPO_DIR" status -s
    confirm "¿Descartar los cambios locales?" || { msg_info "Operación cancelada."; return 0; }
    git -C "$REPO_DIR" restore . 2>/dev/null || git -C "$REPO_DIR" checkout -- .
    msg_ok "Cambios locales descartados."
    log_action "Git: cambios locales descartados"
}

menu_git() {
    MENU_HOOK=git_panel
    run_menu "GIT - CONTROL DE VERSIONES (multi-remoto)" \
        "#REPOSITORIO" \
        "Cambiar de repositorio|git_set_repo" \
        "Ver estado (rama y cambios)|git_status" \
        "Ver últimos commits|git_log" \
        "#SINCRONIZAR CON REMOTOS" \
        "Actualizar referencias de todos los remotos (fetch)|git_fetch" \
        "Probar autenticación SSH de los remotos|git_auth_check" \
        "Descargar cambios (pull seguro)|git_pull" \
        "Subir cambios (commit + push a un remoto o a todos)|git_push" \
        "#RAMAS Y LIMPIEZA" \
        "Crear nueva rama de trabajo|git_branch" \
        "Descartar cambios locales [PELIGRO]|git_restore"
}
