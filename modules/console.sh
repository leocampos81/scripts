#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: CONSOLA DEVOPS
#  Escribes comandos reales (docker, ansible, terraform, git, kubectl...) con la
#  velocidad de la shell, pero con el contexto del dashboard y guardarraíles:
#    - Contexto automático: inventario/limit/playbook de Ansible, proyecto y
#      var-file de Terraform, repo Git activo y sudo para Docker si hace falta.
#    - Sin 'eval': la línea se parsea a argumentos; solo '|' hacia filtros.
#    - Lista de herramientas permitidas (ampliable con PROM_CONSOLE_ALLOW).
#    - Acciones destructivas piden confirmación (CONFIRMAR en las graves).
#    - Historial persistente (↑/↓), modo --dry (muestra el comando resuelto),
#      código de salida y duración de cada comando, todo registrado en el log.
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

typeset -ga CON_ALLOW CON_HIST CON_CMD CON_C1 CON_C2 CON_C3
typeset -gA CON_ALIAS
CON_USE=""
CON_DRY=0
CON_CWD=""
CON_NSEG=0
CON_SUDO_DOCKER=0
CON_HISTFILE="$STATE_DIR/console_history"
CON_FILTERS="grep egrep head tail wc sort uniq cut jq column nl tr less cat"

CON_ALLOW=(docker podman docker-compose ansible ansible-playbook ansible-inventory ansible-galaxy
           ansible-vault ansible-lint ansible-doc ansible-config terraform tofu git kubectl helm
           systemctl journalctl ssh scp rsync curl ping dig ss ip trivy gitleaks checkov tfsec
           hadolint yamllint jq yq)
[[ -n "${PROM_CONSOLE_ALLOW:-}" ]] && CON_ALLOW+=( ${=PROM_CONSOLE_ALLOW} )
CON_ALIAS=( d docker  dc "docker compose"  a ansible  ap ansible-playbook  ai ansible-inventory
            ag ansible-galaxy  av ansible-vault  tf terraform  g git  k kubectl  h helm )

# --- Contexto ------------------------------------------------------------------
con_ctx() {
    local br="-" tfd="${TF_DIR:t}" inv="${ANS_INV:t}"
    if git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        br=$(git -C "$REPO_DIR" branch --show-current); br="${br:-HEAD}"
    fi
    print -rn -- "ns=${CON_USE:-ninguno} · inv=${inv:--} · tf=${tfd:--} · git=$br · dry=$(( CON_DRY )) "
}

con_ctx_full() {
    section "CONTEXTO DE LA CONSOLA"
    kv "Namespace" "${CON_USE:-ninguno}   (:use docker|ansible|terraform|git|kubectl|none)"
    kv "Dry-run" "$( (( CON_DRY )) && print ACTIVADO || print desactivado )"
    kv "Docker" "$( (( CON_SUDO_DOCKER )) && print 'con sudo' || print 'directo' )"
    kv "Inventario" "${ANS_INV:-(ninguno)  :inv}"
    kv "Playbook" "${ANS_PLAY:-(ninguno)  :play}"
    kv "Límite" "${ANS_LIMIT:-(todos)  :limit}"
    kv "Terraform" "${TF_DIR:-(ninguno)  :tf}"
    kv "Var-file" "${TF_VARFILE:-(ninguno)  :var}"
    kv "Repo Git" "$REPO_DIR   (:repo)"
    kv "Compose" "${DK_COMPOSE_FILE:-(ninguno)  :compose}"
}

con_detect_docker() {
    CON_SUDO_DOCKER=0
    command -v docker &>/dev/null || return 0
    docker info &>/dev/null || { (( EUID != 0 )) && CON_SUDO_DOCKER=1; }
    return 0
}

con_help() {
    cat <<'EOF'
 CONSOLA DEVOPS - escribe comandos reales; el dashboard pone el contexto.

   docker ps -a            ansible all -m ping         terraform plan
   git log --oneline       ap site.yml --check         kubectl get pods
   ps -a                   (con ':use docker' no hace falta escribir 'docker')

 Atajos : d=docker  dc=docker compose  a=ansible  ap=ansible-playbook  ai=ansible-inventory
          ag=ansible-galaxy  av=ansible-vault  tf=terraform  g=git  k=kubectl  h=helm
 Pipes  : solo hacia filtros (grep head tail wc sort uniq cut jq column nl tr less cat)
          ej:  docker ps -a | grep web
 Meta   : :ctx  :use <herramienta|none>  :dry [on|off]  :tools  :history [n]  :alias
          :inv  :play  :limit <patrón>  :tf  :var  :repo  :compose   (eligen el contexto)
          :sh  (shell real, sin guardarraíles)   :clear   :q  (o Ctrl+D) para salir
 Historial: ↑/↓ y  !!  (último)  !N (número de :history)
 Guardarraíles: lo destructivo pide confirmación; lo grave exige escribir CONFIRMAR.
EOF
}

con_tools() {
    local t
    section "HERRAMIENTAS PERMITIDAS"
    for t in "${CON_ALLOW[@]}"; do
        if command -v "$t" &>/dev/null; then print -rn -- " ${C_GRN}[ok]${C_RST} ${(r:18:)t}"
        else print -rn -- " [--] ${(r:18:)t}"; fi
        (( ++n % 3 == 0 )) && print ""
    done
    print ""; n=0
}

# --- Historial -----------------------------------------------------------------
con_sensitive() { [[ "$1" =~ '(-p[[:space:]]|--password|--token|passwd|secret|token=|api[_-]?key|vault-password)' ]]; }

con_history_load() {
    mkdir -p "$STATE_DIR" 2>/dev/null; ( umask 077; touch "$CON_HISTFILE" 2>/dev/null )
    local l; local -a lines
    CON_HIST=()
    lines=( ${(f)"$(tail -n 500 "$CON_HISTFILE" 2>/dev/null)"} )
    for l in "${lines[@]}"; do CON_HIST+=("$l"); print -s -- "$l"; done
}

con_history_add() {
    con_sensitive "$1" && return 0                 # no guardar líneas con posibles secretos
    [[ "${CON_HIST[-1]:-}" == "$1" ]] && return 0
    CON_HIST+=("$1"); print -s -- "$1"
    ( umask 077; print -r -- "$1" >> "$CON_HISTFILE" )
}

# --- Parseo: línea -> segmentos (sin eval) ---------------------------------------
con_store_seg() {   # con_store_seg N  (usa el array local 'cur' del llamador)
    case "$1" in
        1) CON_C1=("${cur[@]}") ;;
        2) CON_C2=("${cur[@]}") ;;
        3) CON_C3=("${cur[@]}") ;;
    esac
}

con_parse() {
    local line="$1" t n=1 w
    local -a raw cur
    CON_C1=(); CON_C2=(); CON_C3=(); CON_NSEG=0
    raw=( ${(z)line} )
    (( ${#raw} )) || return 1

    for t in "${raw[@]}"; do
        case "$t" in
            ';'|'&&'|'||'|'&'|'>'|'>>'|'<'|'<<'|'2>'|'2>&1'|'&>')
                msg_err "Operador '$t' no soportado: un comando por línea (solo '|' hacia filtros). Usa :sh para una shell real."
                return 1 ;;
        esac
        if [[ "$t" != \'* && ( "$t" == *'$('* || "$t" == *'`'* ) ]]; then
            msg_err "Sustitución de comandos no permitida en la consola. Usa :sh."; return 1
        fi
    done

    cur=()
    for t in "${raw[@]}"; do
        if [[ "$t" == '|' ]]; then
            (( ${#cur} )) || { msg_err "Pipe sin comando antes."; return 1; }
            con_store_seg $n; n=$(( n + 1 ))
            (( n > 3 )) && { msg_err "Máximo 3 etapas en un pipe."; return 1; }
            cur=()
        else
            w="${(Q)t}"
            [[ "$w" == '~/'* ]] && w="$HOME/${w#\~/}"
            cur+=("$w")
        fi
    done
    (( ${#cur} )) || { msg_err "Pipe sin comando después."; return 1; }
    con_store_seg $n
    CON_NSEG=$n

    local -a f
    for t in 2 3; do
        (( t > CON_NSEG )) && break
        case $t in 2) f=("${CON_C2[@]}") ;; 3) f=("${CON_C3[@]}") ;; esac
        if [[ " $CON_FILTERS " != *" ${f[1]} "* ]]; then
            msg_err "Tras un pipe solo se permiten filtros: $CON_FILTERS"; return 1
        fi
    done
    return 0
}

# --- Resolución: alias, namespace y contexto -----------------------------------
con_resolve() {
    local -a w=("$@")
    local first="${w[1]}" tool a
    CON_CMD=(); CON_CWD=""

    # alias (puede expandirse a varias palabras, p.ej. dc = docker compose)
    if (( ${+CON_ALIAS[$first]} )); then w=( ${=CON_ALIAS[$first]} "${w[@]:1}" ); first="${w[1]}"; fi
    # namespace por defecto: 'ps -a' -> 'docker ps -a'
    if (( ! ${CON_ALLOW[(Ie)$first]} )) && [[ -n "$CON_USE" ]]; then
        w=( ${=CON_USE} "${w[@]}" ); first="${w[1]}"
    fi
    if (( ! ${CON_ALLOW[(Ie)$first]} )); then
        msg_err "'$first' no está en la lista de herramientas permitidas (:tools). Usa :use <herramienta> o :sh."
        return 1
    fi
    # terraform -> tofu si solo está OpenTofu
    if [[ "$first" == terraform ]] && ! command -v terraform &>/dev/null && command -v tofu &>/dev/null; then
        w[1]=tofu; first=tofu
    fi
    if ! command -v "$first" &>/dev/null; then
        msg_err "'$first' no está instalado. (':tools' muestra qué hay disponible)"; return 1
    fi
    tool="$first"

    case "$tool" in
        docker)
            (( CON_SUDO_DOCKER )) && w=( sudo "${w[@]}" ) ;;
        ansible|ansible-playbook|ansible-inventory)
            if [[ -n "$ANS_INV" ]]; then
                if (( ! ${w[(Ie)-i]} )) && [[ -z "${(M)w[@]:#(-i*|--inventory*)}" ]]; then w+=( -i "$ANS_INV" ); fi
            fi
            if [[ "$tool" != ansible-inventory && -n "$ANS_LIMIT" ]]; then
                if (( ! ${w[(Ie)-l]} )) && [[ -z "${(M)w[@]:#(--limit*|-l*)}" ]]; then w+=( --limit "$ANS_LIMIT" ); fi
            fi
            # ansible.cfg y roles/ del proyecto: se ejecuta desde la carpeta del playbook/inventario
            if [[ -n "$ANS_PLAY" ]]; then CON_CWD="${ANS_PLAY:h}"
            elif [[ -n "$ANS_INV" ]]; then CON_CWD="${ANS_INV:h}"; fi ;;
        terraform|tofu)
            if [[ -n "$TF_DIR" && -z "${(M)w[@]:#-chdir=*}" ]]; then w=( "${w[1]}" "-chdir=$TF_DIR" "${w[@]:1}" ); fi
            if [[ -n "$TF_VARFILE" && " ${w[*]} " == *" plan"* || " ${w[*]} " == *" apply"* || " ${w[*]} " == *" destroy"* ]]; then
                [[ -n "$TF_VARFILE" && -z "${(M)w[@]:#-var-file*}" ]] && w+=( "-var-file=$TF_VARFILE" )
            fi ;;
        git)
            if [[ -z "${(M)w[@]:#-C}" ]] && git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
                w=( git -C "$REPO_DIR" "${w[@]:1}" )
            fi ;;
    esac
    CON_CMD=("${w[@]}")
    return 0
}

# --- Guardarraíles ---------------------------------------------------------------
# Devuelve 0 = ejecutar, 1 = cancelado.
con_guard() {
    local s=" ${CON_CMD[*]} " lvl=0 why="" typed tool="${CON_CMD[1]}" mod i
    [[ "$tool" == sudo ]] && tool="${CON_CMD[2]}"

    case "$tool" in
        docker|podman)
            if [[ $s == *" system prune"* || $s == *" volume prune"* || $s == *" image prune -a"* || $s == *" volume rm"* || $s == *" network rm"* ]]; then
                lvl=2; why="elimina recursos de Docker (volúmenes/imágenes/redes): los datos no se recuperan"
            elif [[ $s == *" rm "* || $s == *" rmi "* || $s == *" kill "* || $s == *" stop "* || $s == *" restart "* ]]; then
                lvl=1; why="detiene o elimina contenedores/imágenes"
            fi ;;
        terraform|tofu)
            if [[ $s == *" destroy"* || $s == *"-auto-approve"* || $s == *" state rm"* || $s == *" force-unlock"* ]]; then
                lvl=2; why="modifica o elimina infraestructura sin revisión previa (destroy / auto-approve / state rm)"
            elif [[ $s == *" apply"* || $s == *" import "* || $s == *" taint "* || $s == *" untaint "* || $s == *" state mv"* ]]; then
                lvl=1; why="cambia infraestructura o el estado de Terraform"
            fi ;;
        ansible-playbook)
            if [[ $s != *" --check"* && $s != *" -C "* && $s != *"--syntax-check"* && $s != *"--list-"* ]]; then
                lvl=1; why="ejecuta cambios REALES (no es dry-run: considera --check --diff primero)"
            fi ;;
        ansible)
            mod="command"
            for (( i=1; i<=${#CON_CMD}; i++ )); do
                [[ "${CON_CMD[i]}" == -m || "${CON_CMD[i]}" == --module-name ]] && mod="${CON_CMD[i+1]}"
            done
            if [[ " ping setup debug stat find slurp gather_facts " != *" $mod "* ]]; then
                lvl=1; why="módulo '$mod': ejecuta cambios o comandos en hosts remotos"
            fi ;;
        git)
            if [[ $s == *" push --force"* || $s == *" push -f"* || $s == *" reset --hard"* || $s == *" clean -f"* || $s == *" clean -d"* || $s == *" branch -D"* || $s == *" push --delete"* || $s == *" push origin :"* ]]; then
                lvl=2; why="reescribe o descarta historial/archivos de forma irreversible"
            elif [[ $s == *" rebase"* || $s == *" commit --amend"* || $s == *" push --force-with-lease"* || $s == *" checkout -- "* || $s == *" restore "* || $s == *" stash drop"* ]]; then
                lvl=1; why="modifica historial o descarta cambios locales"
            fi ;;
        kubectl)
            if [[ $s == *" delete namespace"* || $s == *" delete ns "* || $s == *" delete --all"* || $s == *" drain "* ]]; then
                lvl=2; why="elimina namespaces/recursos completos o vacía un nodo"
            elif [[ $s == *" delete "* || $s == *" apply "* || $s == *" replace "* || $s == *" patch "* || $s == *" scale "* || $s == *" rollout restart"* || $s == *" edit "* || $s == *" cordon "* ]]; then
                lvl=1; why="cambia el estado del clúster"
            fi ;;
        helm)
            if [[ $s == *" uninstall "* || $s == *" delete "* ]]; then lvl=2; why="elimina un release"
            elif [[ $s == *" install "* || $s == *" upgrade "* || $s == *" rollback "* ]]; then lvl=1; why="despliega o cambia un release"; fi ;;
        systemctl)
            if [[ $s == *" stop "* || $s == *" disable "* || $s == *" mask "* || $s == *" restart "* || $s == *" poweroff"* || $s == *" reboot"* || $s == *" halt"* || $s == *" isolate "* ]]; then
                lvl=1; why="cambia el estado de servicios del sistema"
                [[ $s == *" ssh"* || $s == *" NetworkManager"* || $s == *" network"* || $s == *" poweroff"* || $s == *" reboot"* || $s == *" halt"* ]] \
                    && { lvl=2; why="puede dejarte sin acceso remoto o apagar el equipo"; }
            fi ;;
        rsync)
            [[ $s == *" --delete"* ]] && { lvl=2; why="--delete borra archivos en el destino"; } ;;
    esac

    (( lvl == 0 )) && return 0
    if (( lvl == 1 )); then
        msg_warn "Acción sensible: $why."
        confirm "¿Ejecutar?" || { msg_info "Cancelado."; return 1; }
    else
        msg_warn "ACCIÓN DESTRUCTIVA: $why."
        prompt_input "Escribe CONFIRMAR para ejecutar: " typed
        [[ "$typed" == CONFIRMAR ]] || { msg_info "Cancelado."; return 1; }
    fi
    return 0
}

# --- Ejecución ---------------------------------------------------------------------
con_execute() {
    local t0=$SECONDS rc cwd="$CON_CWD"
    local -a c1=("${CON_CMD[@]}") c2=("${CON_C2[@]}") c3=("${CON_C3[@]}")
    (
        trap - INT                       # Ctrl+C corta SOLO el comando, no la consola
        [[ -n "$cwd" && -d "$cwd" ]] && cd "$cwd"
        case $CON_NSEG in
            1) "${c1[@]}" ;;
            2) "${c1[@]}" | "${c2[@]}" ;;
            3) "${c1[@]}" | "${c2[@]}" | "${c3[@]}" ;;
        esac
    )
    rc=$?
    CON_LASTRC=$rc
    if (( rc == 0 )); then print -r -- "${C_GRN}[rc=0 · $(( SECONDS - t0 ))s]${C_RST}"
    else print -r -- "${C_RED}[rc=$rc · $(( SECONDS - t0 ))s]${C_RST}"; fi
    return $rc
}

con_run() {
    local line="$1" logline
    con_parse "$line" || return 1
    con_resolve "${CON_C1[@]}" || return 1

    if (( CON_DRY )); then
        print -r -- "${C_YEL}[dry]${C_RST} ${CON_CWD:+(cd ${CON_CWD:t}) }${(j: :)${(@q)CON_CMD}}$( (( CON_NSEG > 1 )) && print -rn -- ' | ...' )"
        return 0
    fi
    con_guard || return 1
    con_execute
    local rc=$?
    if con_sensitive "$line"; then logline="(línea con posible secreto omitida)"; else logline="$line"; fi
    log_action "Consola: $logline (rc=$rc)"
    return $rc
}

# --- Comandos meta (:xxx) ---------------------------------------------------------
con_meta() {
    local cmd="${1%% *}" arg=""
    [[ "$1" == *" "* ]] && arg="${1#* }"
    case "$cmd" in
        help|h|'?') con_help ;;
        ctx) con_ctx_full ;;
        tools) local n=0; con_tools ;;
        alias) local k; for k in ${(ko)CON_ALIAS}; do printf "  %-4s = %s\n" "$k" "${CON_ALIAS[$k]}"; done ;;
        use)
            case "$arg" in
                ''|none|ninguno) CON_USE=""; msg_ok "Sin namespace." ;;
                docker|podman|ansible|ansible-playbook|terraform|tofu|git|kubectl|helm|systemctl)
                    CON_USE="$arg"; msg_ok "Namespace: $arg (ahora 'ps -a' equivale a '$arg ps -a')" ;;
                *) msg_err "Uso: :use docker|ansible|terraform|tofu|git|kubectl|helm|systemctl|none" ;;
            esac ;;
        dry)
            case "$arg" in
                on|1) CON_DRY=1 ;; off|0) CON_DRY=0 ;; *) CON_DRY=$(( ! CON_DRY )) ;;
            esac
            msg_info "Dry-run: $( (( CON_DRY )) && print ACTIVADO '(solo muestra el comando resuelto)' || print desactivado )" ;;
        history|hist)
            local n="${arg:-20}" i start
            valid_num "$n" || n=20
            start=$(( ${#CON_HIST} - n + 1 )); (( start < 1 )) && start=1
            for (( i=start; i<=${#CON_HIST}; i++ )); do printf " %4d  %s\n" "$i" "${CON_HIST[i]}"; done ;;
        inv)     (( ${+functions[ans_select_inv]} )) && ans_select_inv   || msg_err "Falta el módulo iac." ;;
        play)    (( ${+functions[ans_select_play]} )) && ans_select_play || msg_err "Falta el módulo iac." ;;
        limit)
            if [[ -z "$arg" ]]; then ANS_LIMIT=""; msg_ok "Límite eliminado."
            elif [[ "$arg" =~ '^[A-Za-z0-9_.:,!&*@-]+$' ]]; then ANS_LIMIT="$arg"; msg_ok "Límite: $ANS_LIMIT"
            else msg_err "Patrón no válido."; fi ;;
        tf)      (( ${+functions[tf_select_dir]} )) && tf_select_dir || msg_err "Falta el módulo iac." ;;
        var)     (( ${+functions[tf_select_varfile]} )) && tf_select_varfile || msg_err "Falta el módulo iac." ;;
        repo)    (( ${+functions[git_set_repo]} )) && git_set_repo || msg_err "Falta el módulo git." ;;
        compose) (( ${+functions[dk_compose_select]} )) && dk_compose_select || msg_err "Falta el módulo docker." ;;
        clear)   clear ;;
        sh)
            msg_warn "Shell real: sin guardarraíles ni registro. 'exit' para volver."
            log_action "Consola: shell real abierta"
            ( trap - INT; ${SHELL:-/bin/sh} -i ) ;;
        *) msg_err "Comando meta desconocido: :$cmd  (usa :help)" ;;
    esac
}

# --- Bucle principal -----------------------------------------------------------------
console_start() {
    if [[ ! -t 0 || ! -t 1 ]]; then msg_err "La consola requiere una terminal interactiva."; return 1; fi
    con_detect_docker
    con_history_load
    local cmdline rc idx
    clear
    print "══════════════════════════════════════════════════════════════════════"
    print "  CONSOLA DEVOPS · comandos reales con contexto y guardarraíles"
    print "  :help ayuda · :ctx contexto · :dry simula · ↑ historial · :q / Ctrl+D salir"
    print "══════════════════════════════════════════════════════════════════════"
    while true; do
        print ""
        print -r -- "${C_CYN}$(con_ctx)${C_RST}"
        cmdline=""
        if zle -l &>/dev/null; then
            vared -h -p "prom ▸ " cmdline; rc=$?
        else
            prompt_input "prom> " cmdline; rc=$?
        fi
        if (( _PROM_EOF )); then _PROM_EOF=0; break; fi          # Ctrl+D en línea vacía
        (( rc != 0 )) && break
        cmdline="${cmdline##[[:space:]]#}"; cmdline="${cmdline%%[[:space:]]#}"
        [[ -z "$cmdline" ]] && continue

        # expansión de historial: !! y !N
        if [[ "$cmdline" == '!!' ]]; then
            cmdline="${CON_HIST[-1]:-}"; [[ -z "$cmdline" ]] && { msg_warn "Historial vacío."; continue; }
            print -r -- "  → $cmdline"
        elif [[ "$cmdline" == '!'<-> ]]; then
            idx="${cmdline#!}"; cmdline="${CON_HIST[idx]:-}"
            [[ -z "$cmdline" ]] && { msg_warn "No existe esa entrada (:history)."; continue; }
            print -r -- "  → $cmdline"
        fi

        case "$cmdline" in
            ':q'|':quit'|'exit'|'quit'|'q') break ;;
            :*) con_history_add "$cmdline"; con_meta "${cmdline#:}" ;;
            *)  con_history_add "$cmdline"; con_run "$cmdline" ;;
        esac
    done
    print ""
    log_action "Consola: sesión cerrada"
}
