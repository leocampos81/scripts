#!/usr/bin/env zsh
# Módulo: Sysadmin & Servidor

# --- 1. HEALTH CHECK ---
mem_stats() {
    local t a st sf
    read -r t a st sf <<< "$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2} END{printf "%.0f %.0f %.0f %.0f", t*1024, a*1024, st*1024, sf*1024}' /proc/meminfo 2>/dev/null)"
    MEM_TOTAL=${t:-0}; MEM_AVAIL=${a:-0}; SWAP_TOTAL=${st:-0}; SWAP_FREE=${sf:-0}
}

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

act_health() {
    clear
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
    kv "OS" "$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
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
            (( ${+seen[$sid]} )) && continue
            seen[$sid]=1; found=1
            print -r -- " ${C_GRN}[ OK ]${C_RST} ${sid%.service}"
        done
        (( found == 0 )) && print " No se detectaron servicios críticos corriendo."

        local failed; failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
        if [[ -n "$failed" ]]; then
            print -r -- " ${C_RED}[FALLO]${C_RST} Unidades en estado failed:"
            print -r -- "$failed" | sed 's/^/          - /'
        else
            print -r -- " ${C_GRN}[OK]${C_RST} Sin unidades fallidas"
        fi
        if command -v journalctl &>/dev/null; then
            local jerr; jerr=$(journalctl -p err -b -q --no-pager 2>/dev/null | wc -l | tr -d ' ')
            print -r -- " [ i ] Entradas 'err' en este arranque: ${jerr:-0}"
        fi
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
    log_action "Health Check ejecutado"
}

# --- 2. HERRAMIENTAS NATIVAS ---
act_edit() {
    local -a editors=()
    local e choice target n=1
    for e in nvim vim nano vi; do command -v "$e" &>/dev/null && editors+=("$e"); done
    if (( ${#editors} == 0 )); then msg_err "No hay editores instalados."; return 0; fi
    for e in "${editors[@]}"; do print " $n) $e"; n=$(( n + 1 )); done
    prompt_input "Selecciona el editor [1-${#editors}]: " choice
    [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#editors} )) || choice=1
    e="${editors[$choice]}"
    prompt_input "Ruta del archivo a editar: " target
    [[ -z "$target" ]] && return 0
    if [[ -w "$target" ]] || [[ ! -e "$target" && -w "${target:h}" ]]; then
        "$e" "$target"
    else
        if confirm "Sin permiso de escritura. ¿Abrir con sudo?"; then
            sudo "$e" "$target"
        fi
    fi
}

act_grep() {
    local lf pattern
    prompt_input "Ruta del archivo: " lf
    [[ -z "$lf" ]] && return 0
    if [[ ! -f "$lf" ]]; then msg_err "El archivo no existe."; return 0; fi
    prompt_input "Patrón (regex extendida): " pattern
    [[ -z "$pattern" ]] && return 0
    local -a cmd=(grep -inE -- "$pattern" "$lf")
    [[ ! -r "$lf" ]] && cmd=("${SUDO[@]}" "${cmd[@]}")
    "${cmd[@]}" | head -n 50
}

act_storage() {
    print "╔══════════════════════╤══════════╤══════════╤══════════╤════════╗"
    print "║ PUNTO DE MONTAJE     │ TAMAÑO   │ USADO    │ DISP     │ USO %  ║"
    print "╟──────────────────────┼──────────┼──────────┼──────────┼────────╢"
    df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {
        printf "║ %-20.20s │ %-8s │ %-8s │ %-8s │ %-6s ║\n", $6, $2, $3, $4, $5
    }'
    print "╚══════════════════════╧══════════╧══════════╧══════════╧════════╝"
}

act_systemctl() {
    have_systemd || { msg_err "systemd no está disponible."; return 0; }
    systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print "  > " $1}'
    local svc act
    prompt_input "Servicio a gestionar: " svc
    [[ -z "$svc" ]] && return 0
    [[ "$svc" != *.service ]] && svc="${svc}.service"
    print " 1) status | 2) start | 3) restart | 4) stop | 5) enable | 6) disable"
    prompt_input "Acción [1-6]: " act
    case "$act" in
        1) "${SUDO[@]}" systemctl status "$svc" --no-pager ;;
        2) "${SUDO[@]}" systemctl start "$svc" ;;
        3) "${SUDO[@]}" systemctl restart "$svc" ;;
        4) "${SUDO[@]}" systemctl stop "$svc" ;;
        5) "${SUDO[@]}" systemctl enable "$svc" ;;
        6) "${SUDO[@]}" systemctl disable "$svc" ;;
    esac
}

# --- Diagnóstico de Kernel (dmesg) ---
dmesg_errors() {
    clear
    msg_info "Errores y advertencias recientes del Kernel (dmesg):"
    print -r -- "----------------------------------------------------------"
    "${SUDO[@]}" dmesg --level=err,warn -T 2>/dev/null | tail -n 50
    print -r -- "----------------------------------------------------------"
    log_action "dmesg: errores y warnings"
}

dmesg_hardware() {
    clear
    msg_info "Eventos de hardware recientes (USB, Discos, SATA/NVMe):"
    print -r -- "----------------------------------------------------------"
    "${SUDO[@]}" dmesg -T 2>/dev/null | grep -iE "usb|sd[a-z]|nvme|ata|scsi" | tail -n 40
    print -r -- "----------------------------------------------------------"
    log_action "dmesg: eventos de hardware"
}

dmesg_live() {
    clear
    msg_info "Monitoreo en vivo de dmesg (Ctrl+C para volver)..."
    sleep 1
    ( trap - INT; sudo dmesg -wT )
}

dmesg_search() {
    local pat
    prompt_input "Patrón a buscar en dmesg (ej: error, firmware, nic): " pat
    [[ -z "$pat" ]] && return 0
    
    clear
    msg_info "Resultados para '$pat' en dmesg:"
    print -r -- "----------------------------------------------------------"
    
    local resultados
    resultados=$(sudo dmesg -T 2>/dev/null | grep -i -- "$pat")
    
    if [[ -z "$resultados" ]]; then
        msg_warn "No se encontraron coincidencias para '$pat' en el buffer actual de dmesg."
        msg_info "Sugerencia: Prueba con otro término (ej: 'error', 'pci', 'usb', 'fail')."
    else
        print -r -- "$resultados" | tail -n 50
    fi
    print -r -- "----------------------------------------------------------"
    log_action "dmesg: búsqueda '$pat'"
}

# --- Análisis de Arranque (systemd-analyze) ---
boot_blame() {
    clear
    msg_info "Servicios ordenados por tiempo de arranque (culpables del retraso):"
    print -r -- "----------------------------------------------------------"
    systemd-analyze blame 2>/dev/null | head -n 15
    print -r -- "----------------------------------------------------------"
    log_action "Boot: systemd-analyze blame"
}

boot_critical_chain() {
    clear
    msg_info "Cadena crítica de dependencias (dónde se pierde el tiempo):"
    print -r -- "----------------------------------------------------------"
    systemd-analyze critical-chain 2>/dev/null | head -n 20
    print -r -- "----------------------------------------------------------"
    log_action "Boot: systemd-analyze critical-chain"
}

boot_summary() {
    clear
    msg_info "Resumen del tiempo de arranque (Kernel + Userspace):"
    print -r -- "----------------------------------------------------------"
    systemd-analyze 2>/dev/null
    print -r -- "----------------------------------------------------------"
    log_action "Boot: systemd-analyze (resumen)"
}

menu_native() {
    run_menu "HERRAMIENTAS NATIVAS Y DIAGNÓSTICO LINUX" \
        "#ARCHIVOS Y EDICIÓN" \
        "Editar archivos|act_edit" \
        "Búsqueda de texto (grep)|act_grep" \
        "Almacenamiento y particiones|act_storage" \
        "#SERVICIOS" \
        "Gestión de servicios systemctl|act_systemctl" \
        "#DIAGNÓSTICO DE KERNEL (DMESG)" \
        "Ver errores/advertencias del kernel|dmesg_errors" \
        "Eventos de hardware (USB/Discos)|dmesg_hardware" \
        "Monitoreo en vivo de dmesg|dmesg_live" \
        "Buscar patrón en dmesg|dmesg_search" \
        "#ANÁLISIS DE ARRANQUE (SYSTEMD)" \
        "Resumen del tiempo de boot|boot_summary" \
        "Servicios lentos (blame)|boot_blame" \
        "Cadena crítica (critical-chain)|boot_critical_chain"
}

# --- 4. MONITOREO AVANZADO ---
mon_btop() { need btop && run_interruptible btop; }
mon_htop() { need htop && run_interruptible htop; }

menu_monitor() {
    run_menu "MONITOREO AVANZADO DE RECURSOS" \
        "btop (monitor moderno)|mon_btop" \
        "htop (monitor por procesos)|mon_htop"
}

# --- 5. BASES DE DATOS ---
detect_db_engines() {
    local v
    if find_sqlcmd &>/dev/null || proc_running sqlservr; then
        print " [ OK ] Microsoft SQL Server"; return 0
    fi
    if command -v mysql &>/dev/null || proc_running mysqld || proc_running mariadbd; then
        print " [ OK ] MySQL/MariaDB"; return 0
    fi
    if command -v psql &>/dev/null || proc_running postgres; then
        print " [ OK ] PostgreSQL"; return 0
    fi
    print "  (ninguno detectado)"
}

db_mssql() {
    local bin
    if ! bin=$(find_sqlcmd); then
        msg_warn "'sqlcmd' no está instalado."; return 0
    fi
    local -a extra=()
    "$bin" '-?' 2>&1 | grep -qE 'Version (1[7-9]|[2-9][0-9])' && extra=(-C)

    local host user pass out rc dbs
    prompt_input "Servidor [Default: localhost]: " host;   host="${host:-localhost}"
    prompt_input "Usuario [Default: sa]: " user;           user="${user:-sa}"
    prompt_password "Contraseña: " pass
    [[ -z "$pass" ]] && { msg_err "SQL Server requiere contraseña."; return 0; }

    msg_info "Consultando versión y bases de datos en $host..."
    out=$(SQLCMDPASSWORD="$pass" "$bin" -S "$host" -U "$user" "${extra[@]}" -l 5 -h -1 -W \
          -Q "SET NOCOUNT ON; SELECT @@VERSION" 2>&1); rc=$?
    if (( rc != 0 )) || [[ "$out" == *"Sqlcmd: Error"* || "$out" == *"Msg "* ]]; then
        msg_err "No se pudo conectar a SQL Server."
        return 0
    fi
    dbs=$(SQLCMDPASSWORD="$pass" "$bin" -S "$host" -U "$user" "${extra[@]}" -l 5 -h -1 -W \
          -Q "SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name" 2>&1)
    print -r -- "--- VERSIÓN ---"; print -r -- "$out" | head -n 1
    print ""; print -r -- "--- BASES DE DATOS ---"; print -r -- "$dbs" | sed '/^$/d; s/^/  > /'
}

db_mysql() {
    need mysql || return 0
    local user pass
    prompt_input "Usuario [Default: root]: " user; user="${user:-root}"
    prompt_password "Contraseña: " pass
    local -a my=(mysql -u "$user" -N -B)
    [[ -z "$pass" ]] && my=("${SUDO[@]}" "${my[@]}")
    local out; out=$(MYSQL_PWD="$pass" "${my[@]}" -e "SHOW DATABASES;" 2>&1)
    print -r -- "$out" | sed '/^$/d; s/^/  > /'
}

db_pg() {
    need psql || return 0
    local user dbname pass
    prompt_input "Usuario [Default: postgres]: " user;      user="${user:-postgres}"
    prompt_input "Base de datos [Default: postgres]: " dbname; dbname="${dbname:-postgres}"
    prompt_password "Contraseña: " pass
    local -a pg=(psql -h localhost -U "$user" -d "$dbname" -At)
    [[ -z "$pass" ]] && pg=(sudo -u "$user" psql -d "$dbname" -At)
    local out; out=$(PGPASSWORD="$pass" "${pg[@]}" -c "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1;" 2>&1)
    print -r -- "$out" | sed '/^$/d; s/^/  > /'
}

menu_db() {
    run_menu "GESTIÓN DE BASES DE DATOS (BBDD)" \
        "Detectar motores instalados|detect_db_engines" \
        "#SQL SERVER" \
        "Listar BBDD en SQL Server|db_mssql" \
        "#MYSQL / MARIADB" \
        "Listar BBDD en MySQL|db_mysql" \
        "#POSTGRESQL" \
        "Listar BBDD en PostgreSQL|db_pg"
}

# --- 6. CRON Y LOGS ---
cron_user_list() {
    msg_info "Tareas cron del usuario actual ($USER):"
    crontab -l 2>/dev/null || print "No hay tareas programadas."
}
cron_system_list() {
    msg_info "Tareas programadas del sistema:"
    grep -vE '^\s*(#|$)' /etc/crontab 2>/dev/null || print "(sin entradas)"
    ls -1 /etc/cron.d/ 2>/dev/null || print "(no existe o está vacío)"
}
log_sizes() {
    msg_info "Mayores consumidores en /var/log:"
    "${SUDO[@]}" du -ah -d 1 /var/log 2>/dev/null | sort -rh | head -n 15
}

choose_log() {
    CHOSEN_LOG=""
    local -a logs
    logs=( ${(f)"$(find /var/log -maxdepth 2 -type f ! -name '*.gz' ! -name 'btmp*' ! -name 'wtmp*' ! -name 'lastlog' 2>/dev/null | sort)"} )
    if (( ${#logs} == 0 )); then msg_warn "No se encontraron logs."; return 1; fi
    local i=1 lf
    for lf in "${logs[@]}"; do printf " %3d) %s\n" "$i" "$lf"; i=$(( i + 1 )); done
    local num
    prompt_input "Número del log a ver (o 'q'): " num
    [[ -z "$num" || "$num" == q ]] && return 1
    if [[ "$num" == <-> ]] && (( num >= 1 && num <= ${#logs} )); then
        CHOSEN_LOG="${logs[$num]}"
    else
        msg_err "Selección no válida."; return 1
    fi
    return 0
}

log_tail() {
    choose_log || return 0
    msg_info "Mostrando '$CHOSEN_LOG' en vivo (Ctrl+C para salir)..."
    sleep 1
    run_interruptible "${SUDO[@]}" tail -n 50 -f "$CHOSEN_LOG"
}
log_filter() {
    choose_log || return 0
    local pattern
    prompt_input "Patrón a buscar [Default: error|fail|crit|warn]: " pattern
    pattern="${pattern:-error|fail|crit|warn}"
    msg_info "Buscando en '$CHOSEN_LOG'..."
    "${SUDO[@]}" tail -n 500 "$CHOSEN_LOG" | grep -iE -- "$pattern" | ${PAGER:-less}
}

menu_cron_logs() {
    run_menu "TAREAS PROGRAMADAS Y LOGS" \
        "#CRON" \
        "Listar mis tareas (crontab -l)|cron_user_list" \
        "Listar tareas del sistema (/etc/crontab)|cron_system_list" \
        "#LOGS" \
        "Mayores consumidores de /var/log|log_sizes" \
        "Ver un log en tiempo real (tail -f)|log_tail" \
        "Buscar y filtrar logs|log_filter"
}

# --- Menú Principal del Módulo ---
sysadmin_menu() {
    run_menu "SYSADMIN & SERVIDOR" \
        "#SISTEMA" \
        "Actualizar paquetes del sistema ($PKG_MGR)|sys_update_system" \
        "#DIAGNÓSTICO Y GESTIÓN" \
        "Panorama general del servidor (Health Check)|act_health" \
        "Herramientas nativas (Archivos, Servicios, Discos)|menu_native|nopause" \
        "Monitoreo avanzado de recursos (btop, htop)|menu_monitor|nopause" \
        "Gestión de bases de datos (BBDD)|menu_db|nopause" \
        "Tareas programadas (cron/timers) y logs|menu_cron_logs|nopause"
}
