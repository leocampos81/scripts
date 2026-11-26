#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: SYSADMIN  -  diagnóstico, recursos, servicios, logs, paquetes y seguridad del host
#  Se carga con 'source' desde prom_claude.sh (no se ejecuta directamente).
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

# ==== DIAGNÓSTICO Y ESTADO ====
mem_stats() {
    local t a st sf
    read -r t a st sf <<< "$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2} END{printf "%.0f %.0f %.0f %.0f", t*1024, a*1024, st*1024, sf*1024}' /proc/meminfo 2>/dev/null)"
    MEM_TOTAL=${t:-0}; MEM_AVAIL=${a:-0}; SWAP_TOTAL=${st:-0}; SWAP_FREE=${sf:-0}
}

# Imprime nº de actualizaciones pendientes, o "N/D" si no se puede saber.
updates_pending() {
    local n=""
    case "$PKG_MGR" in
        apt)     n=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst') ;;
        dnf|yum) n=$("$PKG_MGR" -C -q check-update 2>/dev/null | grep -cE '^[[:alnum:]_.+-]+\.[[:alnum:]_]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+') ;;
        pacman)  command -v checkupdates &>/dev/null && n=$(checkupdates 2>/dev/null | wc -l) ;;
        zypper)  n=$(zypper --no-refresh -q list-updates 2>/dev/null | grep -c '^v *|') ;;
        apk)     n=$(apk -s upgrade 2>/dev/null | grep -c '^(') ;;
    esac
    n="${n//[[:space:]]/}"
    [[ "$n" == <-> ]] && print "$n" || print "N/D"
}

health_check() {
    print "===================================================================="
    print "               PANORAMA GENERAL DEL SERVIDOR (HEALTH)"
    print -r -- "               $(date '+%Y-%m-%d %H:%M:%S')"
    print "===================================================================="

    local kernel arch up cpu cores flag
    kernel=$(uname -r); arch=$(uname -m)
    up=$(uptime -p 2>/dev/null | sed 's/^up //')
    [[ -z "$up" ]] && up=$(uptime 2>/dev/null | sed 's/^.*up *//; s/, *[0-9]* user.*//')
    cpu=$(lscpu 2>/dev/null | awk -F: '/^Model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
    [[ -z "$cpu" ]] && cpu=$(awk -F: '/model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
    cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null)

    section "SISTEMA Y HARDWARE"
    kv "Hostname" "$HOST"
    kv "OS" "$OS_NAME"
    kv "Kernel" "$kernel ($arch)"
    kv "Uptime" "${up:-N/D}"
    kv "CPU" "${cpu:-N/D}"
    kv "Núcleos" "${cores:-N/D} vCPU"

    mem_stats
    local ram_used=$(( MEM_TOTAL - MEM_AVAIL )) ram_pct=0 swap_used=$(( SWAP_TOTAL - SWAP_FREE ))
    (( MEM_TOTAL > 0 )) && ram_pct=$(( ram_used * 100 / MEM_TOTAL ))
    flag=""; (( ram_pct >= 90 )) && flag="  ${C_YEL}[!] uso alto${C_RST}"
    kv "RAM" "$(human_bytes $ram_used) / $(human_bytes $MEM_TOTAL) (${ram_pct}%)${flag}"
    if (( SWAP_TOTAL == 0 )); then
        kv "Swap" "No configurado"
    elif (( swap_used > 0 )); then
        kv "Swap" "${C_YEL}¡ALERTA!${C_RST} $(human_bytes $swap_used) de $(human_bytes $SWAP_TOTAL) en uso"
    else
        kv "Swap" "No utilizado ($(human_bytes $SWAP_TOTAL))"
    fi

    local l1 l5 l15 rest
    read -r l1 l5 l15 rest < /proc/loadavg 2>/dev/null
    flag=""
    awk -v l="${l1:-0}" -v c="${cores:-1}" 'BEGIN{exit !(l>c)}' && flag="  ${C_YEL}[!] sobre el nº de núcleos${C_RST}"
    kv "Load avg" "${l1:-N/D}, ${l5:-N/D}, ${l15:-N/D}${flag}"
    [[ -f /var/run/reboot-required ]] && kv "Reinicio" "${C_YEL}[!] Requerido (reboot-required)${C_RST}"

    section "ACTUALIZACIONES DEL SISTEMA"
    local upd; upd=$(updates_pending)
    if [[ "$upd" == <-> ]]; then
        if (( upd > 0 )); then print -r -- " ${C_YEL}[!]${C_RST} Paquetes pendientes: $upd actualizaciones"
        else print -r -- " ${C_GRN}[OK]${C_RST} Sistema actualizado (sin pendientes)"; fi
    else
        print " [?] No se pudo determinar (gestor: $PKG_MGR)"
    fi

    section "ALMACENAMIENTO"
    printf " %-22s %8s %8s %8s %5s\n" "Montaje" "Total" "Usado" "Disp" "Uso"
    df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {
        u=$5; sub("%","",u); flag=""; if (u+0>=85) flag="  [!] casi lleno"
        printf " %-22.22s %8s %8s %8s %5s%s\n", $6, $2, $3, $4, $5, flag
    }'

    section "CONECTIVIDAD DE RED PRINCIPAL"
    if command -v ip &>/dev/null; then
        local iface ip4 gw
        iface=$(ip route show default 2>/dev/null | awk '/default/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
        gw=$(ip route show default 2>/dev/null | awk '/default/{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')
        [[ -n "$iface" ]] && ip4=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4; exit}')
        kv "Interfaz" "${iface:-N/A}"
        kv "IP Local" "${ip4:-N/A}"
        kv "Gateway" "${gw:-N/A}"
        local ports; ports=$(ss -tuln 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
        kv "Puertos" "${ports:-N/D} sockets en escucha (TCP+UDP)"
    else
        print " (comando 'ip' no disponible: instala iproute2)"
    fi

    section "SERVICIOS CRÍTICOS (activos)"
    if have_systemd; then
        local -a critical=(ssh sshd docker containerd cron crond systemd-resolved firewalld ufw
                           NetworkManager systemd-networkd network chronyd systemd-timesyncd ntp
                           auditd rsyslog fail2ban nginx apache2 httpd mariadb mysql postgresql
                           mssql-server mongod redis redis-server)
        local -A seen
        local svc sid found=0
        for svc in "${critical[@]}"; do
            systemctl is-active --quiet "$svc" 2>/dev/null || continue
            sid=$(systemctl show -p Id --value "$svc" 2>/dev/null)
            sid="${sid:-$svc}"
            (( ${+seen[$sid]} )) && continue      # evita duplicar alias (ssh/sshd)
            seen[$sid]=1; found=1
            print -r -- " ${C_GRN}[ OK ]${C_RST} ${sid%.service}"
        done
        (( found == 0 )) && print " No se detectaron servicios críticos corriendo."

        local failed; failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
        if [[ -n "$failed" ]]; then
            print -r -- " ${C_RED}[FALLO]${C_RST} Unidades en estado failed:"
            print -r -- "$failed" | sed 's/^/          - /'
        else
            print -r -- " ${C_GRN}[ OK ]${C_RST} Sin unidades fallidas (systemctl --failed)"
        fi
        if command -v journalctl &>/dev/null; then
            local jerr; jerr=$(journalctl -p err -b -q --no-pager 2>/dev/null | wc -l | tr -d ' ')
            print -r -- " [ i ] Entradas 'err' en este arranque: ${jerr:-0} (journalctl -p err -b)"
        fi
    else
        print " (systemd no disponible: sección omitida)"
    fi

    section "BASES DE DATOS DETECTADAS"
    detect_db_engines
    if (( DB_FOUND == 0 )); then
        print " (No se detectaron motores de BBDD en el PATH ni procesos activos)"
    else
        print " (Menú Sysadmin > Bases de datos para conectar y listar BBDD)"
    fi

    section "ESTADO DE PROCESOS"
    local total zombies
    total=$(ps -eo pid= 2>/dev/null | wc -l | tr -d ' ')
    zombies=$(ps -eo stat= 2>/dev/null | grep -c '^Z')
    kv "Total procs" "${total:-N/D} procesos"
    if (( zombies > 0 )); then kv "Zombies" "${C_YEL}¡ALERTA!${C_RST} $zombies procesos Z"
    else kv "Zombies" "0 (saludable)"; fi
    print ""
    print " TOP 5 RAM:"
    ps -eo user:14,pmem,pcpu,comm --sort=-pmem 2>/dev/null | head -n 6 | sed 's/^/  /'
    print ""
    print " TOP 5 CPU:"
    ps -eo user:14,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -n 6 | sed 's/^/  /'
    print ""
}

act_health() {
    clear
    health_check
    log_action "Panorama general del servidor generado"
}

metrics_output() {
    mem_stats
    local l1 l5 l15 rest upt procs zomb ports upd failed
    read -r l1 l5 l15 rest < /proc/loadavg 2>/dev/null
    upt=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)
    procs=$(ps -eo pid= 2>/dev/null | wc -l | tr -d ' ')
    zomb=$(ps -eo stat= 2>/dev/null | grep -c '^Z')
    ports=$(ss -tuln 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
    upd=$(updates_pending)

    print "# HELP prom_claude_load Load average del host"
    print "# TYPE prom_claude_load gauge"
    print "prom_claude_load{period=\"1m\"} ${l1:-0}"
    print "prom_claude_load{period=\"5m\"} ${l5:-0}"
    print "prom_claude_load{period=\"15m\"} ${l15:-0}"
    print "# TYPE prom_claude_uptime_seconds gauge"
    print "prom_claude_uptime_seconds ${upt:-0}"
    print "# TYPE prom_claude_memory_bytes gauge"
    print "prom_claude_memory_bytes{type=\"total\"} $MEM_TOTAL"
    print "prom_claude_memory_bytes{type=\"used\"} $(( MEM_TOTAL - MEM_AVAIL ))"
    print "prom_claude_memory_bytes{type=\"swap_used\"} $(( SWAP_TOTAL - SWAP_FREE ))"
    print "# TYPE prom_claude_processes gauge"
    print "prom_claude_processes{state=\"total\"} ${procs:-0}"
    print "prom_claude_processes{state=\"zombie\"} ${zomb:-0}"
    print "# TYPE prom_claude_listening_sockets gauge"
    print "prom_claude_listening_sockets ${ports:-0}"
    print "# TYPE prom_claude_disk_used_percent gauge"
    df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {
        u=$5; sub("%","",u); m=$6; gsub(/\\/,"\\\\",m); gsub(/"/,"\\\"",m)
        printf "prom_claude_disk_used_percent{mount=\"%s\"} %s\n", m, u
    }'
    if have_systemd; then
        failed=$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l | tr -d ' ')
        print "# TYPE prom_claude_failed_units gauge"
        print "prom_claude_failed_units ${failed:-0}"
    fi
    if [[ "$upd" == <-> ]]; then
        print "# TYPE prom_claude_updates_pending gauge"
        print "prom_claude_updates_pending $upd"
    fi
}

act_resources() {
    local choice
    print " 1) Top 10 procesos por CPU"
    print " 2) Top 10 procesos por memoria"
    print " 3) Memoria RAM y Swap (free -h)"
    print " 4) Monitor interactivo básico (top)"
    prompt_input "Selecciona opción [1-4]: " choice
    case "$choice" in
        1) ps -eo pid,user:14,pcpu,pmem,comm --sort=-pcpu | head -n 11 ;;
        2) ps -eo pid,user:14,pcpu,pmem,comm --sort=-pmem | head -n 11 ;;
        3) free -h ;;
        4) run_interruptible top ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    log_action "Nativo: monitoreo de recursos ($choice)"
}

act_storage() {
    print "╔══════════════════════╤══════════╤══════════╤══════════╤════════╗"
    print "║ PUNTO DE MONTAJE     │ TAMAÑO   │ USADO    │ DISP     │ USO %  ║"
    print "╟──────────────────────┼──────────┼──────────┼──────────┼────────╢"
    df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {
        printf "║ %-20.20s │ %-8s │ %-8s │ %-8s │ %-6s ║\n", $6, $2, $3, $4, $5
    }'
    print "╚══════════════════════╧══════════╧══════════╧══════════╧════════╝"
    if command -v lsblk &>/dev/null; then
        print ""
        msg_info "Dispositivos de bloque (lsblk):"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null
    fi
    log_action "Nativo: almacenamiento"
}

mon_btop() { need btop && run_interruptible btop; }

mon_htop() { need htop && run_interruptible htop; }

# ==== SERVICIOS, LOGS Y TAREAS PROGRAMADAS ====
menu_monitor() {
    run_menu "MONITOREO AVANZADO DE RECURSOS" \
        "btop (monitor moderno)|mon_btop" \
        "htop (monitor por procesos)|mon_htop"
}

act_systemctl() {
    have_systemd || { msg_err "systemd no está disponible en este sistema."; return 0; }
    msg_info "Servicios en ejecución:"
    print -r -- "------------------------------------------"
    systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print "  > " $1}'
    print -r -- "------------------------------------------"

    local svc act crit=0
    prompt_input "Servicio a gestionar (ej: ssh o ssh.service): " svc
    [[ -z "$svc" ]] && return 0
    valid_ident "$svc" || { msg_err "Nombre de servicio no válido."; return 0; }
    [[ "$svc" != *.service ]] && svc="${svc}.service"
    case "${svc%.service}" in ssh|sshd|NetworkManager|systemd-networkd|networking|network) crit=1 ;; esac

    print ""
    print " Servicio seleccionado: $svc"
    print " 1) Consultar estado (status)"
    print " 2) Iniciar (start)"
    print " 3) Reiniciar (restart)"
    print " 4) Detener (stop)"
    print " 5) Habilitar en el arranque (enable)"
    print " 6) Deshabilitar del arranque (disable)"
    prompt_input "Elige la acción [1-6]: " act

    if (( crit )) && [[ "$act" == (3|4|6) ]]; then
        msg_warn "'$svc' es crítico: podrías quedarte sin acceso remoto."
        confirm "¿Continuar?" || return 0
    fi
    case "$act" in
        1) "${SUDO[@]}" systemctl status "$svc" --no-pager ;;
        2) "${SUDO[@]}" systemctl start "$svc"   && msg_ok "Servicio iniciado."    ; log_action "Systemctl: start $svc" ;;
        3) "${SUDO[@]}" systemctl restart "$svc" && msg_ok "Servicio reiniciado."  ; log_action "Systemctl: restart $svc" ;;
        4) "${SUDO[@]}" systemctl stop "$svc"    && msg_ok "Servicio detenido."    ; log_action "Systemctl: stop $svc" ;;
        5) "${SUDO[@]}" systemctl enable "$svc"  && msg_ok "Servicio habilitado."  ; log_action "Systemctl: enable $svc" ;;
        6) "${SUDO[@]}" systemctl disable "$svc" && msg_ok "Servicio deshabilitado."; log_action "Systemctl: disable $svc" ;;
        *) msg_warn "Acción no válida." ;;
    esac
}

act_journal() {
    have_systemd || { msg_err "journalctl requiere systemd."; return 0; }
    msg_info "Servicios activos disponibles:"
    print -r -- "------------------------------------------"
    systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print "  > " $1}'
    print -r -- "------------------------------------------"
    local svc n
    prompt_input "Servicio a consultar (ej: ssh, docker): " svc
    [[ -z "$svc" ]] && return 0
    valid_ident "$svc" || { msg_err "Nombre de servicio no válido."; return 0; }
    [[ "$svc" != *.service ]] && svc="${svc}.service"
    prompt_input "Cantidad de líneas [Default: 40]: " n
    valid_num "$n" || n=40
    msg_info "Últimas $n líneas de '$svc':"
    journal -u "$svc" -n "$n" --no-pager
    log_action "Journalctl: $svc ($n líneas)"
}

cron_user_list() {
    msg_info "Tareas cron del usuario actual ($USER):"
    print -r -- "------------------------------------------"
    crontab -l 2>/dev/null || print "No hay tareas programadas para este usuario (o cron no está instalado)."
}

cron_user_edit() {
    command -v crontab &>/dev/null || { msg_err "crontab no está instalado."; return 0; }
    msg_info "Abriendo editor de crontab (guarda y sal para aplicar)..."
    crontab -e
    log_action "Cron: edición de crontab de usuario"
}

cron_system_list() {
    msg_info "Tareas programadas del sistema:"
    print -r -- "--- /etc/crontab ---"
    grep -vE '^\s*(#|$)' /etc/crontab 2>/dev/null || print "(sin entradas)"
    print ""
    print -r -- "--- /etc/cron.d/ ---"
    ls -1 /etc/cron.d/ 2>/dev/null || print "(no existe o está vacío)"
}

cron_timers() {
    have_systemd || { msg_err "Requiere systemd."; return 0; }
    msg_info "Timers de systemd (equivalente moderno de cron):"
    systemctl list-timers --all --no-pager
}

log_sizes() {
    msg_info "Mayores consumidores en /var/log:"
    "${SUDO[@]}" du -ah -d 1 /var/log 2>/dev/null | sort -rh | head -n 15
    if command -v journalctl &>/dev/null; then
        print ""
        msg_info "Uso de disco del journal:"
        journal --disk-usage 2>/dev/null
    fi
}

# Deja la ruta elegida en CHOSEN_LOG (vacía si se cancela)
choose_log() {
    CHOSEN_LOG=""
    local method num
    print " 1) Elegir de la lista de logs disponibles"
    print " 2) Escribir la ruta manualmente"
    prompt_input "Selecciona una opción [1-2]: " method

    if [[ "$method" == 1 ]]; then
        local -a logs
        logs=( ${(f)"$(find /var/log -maxdepth 2 -type f ! -name '*.gz' ! -name '*.xz' ! -name '*.zst' \
                        ! -name '*.bz2' ! -name '*.zip' ! -name '*.[0-9]' ! -name 'btmp*' ! -name 'wtmp*' \
                        ! -name 'lastlog' ! -name 'faillog' 2>/dev/null | sort)"} )
        if (( ${#logs} == 0 )); then
            msg_warn "No se encontraron logs de texto en /var/log."
            have_systemd && msg_info "Este sistema usa el journal: prueba la opción de journalctl (menú 2)."
            return 1
        fi
        local i=1 lf
        for lf in "${logs[@]}"; do printf " %3d) %s\n" "$i" "$lf"; i=$(( i + 1 )); done
        print ""
        prompt_input "Número del log (o 'q' para cancelar): " num
        [[ -z "$num" || "$num" == q ]] && return 1
        if [[ "$num" == <-> ]] && (( num >= 1 && num <= ${#logs} )); then
            CHOSEN_LOG="${logs[$num]}"
        else
            msg_err "Selección no válida."; return 1
        fi
    elif [[ "$method" == 2 ]]; then
        prompt_input "Ruta completa del log (ej: /var/log/nginx/error.log): " CHOSEN_LOG
        if [[ ! -f "$CHOSEN_LOG" ]]; then
            msg_err "La ruta '$CHOSEN_LOG' no es válida o el archivo no existe."
            CHOSEN_LOG=""; return 1
        fi
    else
        msg_warn "Opción no válida."; return 1
    fi
    return 0
}

log_tail() {
    choose_log || return 0
    msg_info "Mostrando '$CHOSEN_LOG' en vivo (Ctrl+C para volver)..."
    sleep 1
    run_interruptible "${SUDO[@]}" tail -n 50 -f "$CHOSEN_LOG"
    log_action "Logs: tail -f $CHOSEN_LOG"
}

log_filter() {
    choose_log || return 0
    local pattern nlines results count out_action out_file
    print ""
    prompt_input "Patrón a buscar [Default: error|fail|crit|warn]: " pattern
    pattern="${pattern:-error|fail|crit|warn}"
    prompt_input "Líneas finales a revisar [Default: 500]: " nlines
    valid_num "$nlines" || nlines=500

    msg_info "Buscando '$pattern' en las últimas $nlines líneas de '$CHOSEN_LOG'..."
    results=$("${SUDO[@]}" tail -n "$nlines" "$CHOSEN_LOG" | grep -iE -- "$pattern")
    if [[ -z "$results" ]]; then
        msg_info "No se encontraron coincidencias."
        return 0
    fi
    count=$(print -r -- "$results" | wc -l | tr -d ' ')
    msg_ok "Se encontraron $count coincidencias."
    print ""
    print " 1) Guardar en archivo (${TMPDIR:-/tmp})"
    print " 2) Ver en pantalla (paginador)"
    prompt_input "Selecciona una opción [1-2]: " out_action
    if [[ "$out_action" == 1 ]]; then
        out_file="${TMPDIR:-/tmp}/filtro_${CHOSEN_LOG:t}_$(date +%Y%m%d_%H%M%S).log"
        ( umask 077; print -r -- "$results" > "$out_file" )
        msg_ok "Resultado guardado en: $out_file (permisos 600)"
        log_action "Logs: filtro guardado en $out_file"
    else
        print -r -- "$results" | ${PAGER:-less}
        log_action "Logs: filtro visto en pantalla de $CHOSEN_LOG"
    fi
}

menu_cron_logs() {
    run_menu "TAREAS PROGRAMADAS (CRON / TIMERS) Y LOGS" \
        "#TAREAS PROGRAMADAS" \
        "Listar mis tareas (crontab -l)|cron_user_list" \
        "Editar mis tareas (crontab -e)|cron_user_edit" \
        "Listar tareas del sistema (/etc/crontab, /etc/cron.d)|cron_system_list" \
        "Listar timers de systemd|cron_timers" \
        "#LOGS" \
        "Mayores consumidores de /var/log y journal|log_sizes" \
        "Ver un log en tiempo real (tail -f)|log_tail" \
        "Buscar y filtrar logs (avanzado)|log_filter"
}

# ==============================================================================
#  PAQUETES: actualización con log y resumen   (reemplaza al antiguo update.sh)
# ==============================================================================
# Lista de paquetes con actualización pendiente (uno por línea).
updates_list() {
    case "$PKG_MGR" in
        apt)     apt-get -s upgrade 2>/dev/null | awk '/^Inst/{print $2}' ;;
        dnf|yum) "$PKG_MGR" -C -q check-update 2>/dev/null \
                     | awk '/^[[:alnum:]_.+-]+\.[[:alnum:]_]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+/{print $1}' ;;
        pacman)  command -v checkupdates &>/dev/null && checkupdates 2>/dev/null | awk '{print $1}' ;;
        *)       : ;;
    esac
}

act_system_update() {
    if [[ "$PKG_MGR" == unknown ]]; then msg_warn "No se detectó gestor de paquetes."; return 0; fi
    local logf="$STATE_DIR/updates.log" before n rc
    mkdir -p "$STATE_DIR" 2>/dev/null; ( umask 077; touch "$logf" 2>/dev/null )

    before=$(updates_list)
    n=$(print -r -- "$before" | grep -c .)
    msg_info "Actualizaciones pendientes: $n"
    [[ -n "$before" ]] && print -r -- "$before" | head -n 15 | sed 's/^/     - /'
    (( n > 15 )) && print "     ... y $(( n - 15 )) más"
    confirm "¿Actualizar TODOS los paquetes con $PKG_MGR?" || { msg_info "Cancelado."; return 0; }

    print -r -- "=== Actualización iniciada: $(date) ($PKG_MGR, $n pendientes) ===" >> "$logf"
    # El estado se captura DENTRO de cada rama: al cerrar el 'case', pipestatus se pierde.
    case "$PKG_MGR" in
        apt)    { "${SUDO[@]}" apt-get update && "${SUDO[@]}" apt-get dist-upgrade -y; } 2>&1 | tee -a "$logf"; rc=${pipestatus[1]} ;;
        dnf)    "${SUDO[@]}" dnf upgrade -y --refresh --nobest --skip-broken 2>&1 | tee -a "$logf"; rc=${pipestatus[1]} ;;
        yum)    "${SUDO[@]}" yum upgrade -y 2>&1 | tee -a "$logf"; rc=${pipestatus[1]} ;;
        pacman) "${SUDO[@]}" pacman -Syu --noconfirm 2>&1 | tee -a "$logf"; rc=${pipestatus[1]} ;;
        zypper) { "${SUDO[@]}" zypper refresh && "${SUDO[@]}" zypper update -y; } 2>&1 | tee -a "$logf"; rc=${pipestatus[1]} ;;
        apk)    { "${SUDO[@]}" apk update && "${SUDO[@]}" apk upgrade; } 2>&1 | tee -a "$logf"; rc=${pipestatus[1]} ;;
    esac

    print ""
    if (( rc == 0 )); then
        msg_ok "Actualización completada. Log: $logf"
        if [[ "$PKG_MGR" == apt ]] && confirm "¿Limpiar dependencias que ya no se usan (autoremove)?"; then
            "${SUDO[@]}" apt-get autoremove -y 2>&1 | tee -a "$logf"
        fi
    else
        msg_err "La actualización falló (código $rc). Revisa el log: $logf"
    fi
    [[ -f /var/run/reboot-required ]] && msg_warn "El sistema requiere reinicio (reboot-required)."
    log_action "Sistema: actualización con $PKG_MGR (rc=$rc, $n pendientes)"
}

# ==============================================================================
#  MEMORIA Y SWAP   (reemplaza a swap.sh y swap-watch.sh)
# ==============================================================================
_swap_watch_loop() {
    while true; do
        clear
        print -r -- "=== MONITOR RAM/SWAP - $(date +%T)   (Ctrl+C para volver) ==="
        print "\n[MEMORIA GENERAL]"
        free -h
        print "\n[DETALLE SWAP (ZRAM vs DISCO)]"
        swapon --show 2>/dev/null || print "(swapon no disponible)"
        print "\n[TOP 5 PROCESOS QUE MÁS RAM USAN]"
        ps -eo user:14,pmem,pcpu,comm --sort=-pmem 2>/dev/null | head -n 6
        sleep 2
    done
}

act_swap_watch() {
    msg_info "Monitor de RAM/Swap (Ctrl+C para detener y volver al menú)..."
    sleep 1
    run_interruptible _swap_watch_loop
}

# Libera el swap (swapoff + swapon) SOLO si la RAM disponible puede absorberlo.
act_swap_clear() {
    mem_stats
    local used=$(( SWAP_TOTAL - SWAP_FREE ))
    if (( SWAP_TOTAL == 0 )); then msg_info "No hay swap configurado en este sistema."; return 0; fi
    kv "Swap en uso" "$(human_bytes $used) de $(human_bytes $SWAP_TOTAL)"
    kv "RAM disponible" "$(human_bytes $MEM_AVAIL)"
    if (( used == 0 )); then msg_ok "El swap ya está en 0: no hay nada que liberar."; return 0; fi
    if (( used * 100 > MEM_AVAIL * 80 )); then
        msg_err "La RAM disponible no alcanza para absorber el swap en uso sin riesgo de OOM."
        msg_info "Libera memoria (cierra procesos) y vuelve a intentar."
        return 0
    fi
    msg_warn "swapoff mueve el swap de vuelta a la RAM; puede tardar y generar carga de disco."
    confirm "¿Ejecutar 'swapoff -a && swapon -a'?" || { msg_info "Cancelado."; return 0; }
    if "${SUDO[@]}" swapoff -a && "${SUDO[@]}" swapon -a; then
        mem_stats
        msg_ok "Swap reactivado. En uso ahora: $(human_bytes $(( SWAP_TOTAL - SWAP_FREE )))"
        log_action "Swap: liberado (swapoff/swapon)"
    else
        msg_err "Falló swapoff/swapon. Revisa con 'swapon --show'."
        "${SUDO[@]}" swapon -a 2>/dev/null
    fi
}

# ==============================================================================
#  DISCOS: INODOS
# ==============================================================================
act_inodes() {
    msg_info "Uso de inodos (un disco puede estar 'lleno' por inodos aunque tenga espacio):"
    printf " %-22s %10s %10s %10s %5s\n" "Montaje" "Inodos" "Usados" "Libres" "Uso"
    df -iP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {
        u=$5; sub("%","",u); flag=""; if (u+0>=85) flag="  [!] casi agotados"
        printf " %-22.22s %10s %10s %10s %5s%s\n", $6, $2, $3, $4, $5, flag
    }'
    log_action "Nativo: inodos"
}

# ==============================================================================
#  SEGURIDAD DEL HOST
# ==============================================================================
act_selinux() {
    if ! command -v getenforce &>/dev/null; then
        msg_info "SELinux no está instalado en este sistema."
        command -v aa-status &>/dev/null && { msg_info "AppArmor detectado:"; "${SUDO[@]}" aa-status 2>/dev/null | head -n 8; }
        return 0
    fi
    kv "Modo actual" "$(getenforce)"
    command -v sestatus &>/dev/null && sestatus 2>/dev/null | sed -n '1,8p;/Loaded policy/p' | sed 's/^/ /'
    if command -v ausearch &>/dev/null; then
        local out
        out=$("${SUDO[@]}" ausearch -m avc -ts recent 2>/dev/null | tail -n 15)
        print ""
        if [[ -n "$out" ]]; then msg_warn "Denegaciones AVC recientes:"; print -r -- "$out"
        else msg_ok "Sin denegaciones AVC recientes."; fi
    else
        msg_info "ausearch no instalado (paquete audit) para ver denegaciones."
    fi
    log_action "Seguridad: SELinux"
}

act_firewall() {
    local found=0 st
    if command -v firewall-cmd &>/dev/null; then
        found=1
        st=$("${SUDO[@]}" firewall-cmd --state 2>&1)
        kv "firewalld" "$st"
        if [[ "$st" == running ]]; then
            "${SUDO[@]}" firewall-cmd --get-active-zones
            print ""
            "${SUDO[@]}" firewall-cmd --list-all
        fi
    fi
    if command -v ufw &>/dev/null; then found=1; "${SUDO[@]}" ufw status verbose; fi
    if (( ! found )) && command -v nft &>/dev/null; then
        found=1; msg_info "nftables (primeras 40 líneas):"; "${SUDO[@]}" nft list ruleset 2>/dev/null | head -n 40
    fi
    (( found )) || msg_warn "No se detectó firewalld, ufw ni nftables."
    log_action "Seguridad: firewall"
}

act_access() {
    msg_info "Últimos accesos exitosos:"
    last -n 10 2>/dev/null | sed 's/^/  /'
    print ""
    msg_info "Últimos intentos FALLIDOS (lastb):"
    local out; out=$("${SUDO[@]}" lastb -n 10 2>/dev/null)
    if [[ -n "$out" ]]; then print -r -- "$out" | sed 's/^/  /'; else print "  (ninguno o lastb no disponible)"; fi
    print ""
    msg_info "Sesiones abiertas ahora:"
    who | sed 's/^/  /'
    log_action "Seguridad: accesos"
}

act_privileged() {
    msg_info "Usuarios con privilegios de administración:"
    local g
    for g in wheel sudo adm root; do
        getent group "$g" &>/dev/null && print -r -- "  $g: $(getent group "$g" | cut -d: -f4)"
    done
    print ""
    msg_info "Cuentas con UID 0 (deberías ver solo 'root'):"
    awk -F: '$3==0{print "  " $1}' /etc/passwd
    print ""
    msg_info "Cuentas con shell de login y sin contraseña bloqueada:"
    awk -F: '$7 !~ /(nologin|false)$/ {print "  " $1 " (" $7 ")"}' /etc/passwd | head -n 20
    log_action "Seguridad: usuarios privilegiados"
}

act_chrony() {
    if command -v chronyc &>/dev/null; then
        msg_info "chronyc tracking:"; chronyc tracking 2>&1
        print ""; msg_info "Fuentes de tiempo:"; chronyc sources 2>&1
    fi
    command -v timedatectl &>/dev/null && { print ""; msg_info "timedatectl:"; timedatectl 2>/dev/null; }
    command -v chronyc &>/dev/null || command -v timedatectl &>/dev/null || msg_warn "Ni chronyc ni timedatectl disponibles."
    log_action "Sistema: sincronización horaria"
}


# ==============================================================================
#  EXPORTAR EL HEALTH CHECK A CSV
#  Formato "largo" (una fila por métrica): timestamp,host,categoria,metrica,valor,unidad,estado
#  Pensado para acumular series de tiempo (cron) y abrirse en Excel/Sheets/pandas.
# ==============================================================================
CSV_SEP=","
CSV_TS=""

csv_q() {
    local v="$1"
    if [[ "$v" == *\"* || "$v" == *$'\n'* || "$v" == *"$CSV_SEP"* ]]; then
        v="${v//\"/\"\"}"; print -rn -- "\"$v\""
    else
        print -rn -- "$v"
    fi
}

# csv_row categoria metrica valor unidad estado
csv_row() {
    local s="$CSV_SEP"
    print -r -- "$CSV_TS$s$(csv_q "$HOST")$s$(csv_q "$1")$s$(csv_q "$2")$s$(csv_q "$3")$s$(csv_q "$4")$s$(csv_q "$5")"
}

health_csv_header() {
    local s="$CSV_SEP"
    print -r -- "timestamp${s}host${s}categoria${s}metrica${s}valor${s}unidad${s}estado"
}

health_csv_rows() {
    CSV_TS=$(date '+%Y-%m-%dT%H:%M:%S%z')
    local cores up_s cpu l1 l5 l15 rest st used pct upd failed ports total zomb iface ip4 gw svc sid mnt tot usd av name
    cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null); cores="${cores:-1}"
    cpu=$(lscpu 2>/dev/null | awk -F: '/^Model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}')

    csv_row sistema os "$OS_NAME" texto INFO
    csv_row sistema kernel "$(uname -r)" texto INFO
    csv_row sistema arquitectura "$(uname -m)" texto INFO
    up_s=$(awk '{printf "%d",$1}' /proc/uptime 2>/dev/null)
    csv_row sistema uptime "${up_s:-0}" segundos INFO
    csv_row cpu modelo "${cpu:-N/D}" texto INFO
    csv_row cpu nucleos "$cores" unidades INFO

    read -r l1 l5 l15 rest < /proc/loadavg 2>/dev/null
    st=OK; awk -v l="${l1:-0}" -v c="$cores" 'BEGIN{exit !(l>c)}' && st=ALERTA
    csv_row carga load_1m "${l1:-0}" ratio "$st"
    csv_row carga load_5m "${l5:-0}" ratio INFO
    csv_row carga load_15m "${l15:-0}" ratio INFO

    mem_stats
    used=$(( MEM_TOTAL - MEM_AVAIL )); pct=0; (( MEM_TOTAL > 0 )) && pct=$(( used * 100 / MEM_TOTAL ))
    csv_row memoria ram_total "$MEM_TOTAL" bytes INFO
    csv_row memoria ram_usada "$used" bytes INFO
    st=OK; (( pct >= 90 )) && st=ALERTA
    csv_row memoria ram_usada_pct "$pct" porcentaje "$st"
    csv_row memoria swap_total "$SWAP_TOTAL" bytes INFO
    st=OK; (( SWAP_TOTAL - SWAP_FREE > 0 )) && st=ALERTA
    csv_row memoria swap_usada "$(( SWAP_TOTAL - SWAP_FREE ))" bytes "$st"

    df -PB1 -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1{u=$5; sub("%","",u); print $6"\t"$2"\t"$3"\t"$4"\t"u}' \
    | while IFS=$'\t' read -r mnt tot usd av pct; do
        st=OK; (( pct >= 85 )) && st=ALERTA
        csv_row disco "usado_pct:$mnt" "$pct" porcentaje "$st"
        csv_row disco "total:$mnt" "$tot" bytes INFO
        csv_row disco "libre:$mnt" "$av" bytes INFO
    done
    df -iP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1{u=$5; sub("%","",u); if (u ~ /^[0-9]+$/) print $6"\t"u}' \
    | while IFS=$'\t' read -r mnt pct; do
        st=OK; (( pct >= 85 )) && st=ALERTA
        csv_row inodos "usado_pct:$mnt" "$pct" porcentaje "$st"
    done

    upd=$(updates_pending)
    csv_row paquetes actualizaciones_pendientes "$upd" paquetes INFO
    csv_row paquetes reinicio_requerido "$([[ -f /var/run/reboot-required ]] && print si || print no)" booleano INFO

    if have_systemd; then
        failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
        st=OK; [[ -n "$failed" ]] && st=ALERTA
        csv_row servicios unidades_fallidas "$(print -r -- "$failed" | grep -c .)" unidades "$st"
        for name in ${(f)failed}; do csv_row servicios unidad_fallida "$name" texto ALERTA; done
        local -A seen
        for svc in ssh sshd docker containerd cron crond systemd-resolved firewalld ufw NetworkManager systemd-networkd \
                   chronyd systemd-timesyncd auditd rsyslog fail2ban nginx apache2 httpd mariadb mysql postgresql \
                   mssql-server mongod redis redis-server; do
            systemctl is-active --quiet "$svc" 2>/dev/null || continue
            sid=$(systemctl show -p Id --value "$svc" 2>/dev/null); sid="${sid:-$svc}"
            (( ${+seen[$sid]} )) && continue
            seen[$sid]=1; csv_row servicios "activo:${sid%.service}" activo texto OK
        done
    fi

    total=$(ps -eo pid= 2>/dev/null | wc -l | tr -d ' ')
    zomb=$(ps -eo stat= 2>/dev/null | grep -c '^Z')
    csv_row procesos total "${total:-0}" unidades INFO
    st=OK; (( zomb > 0 )) && st=ALERTA
    csv_row procesos zombies "${zomb:-0}" unidades "$st"

    if command -v ip &>/dev/null; then
        iface=$(ip route show default 2>/dev/null | awk '/default/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
        gw=$(ip route show default 2>/dev/null | awk '/default/{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')
        [[ -n "$iface" ]] && ip4=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4; exit}')
        csv_row red interfaz_principal "${iface:-N/A}" texto INFO
        csv_row red ip_local "${ip4:-N/A}" texto INFO
        csv_row red gateway "${gw:-N/A}" texto INFO
        ports=$(ss -tuln 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
        csv_row red sockets_en_escucha "${ports:-0}" unidades INFO
    fi

    for name in ${(f)"$(detect_db_engines | sed -nE 's/^ \[ OK \] ([^(]+[^( ]).*/\1/p')"}; do
        csv_row bases_de_datos motor_detectado "$name" texto INFO
    done
}

# Escribe el CSV en un archivo (agrega filas si ya existe). $2 = 1 para formato Excel (; + BOM)
health_csv_write() {
    local file="$1" excel="${2:-0}" new=1
    mkdir -p "${file:h}" 2>/dev/null || { msg_err "No pude crear '${file:h}'."; return 1; }
    if [[ -s "$file" ]]; then
        new=0
        head -n 1 "$file" | grep -q ';' && CSV_SEP=";" || CSV_SEP=","      # respeta el separador del archivo
    else
        CSV_SEP=","; (( excel )) && CSV_SEP=";"
    fi
    if (( new )); then
        (( excel )) && printf '\xEF\xBB\xBF' > "$file"
        health_csv_header >> "$file"
    fi
    health_csv_rows >> "$file"
    msg_ok "CSV $( (( new )) && print creado || print actualizado ): $file ($(grep -c . "$file") líneas, separador '$CSV_SEP')"
    log_action "Health: exportado a CSV $file"
}

# Menú: exportación interactiva
act_health_csv() {
    local mode f def="$HOME/prom_exports/health_${HOST}_$(date +%Y%m%d_%H%M%S).csv"
    print " 1) Coma ',' (estándar: Google Sheets, pandas, Grafana)"
    print " 2) Punto y coma ';' + UTF-8 con BOM (Excel en español)"
    prompt_input "Elige [1-2, Default 1]: " mode
    prompt_input "Archivo [Default: $def]: " f
    f="${f:-$def}"
    msg_info "Recolectando métricas..."
    health_csv_write "$f" "$([[ "$mode" == 2 ]] && print 1 || print 0)"
    [[ -f "$f" ]] && { print ""; msg_info "Primeras filas:"; head -n 6 "$f" | sed 's/^\xEF\xBB\xBF//' | cut -c1-120 | sed 's/^/   /'; }
}

# CLI: ./prom_claude.sh health-csv [--excel] [archivo]
#      sin archivo -> stdout; con archivo -> crea o agrega filas (ideal para cron)
health_csv_cli() {
    local excel=0 file=""
    while (( $# )); do
        case "$1" in --excel) excel=1 ;; *) file="$1" ;; esac; shift
    done
    if [[ -n "$file" ]]; then
        health_csv_write "$file" "$excel" >/dev/null && print -r -- "OK: $file"
    else
        CSV_SEP=","; (( excel )) && CSV_SEP=";"
        health_csv_header; health_csv_rows
    fi
}

# ==============================================================================
#  MENÚ SYSADMIN
# ==============================================================================
menu_memory() {
    run_menu "MEMORIA Y SWAP" \
        "Monitor en vivo de RAM/Swap (Ctrl+C para volver)|act_swap_watch" \
        "Liberar swap (swapoff/swapon con verificación de RAM)|act_swap_clear" \
        "Recursos y procesos (top CPU/RAM, free)|act_resources"
}

menu_security() {
    run_menu "SEGURIDAD DEL HOST" \
        "SELinux / AppArmor: modo y denegaciones recientes|act_selinux" \
        "Firewall (firewalld / ufw / nftables)|act_firewall" \
        "Accesos: exitosos, fallidos y sesiones abiertas|act_access" \
        "Usuarios privilegiados y cuentas UID 0|act_privileged"
}

menu_sysadmin() {
    run_menu "SYSADMIN - ADMINISTRACIÓN DEL SERVIDOR" \
        "#DIAGNOSTICO Y ESTADO" \
        "Panorama general del servidor (Health Check)|act_health" \
        "Exportar el Health Check a CSV (Excel / Sheets)|act_health_csv" \
        "Memoria, swap y procesos|menu_memory|nopause" \
        "Almacenamiento y particiones|act_storage" \
        "Inodos (df -i)|act_inodes" \
        "Sincronización horaria (chrony / timedatectl)|act_chrony" \
        "Monitores interactivos (btop / htop)|menu_monitor|nopause" \
        "#SISTEMA, SERVICIOS Y PAQUETES" \
        "Actualizar paquetes del sistema (con log)|act_system_update" \
        "Gestión de servicios (systemctl)|act_systemctl" \
        "Logs de un servicio (journalctl)|act_journal" \
        "Logs del sistema y tareas programadas (cron/timers)|menu_cron_logs|nopause" \
        "Monitoreo (Prometheus, Grafana, Loki, etc.)|menu_monitoring|nopause" \
        "#SEGURIDAD" \
        "Seguridad del host (SELinux, firewall, accesos)|menu_security|nopause" \
        "Fail2ban (gestión de baneos)|menu_fail2ban|nopause" \
        "#ARCHIVOS Y DATOS" \
        "Archivos: editar, buscar, comprimir, espacio, rsync|menu_files|nopause" \
        "Bases de datos (listar, ejecutar SQL)|menu_db|nopause" \
        "#USUARIOS Y GRUPOS" \
        "Gestión de usuarios y grupos|menu_users|nopause"
}
