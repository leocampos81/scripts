#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: DOCKER (contenedores y Compose)
#  Corrige: el selector de contenedor ya no se ejecuta dentro de $(...) (se
#  tragaba la lista y el prompt), y todo usa "${DOCKER[@]}" (sudo solo si hace falta).
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

typeset -ga DOCKER COMPOSE_CMD
DOCKER=(docker)
COMPOSE_CMD=()
DK_PICKED=""
DK_COMPOSE_FILE=""

# Elige un contenedor y deja el nombre en DK_PICKED
dk_pick() {
    DK_PICKED=""
    local -a names
    names=( ${(f)"$("${DOCKER[@]}" ps -a --format '{{.Names}}  ({{.Status}})' 2>/dev/null)"} )
    pick_from_list "Contenedores:" "${names[@]}" || return 1
    DK_PICKED="${PICKED%%  *}"      # el nombre no lleva espacios; el estado viene tras dos espacios
    [[ -n "$DK_PICKED" ]]
}

dk_panel() {
    print ""
    local running total
    running=$("${DOCKER[@]}" ps -q 2>/dev/null | wc -l | tr -d ' ')
    total=$("${DOCKER[@]}" ps -aq 2>/dev/null | wc -l | tr -d ' ')
    kv "Contenedores" "$running en ejecución / $total en total"
    kv "Compose" "${DK_COMPOSE_FILE:-(sin proyecto seleccionado)}"
}

dk_ps()     { "${DOCKER[@]}" ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"; }
dk_images() { "${DOCKER[@]}" images; }

dk_stats() {
    msg_info "Snapshot de docker stats (no interactivo):"
    "${DOCKER[@]}" stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
}

dk_logs() {
    dk_pick || return 0
    local n
    prompt_input "Cantidad de líneas [Default: 50]: " n
    valid_num "$n" || n=50
    if confirm "¿Seguir en vivo? (Ctrl+C para volver al menú)"; then
        run_interruptible "${DOCKER[@]}" logs -f --tail "$n" "$DK_PICKED"
    else
        "${DOCKER[@]}" logs --tail "$n" "$DK_PICKED"
    fi
    log_action "Docker: logs de $DK_PICKED"
}

dk_ctl() {
    dk_pick || return 0
    local act
    print " 1) Restart | 2) Stop | 3) Start"
    prompt_input "Acción [1-3]: " act
    case "$act" in
        1) if confirm "¿Reiniciar '$DK_PICKED'?"; then "${DOCKER[@]}" restart "$DK_PICKED"; log_action "Docker: restart $DK_PICKED"; fi ;;
        2) if confirm "¿Detener '$DK_PICKED'?"; then "${DOCKER[@]}" stop "$DK_PICKED"; log_action "Docker: stop $DK_PICKED"; fi ;;
        3) "${DOCKER[@]}" start "$DK_PICKED"; log_action "Docker: start $DK_PICKED" ;;
        *) msg_warn "Acción no válida." ;;
    esac
}

# Shell interactivo dentro de un contenedor (bash si existe, si no sh)
dk_shell() {
    dk_pick || return 0
    msg_info "Entrando a '$DK_PICKED' (escribe 'exit' para volver)..."
    "${DOCKER[@]}" exec -it "$DK_PICKED" bash 2>/dev/null || "${DOCKER[@]}" exec -it "$DK_PICKED" sh
    log_action "Docker: shell en $DK_PICKED"
}

dk_prune() {
    msg_info "Uso de disco actual de Docker:"
    "${DOCKER[@]}" system df
    print ""
    msg_warn "Se eliminarán contenedores detenidos, redes sin uso e imágenes huérfanas."
    confirm "¿Ejecutar 'docker system prune -f'?" || { msg_info "Cancelado."; return 0; }
    "${DOCKER[@]}" system prune -f
    log_action "Docker: system prune"
}

# --- Docker Compose -------------------------------------------------------------
dk_compose_detect() {
    COMPOSE_CMD=()
    if "${DOCKER[@]}" compose version &>/dev/null; then COMPOSE_CMD=("${DOCKER[@]}" compose)
    elif command -v docker-compose &>/dev/null; then COMPOSE_CMD=("${SUDO[@]}" docker-compose); fi
    (( ${#COMPOSE_CMD} )) || { msg_warn "No hay 'docker compose' ni 'docker-compose' disponibles."; return 1; }
}

dk_compose_need() {
    dk_compose_detect || return 1
    [[ -n "$DK_COMPOSE_FILE" && -f "$DK_COMPOSE_FILE" ]] && return 0
    msg_warn "Primero selecciona un proyecto Compose."; return 1
}

dk_compose_select() {
    local -a found
    found=( ${(f)"$(auto_find 4 -type f '(' -name 'docker-compose.y*ml' -o -name 'compose.y*ml' ')' | sort)"} )
    found+=("[escribir ruta manualmente]")
    pick_from_list "Proyectos Compose bajo $AUTO_BASE:" "${found[@]}" || return 0
    local choice="$PICKED"
    [[ "$choice" == "[escribir ruta manualmente]" ]] && prompt_input "Ruta del archivo compose: " choice
    [[ -z "$choice" ]] && return 0
    [[ -f "$choice" ]] || { msg_err "No existe: $choice"; return 0; }
    DK_COMPOSE_FILE="${choice:A}"
    msg_ok "Proyecto Compose: $DK_COMPOSE_FILE"
}

dk_compose_ps()   { dk_compose_need || return 0; "${COMPOSE_CMD[@]}" -f "$DK_COMPOSE_FILE" ps; }
dk_compose_logs() {
    dk_compose_need || return 0
    msg_info "Logs en vivo (Ctrl+C para volver)..."
    run_interruptible "${COMPOSE_CMD[@]}" -f "$DK_COMPOSE_FILE" logs -f --tail 100
}
dk_compose_up() {
    dk_compose_need || return 0
    msg_info "Servicios definidos:"; "${COMPOSE_CMD[@]}" -f "$DK_COMPOSE_FILE" config --services
    confirm "¿Levantar el proyecto (up -d)?" || return 0
    "${COMPOSE_CMD[@]}" -f "$DK_COMPOSE_FILE" up -d
    log_action "Compose: up -d $DK_COMPOSE_FILE"
}
dk_compose_down() {
    dk_compose_need || return 0
    msg_warn "Se detendrán y eliminarán los contenedores del proyecto (los volúmenes se conservan)."
    confirm "¿Ejecutar 'down'?" || return 0
    "${COMPOSE_CMD[@]}" -f "$DK_COMPOSE_FILE" down
    log_action "Compose: down $DK_COMPOSE_FILE"
}

menu_docker() {
    if ! need docker; then pause_screen; return 0; fi
    if docker info &>/dev/null; then DOCKER=(docker); else DOCKER=("${SUDO[@]}" docker); fi
    MENU_HOOK=dk_panel
    run_menu "DOCKER - CONTENEDORES Y COMPOSE" \
        "#CONTENEDORES" \
        "Ver contenedores (docker ps -a)|dk_ps" \
        "Monitoreo CPU/RAM (docker stats, snapshot)|dk_stats" \
        "Logs de un contenedor|dk_logs" \
        "Reiniciar / Detener / Iniciar un contenedor|dk_ctl" \
        "Shell dentro de un contenedor|dk_shell|nopause" \
        "Listar imágenes|dk_images" \
        "Limpieza general (docker system prune)|dk_prune" \
        "#DOCKER COMPOSE" \
        "Seleccionar proyecto (autodetección)|dk_compose_select" \
        "Estado de los servicios|dk_compose_ps" \
        "Levantar (up -d)|dk_compose_up" \
        "Logs en vivo|dk_compose_logs" \
        "Detener y eliminar (down)|dk_compose_down"
}
