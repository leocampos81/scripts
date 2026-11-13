#!/usr/bin/env zsh

# ==============================================================================
#  PROMETHERION2112 - SYSADMIN TOOLKIT & DASHBOARD
#  Repositorio: git@github.com:leocampos81/scripts.git
#  Autor: Leonardo Campos (https://github.com/leocampos81)
#  Versión: dsv1 (DeepSeek v1 - sobre base Claude v5.0)
# ==============================================================================
#  USO
#    ./prom_claude_dsv1.sh            Menú interactivo
#    ./prom_claude_dsv1.sh health     Health Check sin menú
#    ./prom_claude_dsv1.sh metrics    Métricas Prometheus
#    ./prom_claude_dsv1.sh version | help
# ==============================================================================
#  BITÁCORA DE CAMBIOS (CHANGELOG)
# ==============================================================================
#  [2026-11-12] - v5.0 (Rama Claude)
#    * Refactorización total: menús dirigidos por datos (run_menu).
#    * Modos no interactivos (health, metrics).
#    * Seguridad: contraseñas por entorno, sin eval, validación de inputs.
#    * Nuevo Health Check avanzado y detección de BBDD.
#
#  [2026-11-13] - dsv1 (Rama DeepSeek)
#    * Módulo de Automatización (IaC) reescrito:
#      - Submenú exclusivo para Ansible (inventarios, ping, playbooks).
#      - Submenú exclusivo para Terraform (init, plan, fmt, directorios).
#      - Búsqueda dinámica de archivos .yml y .tf en rutas típicas.
#
#  [2026-11-13] - dsv1.1 (Rama DeepSeek)
#    * Integración del banner visual desde banner.sh.
#    * Corrección de find_workdir (redirección de prompt a stderr).
# ==============================================================================

# --- Opciones de zsh ----------------------------------------------------------
setopt TYPESET_SILENT NO_BEEP
export LC_NUMERIC=C

# --- Rutas y variables globales ------------------------------------------------
VERSION="dsv1.1"
SCRIPT_NAME="${0:t}"
REPO_DIR="${PROM_REPO_DIR:-$HOME/.local/bin/scripts}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/prometherion"
LOG_FILE="$STATE_DIR/sysadmin.log"
LOG_MAX_BYTES=1048576
BOX_W=60
BOX_LBL=16
BOX_VW=$(( BOX_W - BOX_LBL - 4 ))
NMAP_ACK=0
DB_FOUND=0
CHOSEN_LOG=""

# --- Colores ------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RST=$'\e[0m'; C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_CYN=$'\e[36m'
else
    C_RST=""; C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""
fi

msg_info() { print -r -- "${C_CYN}[-]${C_RST} $*"; }
msg_ok()   { print -r -- "${C_GRN}[OK]${C_RST} $*"; }
msg_warn() { print -r -- "${C_YEL}[!]${C_RST} $*"; }
msg_err()  { print -r -- "${C_RED}[ERROR]${C_RST} $*"; }

# --- Privilegios ---------------------------------------------------------------
if (( EUID == 0 )); then SUDO=(); else SUDO=(sudo); fi

# --- Utilidades internas -------------------------------------------------------
init_log() {
    mkdir -p "$STATE_DIR" 2>/dev/null && chmod 700 "$STATE_DIR" 2>/dev/null
    if [[ -f "$LOG_FILE" ]]; then
        local sz
        sz=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
        (( sz > LOG_MAX_BYTES )) && mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
    fi
    ( umask 077; touch "$LOG_FILE" 2>/dev/null )
}

log_action() {
    print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
}

get_os_name() {
    if [[ -f /etc/os-release ]]; then
        ( . /etc/os-release 2>/dev/null; print -r -- "${PRETTY_NAME:-Linux}" )
    else
        print -r -- "Linux genérico"
    fi
}

have_systemd() { command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; }
proc_running() { command -v pgrep &>/dev/null && pgrep -x "$1" &>/dev/null; }

valid_num()   { [[ -n "$1" && "$1" == <-> ]]; }
valid_host()  { local re='^[A-Za-z0-9._:/,%-]+$'; [[ -n "$1" && "$1" != -* && "$1" =~ $re ]]; }
valid_ident() { local re='^[A-Za-z0-9._@:-]+$';   [[ -n "$1" && "$1" != -* && "$1" =~ $re ]]; }

prompt_input() {
    local prompt_msg="$1" var_name="$2" old_stty_local rc
    old_stty_local=$(stty -g 2>/dev/null)
    stty erase '^?' erase '^H' 2>/dev/null
    print -rn -- "$prompt_msg"
    read -r "$var_name"
    rc=$?
    [[ -n "$old_stty_local" ]] && stty "$old_stty_local" 2>/dev/null
    return $rc
}

prompt_password() {
    local prompt_msg="$1" var_name="$2"
    read -rs "${var_name}?${prompt_msg}"
    local rc=$?
    print ""
    return $rc
}

confirm() {
    local ans
    read -r "ans?$1 (s/n): "
    [[ "$ans" == [sSyY] ]]
}

pause_screen() {
    [[ -t 0 ]] || return 0
    print ""
    read -r "?Presiona Enter para continuar..."
    while read -r -t 0.01 -k 1 2>/dev/null; do :; done
}

run_interruptible() { ( trap - INT; "$@" ); return 0; }

ccurl() {
    command -v curl &>/dev/null || { msg_err "curl no está instalado."; return 1; }
    curl -sS --max-time 10 "$@"
}

urlencode() {
    if command -v jq &>/dev/null; then
        printf '%s' "$1" | jq -sRr @uri
    else
        printf '%s' "$1" | sed 's/ /%20/g'
    fi
}

human_bytes() {
    awk -v b="${1:-0}" 'BEGIN{split("B KiB MiB GiB TiB",u," "); i=1; while(b>=1024 && i<5){b/=1024;i++} printf "%.1f %s", b, u[i]}'
}

ms_fmt() { awk -v s="${1:-0}" 'BEGIN{printf "%.1f ms", s*1000}'; }

# --- Helpers de formato --------------------------------------------------------
_hline() { local e=""; print -rn -- "${(l:$1::─:)e}"; }

box_open() {
    local t="${1[1,$((BOX_W-2))]}" w=$((BOX_W-2))
    print -r -- "┌$(_hline $BOX_W)┐"
    print -r -- "│ ${(r:$w:)t} │"
    print -r -- "├$(_hline $BOX_W)┤"
}
box_sep()   { print -r -- "├$(_hline $BOX_W)┤"; }
box_close() { print -r -- "└$(_hline $BOX_W)┘"; }
box_text()  { local w=$((BOX_W-2)) t="${1[1,$((BOX_W-2))]}"; print -r -- "│ ${(r:$w:)t} │"; }
box_row() {
    local l="${1[1,$BOX_LBL]}" v="${2[1,$BOX_VW]}"
    print -r -- "│ ${(r:$BOX_LBL:)l}: ${(r:$BOX_VW:)v} │"
}

section() { local t="--- $1 "; print ""; print -r -- "${(r:68::-:)t}"; }
kv()      { print -r -- " ${(r:13:)1}: $2"; }

# --- Gestor de paquetes -------------------------------------------------------
detect_pkg_manager() {
    PKG_MGR="unknown"; PKG_INSTALL=()
    if   command -v apt-get &>/dev/null; then PKG_MGR="apt";    PKG_INSTALL=("${SUDO[@]}" apt-get install -y)
    elif command -v dnf     &>/dev/null; then PKG_MGR="dnf";    PKG_INSTALL=("${SUDO[@]}" dnf install -y)
    elif command -v yum     &>/dev/null; then PKG_MGR="yum";    PKG_INSTALL=("${SUDO[@]}" yum install -y)
    elif command -v pacman  &>/dev/null; then PKG_MGR="pacman"; PKG_INSTALL=("${SUDO[@]}" pacman -S --noconfirm --needed)
    elif command -v zypper  &>/dev/null; then PKG_MGR="zypper"; PKG_INSTALL=("${SUDO[@]}" zypper --non-interactive install)
    elif command -v apk     &>/dev/null; then PKG_MGR="apk";    PKG_INSTALL=("${SUDO[@]}" apk add)
    fi
}

pkg_for() {
    case "$1:$PKG_MGR" in
        dig:apt)                        print dnsutils ;;
        dig:dnf|dig:yum|dig:zypper)     print bind-utils ;;
        dig:pacman)                     print bind ;;
        dig:apk)                        print bind-tools ;;
        nc:apt|nc:zypper|nc:apk)        print netcat-openbsd ;;
        nc:dnf|nc:yum)                  print nmap-ncat ;;
        nc:pacman)                      print openbsd-netcat ;;
        mysql:apt|mysql:zypper|mysql:apk) print mariadb-client ;;
        mysql:dnf|mysql:yum)            print mariadb ;;
        mysql:pacman)                   print mariadb-clients ;;
        psql:apt|psql:apk)              print postgresql-client ;;
        psql:*)                         print postgresql ;;
        docker:apt)                     print docker.io ;;
        docker:dnf|docker:yum)          print docker-ce ;;
        docker:*)                       print docker ;;
        ansible:dnf|ansible:yum)        print ansible-core ;;
        sqlcmd:*|terraform:*)           print "" ;;
        *)                              print "$1" ;;
    esac
}

install_hint() {
    case "$1" in
        sqlcmd)    msg_info "Instala mssql-tools18 desde el repo de Microsoft:"; msg_info "https://learn.microsoft.com/sql/linux/sql-server-linux-setup-tools" ;;
        terraform) msg_info "Terraform no viene en los repos base: https://developer.hashicorp.com/terraform/install" ;;
        docker)    msg_info "Si el paquete falla, usa el repo oficial: https://docs.docker.com/engine/install/" ;;
        *)         msg_warn "No conozco un paquete para '$1' en $PKG_MGR." ;;
    esac
}

ensure_pkg() {
    local bin="$1" pkg="${2:-}"
    command -v "$bin" &>/dev/null && return 0
    [[ -z "$pkg" ]] && pkg=$(pkg_for "$bin")

    msg_warn "'$bin' no está instalado."
    if [[ "$PKG_MGR" == unknown ]]; then
        msg_warn "No se detectó un gestor de paquetes compatible."
        return 1
    fi
    if [[ -z "$pkg" ]]; then
        install_hint "$bin"
        return 1
    fi
    confirm "¿Instalar '$pkg' con $PKG_MGR ahora?" || return 1

    msg_info "Instalando '$pkg' con $PKG_MGR..."
    "${PKG_INSTALL[@]}" "$pkg"
    log_action "Instalación: $pkg vía $PKG_MGR"

    if command -v "$bin" &>/dev/null; then
        msg_ok "'$bin' instalado correctamente."
        return 0
    fi
    msg_err "La instalación de '$pkg' falló o '$bin' no quedó en el PATH."
    return 1
}

need() { ensure_pkg "$1" "${2:-}"; }

find_sqlcmd() {
    local c
    for c in "$(command -v sqlcmd 2>/dev/null)" /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
        [[ -n "$c" && -x "$c" ]] && { print -r -- "$c"; return 0; }
    done
    return 1
}

journal() {
    if (( EUID == 0 )) || id -nG 2>/dev/null | grep -qwE 'adm|systemd-journal|wheel'; then
        journalctl "$@"
    else
        sudo journalctl "$@"
    fi
}

# --- Motor de menús -----------------------------------------------------------
run_menu() {
    local title="$1"; shift
    local -a items=("$@") parts
    local -A map
    local choice it n fn flag quit_label="Volver al menú anterior"
    [[ "$title" == __MAIN__ ]] && quit_label="Salir"

    while true; do
        map=()
        clear
        if [[ "$title" == __MAIN__ ]]; then
            banner_main
        else
            print "=========================================================="
            print -r -- "  $title"
            print "=========================================================="
        fi

        n=0
        for it in "${items[@]}"; do
            if [[ "$it" == "#"* ]]; then
                print ""
                print -r -- "--- ${it#\#} ---"
                continue
            fi
            parts=("${(@s:|:)it}")
            n=$(( n + 1 ))
            printf " %2d) %s\n" "$n" "${parts[1]}"
            map[$n]="${parts[2]}|${parts[3]}"
        done
        print ""
        print -r -- "  q) $quit_label"
        print "=========================================================="

        prompt_input "Elige una opción [1-$n o q]: " choice || return 0
        case "$choice" in
            q|Q) return 0 ;;
            *)
                if [[ "$choice" == <-> && -n "${map[$choice]:-}" ]]; then
                    fn="${map[$choice]%%|*}"
                    flag="${map[$choice]#*|}"
                    print ""
                    "$fn"
                    [[ "$flag" != nopause ]] && pause_screen
                elif [[ -n "$choice" ]]; then
                    msg_warn "Opción no válida."
                    sleep 1
                fi
                ;;
        esac
    done
}

# ==============================================================================
#  BANNER
# ==============================================================================
banner_main() {
    # Si existe banner.sh en el mismo directorio, ejecutarlo
    if [[ -x "${0:A:h}/banner.sh" ]]; then
        "${0:A:h}/banner.sh"
    else
        # Fallback: banner ASCII interno
        print "╔══════════════════════════════════════════════════════════════════╗"
        print "║                                                                  ║"
        print "║                  P R O M E T H E R I O N  2 1 1 2                ║"
        print "║                 S Y S A D M I N   D A S H B O A R D              ║"
        print "║                                                                  ║"
        print "╚══════════════════════════════════════════════════════════════════╝"
        print -r -- "[*] Usuario Activo : $USER@$HOST"
        print -r -- "[*] Servidor actual: $OS_NAME"
        print -r -- "[*] Gestor paquetes: $PKG_MGR"
        print -r -- "[*] Versión script : v$VERSION ($SCRIPT_NAME)"
    fi
}

# ==============================================================================
#  DATOS DEL SISTEMA
# ==============================================================================
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

detect_db_engines() {
    DB_FOUND=0
    local v
    if find_sqlcmd &>/dev/null || proc_running sqlservr; then
        print " [ OK ] Microsoft SQL Server (sqlcmd o proceso detectado)"; DB_FOUND=1
    fi
    if command -v mysql &>/dev/null || proc_running mysqld || proc_running mariadbd; then
        v=$(mysql --version 2>/dev/null | cut -c1-60)
        print -r -- " [ OK ] MySQL/MariaDB ${v:+(cliente: $v)}"; DB_FOUND=1
    fi
    if command -v psql &>/dev/null || proc_running postgres; then
        v=$(psql --version 2>/dev/null)
        print -r -- " [ OK ] PostgreSQL ${v:+(cliente: $v)}"; DB_FOUND=1
    fi
    if command -v mongod &>/dev/null || proc_running mongod; then
        v=$(mongod --version 2>/dev/null | head -n1)
        print -r -- " [ OK ] MongoDB ${v:+($v)}"; DB_FOUND=1
    fi
    if command -v redis-server &>/dev/null || proc_running redis-server; then
        v=$(redis-server --version 2>/dev/null | awk '{print $3}')
        print -r -- " [ OK ] Redis ${v:+($v)}"; DB_FOUND=1
    fi
}

# ==============================================================================
#  HEALTH CHECK
# ==============================================================================
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
        print " (Usa la opción 9 del menú para conectar y listar BBDD)"
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
    ps -eo user:14,pmem,pcpu,comm --sort=-pmem 2>/dev/null | grep -v "ps " | head -n 6 | sed 's/^/  /'
    print ""
    print " TOP 5 CPU:"
    ps -eo user:14,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | grep -v "ps " | head -n 6 | sed 's/^/  /'
    print ""
}

act_health() {
    clear
    health_check
    log_action "Panorama general del servidor generado"
}

# ==============================================================================
#  MÉTRICAS
# ==============================================================================
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

# ==============================================================================
#  HERRAMIENTAS NATIVAS
# ==============================================================================
act_edit() {
    local -a editors=()
    local e choice target n=1
    for e in nvim vim nano vi; do command -v "$e" &>/dev/null && editors+=("$e"); done
    if (( ${#editors} == 0 )); then msg_err "No hay editores instalados (nvim/vim/nano/vi)."; return 0; fi
    for e in "${editors[@]}"; do print " $n) $e"; n=$(( n + 1 )); done
    prompt_input "Selecciona el editor [1-${#editors}]: " choice
    [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#editors} )) || choice=1
    e="${editors[$choice]}"

    prompt_input "Ruta del archivo a editar: " target
    [[ -z "$target" ]] && return 0
    if [[ -e "$target" && ! -w "$target" ]] || [[ ! -e "$target" && ! -w "${target:h}" ]]; then
        if confirm "Sin permiso de escritura en '$target'. ¿Abrir con sudo?"; then
            "${SUDO[@]}" "$e" "$target"
            log_action "Editor: (sudo) abierto $target"
            return 0
        fi
    fi
    "$e" "$target"
    log_action "Editor: abierto $target"
}

act_grep() {
    local lf pattern
    prompt_input "Ruta del archivo (ej: /var/log/syslog): " lf
    [[ -z "$lf" ]] && return 0
    if [[ ! -f "$lf" ]]; then msg_err "El archivo '$lf' no existe."; return 0; fi
    prompt_input "Patrón (regex extendida, ej: ERROR|FAIL): " pattern
    [[ -z "$pattern" ]] && return 0
    local -a cmd=(grep -inE -- "$pattern" "$lf")
    [[ ! -r "$lf" ]] && cmd=("${SUDO[@]}" "${cmd[@]}")
    msg_info "Primeras 50 coincidencias en '$lf':"
    "${cmd[@]}" | head -n 50
    log_action "Grep: '$pattern' en $lf"
}

act_fileinfo() {
    local f
    prompt_input "Ruta del archivo a analizar: " f
    [[ -z "$f" ]] && return 0
    if [[ ! -f "$f" ]]; then msg_err "El archivo no existe."; return 0; fi

    local ftype fsize fperm fowner fmod facc fcre fchg hash
    ftype=$(file -b "$f" 2>/dev/null); ftype="${ftype:-N/D}"
    fsize=$(stat -c %s "$f" 2>/dev/null)
    fperm=$(stat -c "%A (%a)" "$f" 2>/dev/null)
    fowner=$(stat -c "%U:%G" "$f" 2>/dev/null)
    fmod=$(stat -c %y "$f" 2>/dev/null)
    facc=$(stat -c %x "$f" 2>/dev/null)
    fchg=$(stat -c %z "$f" 2>/dev/null)
    fcre=$(stat -c %w "$f" 2>/dev/null)
    [[ -z "$fcre" || "$fcre" == "-" ]] && fcre="No disponible (FS)"
    hash=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')

    local n_lines n_words n_chars n_bytes
    n_lines=$(( $(wc -l < "$f") )); n_words=$(( $(wc -w < "$f") ))
    n_chars=$(( $(wc -m < "$f") )); n_bytes=$(( $(wc -c < "$f") ))

    local awk_out max_len empty avg
    awk_out=$(awk '{ l=length($0); if (l>max) max=l; if (l==0) empty++ } END { print max+0, empty+0 }' "$f")
    max_len="${awk_out%% *}"; empty="${awk_out##* }"
    avg=$(awk -v w="$n_words" -v l="$n_lines" 'BEGIN{ if (l>0) printf "%.2f", w/l; else print "0.00" }')

    print ""
    box_open "ANÁLISIS TÉCNICO DE ARCHIVO"
    box_text "IDENTIDAD"
    box_sep
    box_row "Tipo" "$ftype"
    box_row "Tamaño" "$(human_bytes $fsize) ($fsize bytes)"
    box_row "Permisos" "$fperm"
    box_row "Propietario" "$fowner"
    box_sep
    box_text "FECHAS"
    box_sep
    box_row "Modificado" "$fmod"
    box_row "Accedido" "$facc"
    box_row "Cambio (ctime)" "$fchg"
    box_row "Creado" "$fcre"
    box_sep
    box_text "CONTENIDO"
    box_sep
    box_row "Líneas" "$n_lines"
    box_row "Palabras" "$n_words"
    box_row "Caracteres" "$n_chars"
    box_row "Bytes" "$n_bytes"
    box_row "Línea + larga" "$max_len caracteres"
    box_row "Líneas vacías" "$empty"
    box_row "Palabras/línea" "$avg"
    box_close
    print -r -- " SHA256: ${hash:-N/D}"
    log_action "Info: análisis técnico de $f"
}

act_diff() {
    local f1 f2
    prompt_input "Ruta del Archivo 1: " f1
    prompt_input "Ruta del Archivo 2: " f2
    if [[ -f "$f1" && -f "$f2" ]]; then
        msg_info "Diferencias (diff -u):"
        diff -u -- "$f1" "$f2" || true
        log_action "Diff: $f1 vs $f2"
    else
        msg_err "Uno o ambos archivos no existen."
    fi
}

act_rsync() {
    need rsync || return 0
    local src dst
    prompt_input "Directorio o archivo origen: " src
    prompt_input "Destino (user@host:/ruta o /ruta): " dst
    [[ -z "$src" || -z "$dst" ]] && return 0
    msg_info "Simulación previa (rsync -avhn):"
    rsync -avhn -- "$src" "$dst" || { msg_err "La simulación falló."; return 0; }
    confirm "¿Ejecutar la sincronización real?" || return 0
    rsync -avh --progress -- "$src" "$dst"
    log_action "Rsync: $src -> $dst"
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

act_net_basic() {
    command -v ip &>/dev/null || { msg_err "Falta 'ip' (paquete iproute2)."; return 0; }
    msg_info "Interfaces de red detectadas:"
    ip -brief address | awk '{print "  > " $1 " (" $2 ") " $3}'
    print -r -- "------------------------------------------"
    print " 1) Direcciones IP detalladas (ip a)"
    print " 2) Tabla de ruteo (ip route)"
    print " 3) Puertos en escucha TCP/UDP (ss -tulpn)"
    print " 4) Prueba rápida de conectividad (ping)"
    print " 5) Ficha técnica de una interfaz"
    local choice
    prompt_input "Selecciona opción [1-5]: " choice
    case "$choice" in
        1) ip address ;;
        2) ip route ;;
        3) "${SUDO[@]}" ss -tulpn ;;
        4) local target
           prompt_input "IP o host de prueba: " target
           valid_host "$target" && ping -c 4 "$target" || msg_err "Destino no válido o sin respuesta." ;;
        5) local iface state mac mtu ipv4 ipv6 gw
           prompt_input "Interfaz (ej: eth0, ens18, wlan0): " iface
           if ! valid_ident "$iface" || ! ip link show dev "$iface" &>/dev/null; then
               msg_err "La interfaz '$iface' no existe."; return 0
           fi
           state=$(ip -o link show dev "$iface" | awk '{for(i=1;i<=NF;i++) if($i=="state"){print $(i+1); exit}}')
           mtu=$(ip -o link show dev "$iface" | awk '{for(i=1;i<=NF;i++) if($i=="mtu"){print $(i+1); exit}}')
           mac=$(ip -o link show dev "$iface" | awk '{for(i=1;i<=NF;i++) if($i=="link/ether"){print $(i+1); exit}}')
           ipv4=$(ip -4 -o addr show dev "$iface" | awk '{print $4; exit}')
           ipv6=$(ip -6 -o addr show dev "$iface" scope global | awk '{print $4; exit}')
           gw=$(ip route show default dev "$iface" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')
           print ""
           box_open "FICHA TÉCNICA DE INTERFAZ"
           box_row "Interfaz" "$iface"
           box_row "Estado" "${state:-Desconocido}"
           box_row "MAC" "${mac:-N/A}"
           box_row "MTU" "${mtu:-N/A}"
           box_row "IPv4" "${ipv4:-N/A}"
           box_row "IPv6" "${ipv6:-N/A}"
           box_row "Gateway" "${gw:-N/A}"
           box_close ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    log_action "Nativo: red básica ($choice)"
}

menu_native() {
    run_menu "HERRAMIENTAS NATIVAS Y DIAGNÓSTICO LINUX" \
        "#TRABAJAR CON ARCHIVOS" \
        "Editar archivos (nvim / vim / nano / vi)|act_edit" \
        "Búsqueda y filtrado de texto (grep -E)|act_grep" \
        "Análisis técnico de archivo (stat, file, wc, sha256)|act_fileinfo" \
        "Comparación de archivos (diff)|act_diff" \
        "Resguardo rápido (rsync con simulación previa)|act_rsync" \
        "#SERVICIOS Y LOGS (SYSTEMCTL / JOURNALCTL)" \
        "Gestión de servicios systemctl (autolistado de activos)|act_systemctl" \
        "Inspección de logs journalctl|act_journal" \
        "#RECURSOS, DISCOS Y RED NATIVA" \
        "Recursos locales y procesos en vivo|act_resources" \
        "Almacenamiento y particiones|act_storage" \
        "Red básica e interfaces|act_net_basic"
}

# ==============================================================================
#  MONITOREO AVANZADO
# ==============================================================================
mon_btop() { need btop && run_interruptible btop; }
mon_htop() { need htop && run_interruptible htop; }

menu_monitor() {
    run_menu "MONITOREO AVANZADO DE RECURSOS" \
        "btop (monitor moderno)|mon_btop" \
        "htop (monitor por procesos)|mon_htop"
}

# ==============================================================================
#  DOCKER
# ==============================================================================
dk_list_names() {
    msg_info "Contenedores:"
    "${DOCKER[@]}" ps -a --format '  > {{.Names}}  ({{.Status}})'
}

dk_ps() {
    "${DOCKER[@]}" ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

dk_stats() {
    msg_info "Snapshot de docker stats (no interactivo):"
    "${DOCKER[@]}" stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
}

dk_logs() {
    dk_list_names
    local name n
    prompt_input "Nombre del contenedor: " name
    [[ -z "$name" ]] && return 0
    valid_ident "$name" || { msg_err "Nombre no válido."; return 0; }
    prompt_input "Cantidad de líneas [Default: 50]: " n
    valid_num "$n" || n=50
    if confirm "¿Seguir en vivo? (Ctrl+C para volver al menú)"; then
        run_interruptible "${DOCKER[@]}" logs -f --tail "$n" "$name"
    else
        "${DOCKER[@]}" logs --tail "$n" "$name"
    fi
    log_action "Docker: logs de $name"
}

dk_ctl() {
    dk_list_names
    local name act
    prompt_input "Nombre del contenedor: " name
    [[ -z "$name" ]] && return 0
    valid_ident "$name" || { msg_err "Nombre no válido."; return 0; }
    print " 1) Restart | 2) Stop | 3) Start"
    prompt_input "Acción [1-3]: " act
    case "$act" in
        1) "${DOCKER[@]}" restart "$name"; log_action "Docker: restart $name" ;;
        2) "${DOCKER[@]}" stop "$name";    log_action "Docker: stop $name" ;;
        3) "${DOCKER[@]}" start "$name";   log_action "Docker: start $name" ;;
        *) msg_warn "Acción no válida." ;;
    esac
}

dk_images() { "${DOCKER[@]}" images; }

dk_prune() {
    msg_info "Uso de disco actual de Docker:"
    "${DOCKER[@]}" system df
    print ""
    msg_warn "Se eliminarán contenedores detenidos, redes sin uso e imágenes huérfanas."
    confirm "¿Ejecutar 'docker system prune -f'?" || { msg_info "Cancelado."; return 0; }
    "${DOCKER[@]}" system prune -f
    log_action "Docker: system prune"
}

menu_docker() {
    if ! need docker; then pause_screen; return 0; fi
    if docker info &>/dev/null; then DOCKER=(docker); else DOCKER=("${SUDO[@]}" docker); fi
    run_menu "GESTIÓN Y ESTADO DE DOCKER LAB" \
        "Ver contenedores (docker ps -a)|dk_ps" \
        "Monitoreo CPU/RAM (docker stats, snapshot)|dk_stats" \
        "Inspeccionar logs de un contenedor|dk_logs" \
        "Reiniciar / Detener / Iniciar contenedor|dk_ctl" \
        "Listar imágenes|dk_images" \
        "Limpieza general (docker system prune)|dk_prune"
}

# ==============================================================================
#  MANTENIMIENTO Y GIT
# ==============================================================================
act_system_update() {
    if [[ "$PKG_MGR" == unknown ]]; then msg_warn "No se detectó gestor de paquetes."; return 0; fi
    confirm "¿Actualizar TODOS los paquetes con $PKG_MGR?" || { msg_info "Cancelado."; return 0; }
    msg_info "Actualizando sistema con $PKG_MGR..."
    case "$PKG_MGR" in
        apt)    "${SUDO[@]}" apt-get update && "${SUDO[@]}" apt-get dist-upgrade -y ;;
        dnf)    "${SUDO[@]}" dnf upgrade -y --refresh --nobest --skip-broken ;;
        yum)    "${SUDO[@]}" yum upgrade -y ;;
        pacman) "${SUDO[@]}" pacman -Syu --noconfirm ;;
        zypper) "${SUDO[@]}" zypper refresh && "${SUDO[@]}" zypper update -y ;;
        apk)    "${SUDO[@]}" apk update && "${SUDO[@]}" apk upgrade ;;
    esac
    log_action "Sistema: actualización con $PKG_MGR"
    [[ -f /var/run/reboot-required ]] && msg_warn "El sistema requiere reinicio (reboot-required)."
}

git_ok() {
    command -v git &>/dev/null || { need git || return 1; }
    if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        msg_err "No hay un repositorio Git en $REPO_DIR"
        msg_info "(Puedes cambiar la ruta con: PROM_REPO_DIR=/ruta $SCRIPT_NAME)"
        return 1
    fi
}

git_status() {
    git_ok || return 0
    msg_info "Rama actual: $(git -C "$REPO_DIR" branch --show-current)"
    print ""
    msg_info "Estado del repositorio:"
    if [[ -z "$(git -C "$REPO_DIR" status -s)" ]]; then
        print "    (El árbol de trabajo está limpio)"
    else
        git -C "$REPO_DIR" status -sb
    fi
    log_action "Git: status"
}

git_log() {
    git_ok || return 0
    msg_info "Últimos 5 commits:"
    git -C "$REPO_DIR" log --oneline --decorate -n 5
    log_action "Git: log"
}

git_pull() {
    git_ok || return 0
    msg_info "Descargando cambios..."
    if ! git -C "$REPO_DIR" pull --ff-only 2>/dev/null; then
        msg_warn "Las ramas han divergido. Intentando merge automático..."
        git -C "$REPO_DIR" pull --no-rebase
    fi
    log_action "Git: pull"
}

git_push() {
    git_ok || return 0
    if [[ -z "$(git -C "$REPO_DIR" status -s)" ]]; then msg_warn "No hay cambios para subir."; return 0; fi
    msg_info "Archivos modificados:"
    git -C "$REPO_DIR" status -s
    print ""
    local def_msg="Actualiza scripts ($(date +%F))" git_msg branch
    prompt_input "Mensaje para commit [Default: '$def_msg']: " git_msg
    git_msg="${git_msg:-$def_msg}"
    msg_info "Subiendo cambios..."
    git -C "$REPO_DIR" add -A && git -C "$REPO_DIR" commit -m "$git_msg" || return 0
    if ! git -C "$REPO_DIR" push; then
        branch=$(git -C "$REPO_DIR" branch --show-current)
        if ! git -C "$REPO_DIR" rev-parse --abbrev-ref '@{u}' &>/dev/null; then
            msg_warn "La rama '$branch' no tiene upstream."
            confirm "¿Ejecutar 'git push -u origin $branch'?" && git -C "$REPO_DIR" push -u origin "$branch"
        fi
    fi
    log_action "Git: push ($git_msg)"
}

git_branch() {
    git_ok || return 0
    local new_branch
    prompt_input "Nombre de la nueva rama (ej: feature-red): " new_branch
    [[ -z "$new_branch" ]] && return 0
    if ! git -C "$REPO_DIR" check-ref-format --branch "$new_branch" &>/dev/null; then
        msg_err "Nombre de rama no válido."; return 0
    fi
    git -C "$REPO_DIR" checkout -b "$new_branch" && log_action "Git: nueva rama $new_branch"
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
    run_menu "MANTENIMIENTO Y SINCRONIZACIÓN GIT" \
        "#SISTEMA" \
        "Actualizar paquetes del sistema ($PKG_MGR)|act_system_update" \
        "#REPOSITORIO: $REPO_DIR" \
        "Ver estado del repositorio (rama y cambios)|git_status" \
        "Ver últimos commits|git_log" \
        "Descargar cambios del servidor (git pull)|git_pull" \
        "Subir cambios locales (add + commit + push)|git_push" \
        "Crear nueva rama de trabajo (checkout -b)|git_branch" \
        "Descartar cambios locales (git restore) [PELIGRO]|git_restore"
}

# ==============================================================================
#  UTILIDADES LOCALES Y CONSULTAS
# ==============================================================================
util_weather_full() {
    local city
    prompt_input "Ciudad (Enter para autodetectar): " city
    msg_info "Consultando wttr.in..."
    ccurl "wttr.in/${city// /+}?lang=es&m"
    log_action "Utilidades: clima completo (${city:-auto})"
}
util_weather_compact() { msg_info "Consultando clima compacto..."; ccurl "wttr.in/?format=3&m"; log_action "Utilidades: clima compacto"; }
util_moon()            { msg_info "Consultando fase lunar...";     ccurl "wttr.in/moon";         log_action "Utilidades: fase lunar"; }

util_sun() {
    need jq || return 0
    local lat lng
    prompt_input "Latitud [Default: -33.45 (Santiago)]: " lat
    prompt_input "Longitud [Default: -70.66 (Santiago)]: " lng
    lat="${lat:--33.45}"; lng="${lng:--70.66}"
    msg_info "Amanecer/atardecer (UTC) para ($lat, $lng):"
    ccurl --get --data-urlencode "lat=$lat" --data-urlencode "lng=$lng" --data "formatted=0" \
        "https://api.sunrise-sunset.org/json" | jq '.results'
    log_action "Utilidades: sunrise/sunset ($lat,$lng)"
}

util_password() {
    local len sym set
    prompt_input "Largo de la contraseña [Default: 20]: " len
    valid_num "$len" && (( len >= 8 && len <= 128 )) || len=20
    set='A-Za-z0-9'
    confirm "¿Incluir símbolos?" && set='A-Za-z0-9!@#%^*_+=-'
    msg_info "Contraseña aleatoria ($len caracteres):"
    LC_ALL=C tr -dc "$set" < /dev/urandom 2>/dev/null | head -c "$len"
    print ""
    log_action "Utilidades: contraseña local generada"
}

util_uuid() {
    msg_info "UUID v4 generado localmente:"
    if [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
    elif command -v uuidgen &>/dev/null; then uuidgen | tr '[:upper:]' '[:lower:]'
    else openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
    fi
    log_action "Utilidades: UUID local"
}

util_qr() {
    local txt
    prompt_input "Texto o URL para el QR: " txt
    [[ -z "$txt" ]] && return 0
    if command -v qrencode &>/dev/null; then
        qrencode -t ansiutf8 -- "$txt"
    elif command -v mkqr &>/dev/null; then
        mkqr "$txt"
    elif need qrencode; then
        qrencode -t ansiutf8 -- "$txt"
    else
        msg_warn "Fallback remoto: el texto se enviaría a qrenco.de."
        confirm "¿Continuar?" || return 0
        ccurl "qrenco.de/$(urlencode "$txt")"
    fi
    log_action "Utilidades: QR generado"
}

util_dict() {
    local w
    prompt_input "Palabra a consultar (inglés / término tech): " w
    valid_ident "$w" || { msg_err "Palabra no válida."; return 0; }
    msg_info "Definición de '$w':"
    ccurl "dict.org/d:$w" | grep -v '^$' | head -n 40
    log_action "Utilidades: diccionario '$w'"
}

util_cheat() {
    local c
    prompt_input "Comando a consultar (ej: rsync, tar, git): " c
    valid_ident "$c" || { msg_err "Comando no válido."; return 0; }
    msg_info "cheat.sh/$c"
    ccurl "cht.sh/$c"
    log_action "Utilidades: cheat.sh $c"
}

util_wiki() {
    need jq || return 0
    local term
    prompt_input "Término o título en Wikipedia (ej: Linux): " term
    [[ -z "$term" ]] && return 0
    msg_info "Resumen de '$term' en es.wikipedia:"
    ccurl "https://es.wikipedia.org/api/rest_v1/page/summary/$(urlencode "$term")" \
        | jq -r '.extract // .detail // "No encontrado"'
    log_action "Utilidades: wikipedia '$term'"
}

util_fx() {
    need jq || return 0
    local base targets
    prompt_input "Moneda base [Default: USD]: " base
    base="${${base:-USD}:u}"
    valid_ident "$base" || { msg_err "Moneda no válida."; return 0; }
    prompt_input "Monedas destino separadas por coma [Default: CLP,USD,EUR,ARS,BRL]: " targets
    targets="${targets:-CLP,USD,EUR,ARS,BRL}"
    msg_info "Tipo de cambio desde $base:"
    ccurl "https://open.er-api.com/v6/latest/$base" | jq --arg l "$targets" \
        '{base: .base_code, actualizado: .time_last_update_utc,
          tasas: ((.rates // {}) as $r | ($l | split(",") | map(ascii_upcase | gsub(" ";""))) | map({key: ., value: $r[.]}) | from_entries)}'
    log_action "Utilidades: tipo de cambio base $base"
}

util_crypto() {
    need jq || return 0
    local ids fiat
    prompt_input "IDs de cripto separados por coma [Default: bitcoin,ethereum]: " ids
    ids="${ids:-bitcoin,ethereum}"
    prompt_input "Moneda fiat (usd, eur, clp...) [Default: usd]: " fiat
    fiat="${fiat:-usd}"
    msg_info "Cotización de $ids en $fiat:"
    ccurl --get --data-urlencode "ids=$ids" --data-urlencode "vs_currencies=$fiat" \
        "https://api.coingecko.com/api/v3/simple/price" | jq .
    log_action "Utilidades: cripto $ids/$fiat"
}

menu_utils() {
    run_menu "UTILIDADES LOCALES Y CONSULTAS" \
        "#CLIMA Y ASTRONOMÍA" \
        "Clima actual completo (wttr.in)|util_weather_full" \
        "Clima compacto de una línea|util_weather_compact" \
        "Fase lunar actual|util_moon" \
        "Amanecer y atardecer (sunrise-sunset.org)|util_sun" \
        "#GENERACIÓN LOCAL (SIN RED)" \
        "Generar contraseña segura|util_password" \
        "Generar UUID v4|util_uuid" \
        "Generar código QR en terminal|util_qr" \
        "#CONSULTAS Y REFERENCIA" \
        "Diccionario / definición de palabras (dict.org)|util_dict" \
        "Hojas de ayuda rápida de comandos (cht.sh)|util_cheat" \
        "Resumen de Wikipedia|util_wiki" \
        "#FINANZAS" \
        "Tipo de cambio de divisas (open.er-api.com)|util_fx" \
        "Cotización de criptomonedas (coingecko)|util_crypto"
}

# ==============================================================================
#  AUTOMATIZACIÓN (IaC) - dsv1.1
# ==============================================================================

# Busca un directorio de trabajo lógico para Ansible/Terraform
find_workdir() {
    local type="$1" # "ansible" o "terraform"
    local default_dir=""
    
    if [[ "$type" == "ansible" ]]; then
        for d in "$HOME/ansible" "$HOME/playbooks" "/etc/ansible" "$HOME/proyectos/ansible" "$HOME/repos/ansible"; do
            if [[ -d "$d" ]]; then default_dir="$d"; break; fi
        done
    else
        for d in "$HOME/terraform" "$HOME/infra" "$HOME/proyectos/terraform" "$HOME/repos/terraform"; do
            if [[ -d "$d" ]]; then default_dir="$d"; break; fi
        done
    fi
    
    [[ -z "$default_dir" ]] && default_dir="$PWD"
    
    local workdir
    prompt_input "Directorio donde buscar [Default: $default_dir]: " workdir >&2
    print -r -- "${workdir:-$default_dir}"
}

find_files() {
    local dir="$1" pattern="$2"
    [[ -z "$dir" ]] && dir="."
    find "$dir" -maxdepth 4 -type f -name "$pattern" \
        -not -path '*/\.*' -not -path '*/node_modules/*' \
        -not -path '*/venv/*' -not -path '*/__pycache__/*' 2>/dev/null | sort
}

# --- Submenú Ansible ---
ans_status() {
    need ansible || return 0
    msg_info "Versión de Ansible:"
    ansible --version | head -n 3
    log_action "Ansible: status"
}

ans_inventories() {
    local workdir; workdir=$(find_workdir ansible)
    if [[ ! -d "$workdir" ]]; then msg_err "El directorio '$workdir' no existe."; return 0; fi
    
    msg_info "Buscando inventarios en '$workdir'..."
    local -a invs=(${(f)"$(find_files "$workdir" 'hosts' ; find_files "$workdir" '*inventory*')"})
    
    if (( ${#invs} == 0 )); then
        msg_warn "No se encontraron archivos de inventario (hosts, inventory*)."
        return 0
    fi
    
    local i=1 f
    for f in "${invs[@]}"; do print " $i) $f"; i=$((i+1)); done
    log_action "Ansible: inventarios listados en $workdir"
}

ans_ping() {
    need ansible || return 0
    local workdir; workdir=$(find_workdir ansible)
    
    local -a invs=(${(f)"$(find_files "$workdir" 'hosts' ; find_files "$workdir" '*inventory*')"})
    if (( ${#invs} == 0 )); then msg_err "No se encontraron inventarios en '$workdir'."; return 0; fi
    
    local i=1 f
    for f in "${invs[@]}"; do print " $i) $f"; i=$((i+1)); done
    local inv
    prompt_input "Selecciona el número del inventario [Default: 1]: " inv
    inv="${inv:-1}"
    
    if [[ "$inv" == <-> ]] && (( inv >= 1 && inv <= ${#invs} )); then
        local target="${invs[$inv]}"
        msg_info "Haciendo ping a todos los hosts de '$target'..."
        ansible all -i "$target" -m ping
        log_action "Ansible: ping a $target"
    else
        msg_err "Selección no válida."
    fi
}

ans_playbooks() {
    need ansible || return 0
    local workdir; workdir=$(find_workdir ansible)
    
    msg_info "Buscando playbooks (.yml) en '$workdir'..."
    local -a plays=(${(f)"$(find_files "$workdir" '*.yml')"})
    if (( ${#plays} == 0 )); then
        msg_warn "No se encontraron archivos .yml en '$workdir'."
        msg_info "Sugerencia: crea un directorio como ~/ansible o ~/playbooks y coloca tus archivos ahí."
        return 0
    fi
    
    local i=1 f
    for f in "${plays[@]}"; do print " $i) $f"; i=$((i+1)); done
    local play
    prompt_input "Selecciona el número del playbook a ejecutar (o 'q' para cancelar): " play
    [[ -z "$play" || "$play" == "q" ]] && return 0
    
    if [[ "$play" == <-> ]] && (( play >= 1 && play <= ${#plays} )); then
        local target="${plays[$play]}"
        print ""
        msg_warn "Ejecutando playbook: $target"
        print " 1) Simulación (--check)"
        print " 2) Ejecución real"
        local mode
        prompt_input "Selecciona modo [1-2]: " mode
        case "$mode" in
            1) ansible-playbook "$target" --check ;;
            2) ansible-playbook "$target" ;;
            *) msg_warn "Opción no válida."; return 0 ;;
        esac
        log_action "Ansible: playbook $target (modo $mode)"
    else
        msg_err "Selección no válida."
    fi
}

menu_ansible() {
    run_menu "ANSIBLE (Gestión de configuración)" \
        "Ver versión y estado|ans_status" \
        "Listar inventarios (hosts, inventory*)|ans_inventories" \
        "Probar conexión con inventario (ansible ping)|ans_ping" \
        "Listar y ejecutar playbooks (.yml)|ans_playbooks"
}

# --- Submenú Terraform ---
tf_status() {
    need terraform || return 0
    msg_info "Versión de Terraform:"
    terraform version
    log_action "Terraform: status"
}

tf_dirs() {
    local workdir; workdir=$(find_workdir terraform)
    if [[ ! -d "$workdir" ]]; then msg_err "El directorio '$workdir' no existe."; return 0; fi
    
    msg_info "Buscando directorios con archivos .tf en '$workdir'..."
    local -a dirs=(${(f)"$(find_files "$workdir" '*.tf' | xargs -n1 dirname 2>/dev/null | sort -u)"})
    
    if (( ${#dirs} == 0 )); then
        msg_warn "No se encontraron proyectos Terraform (.tf) en '$workdir'."
        msg_info "Sugerencia: crea un directorio como ~/terraform o ~/infra y coloca tus archivos ahí."
        return 0
    fi
    
    local i=1 d
    for d in "${dirs[@]}"; do print " $i) $d"; i=$((i+1)); done
    log_action "Terraform: directorios listados en $workdir"
}

tf_plan() {
    need terraform || return 0
    local workdir; workdir=$(find_workdir terraform)
    
    local -a dirs=(${(f)"$(find_files "$workdir" '*.tf' | xargs -n1 dirname 2>/dev/null | sort -u)"})
    if (( ${#dirs} == 0 )); then msg_err "No se encontraron proyectos Terraform en '$workdir'."; return 0; fi
    
    local i=1 d
    for d in "${dirs[@]}"; do print " $i) $d"; i=$((i+1)); done
    local proj
    prompt_input "Selecciona el número del proyecto [Default: 1]: " proj
    proj="${proj:-1}"
    
    if [[ "$proj" == <-> ]] && (( proj >= 1 && proj <= ${#dirs} )); then
        local target="${dirs[$proj]}"
        msg_info "Ejecutando 'terraform init' y 'terraform plan' en $target..."
        ( cd "$target" && terraform init -input=false >/dev/null && terraform plan )
        log_action "Terraform: plan en $target"
    else
        msg_err "Selección no válida."
    fi
}

tf_fmt() {
    need terraform || return 0
    local workdir; workdir=$(find_workdir terraform)
    msg_info "Validando formato de archivos .tf en '$workdir' (check)..."
    ( cd "$workdir" && terraform fmt -check -recursive -diff )
    log_action "Terraform: fmt check en $workdir"
}

menu_terraform() {
    run_menu "TERRAFORM (Infraestructura como código)" \
        "Ver versión y estado|tf_status" \
        "Listar proyectos (.tf)|tf_dirs" \
        "Planificar cambios (init + plan)|tf_plan" \
        "Validar formato (fmt -check)|tf_fmt"
}

# --- Menú Principal de Automatización ---
menu_automation() {
    run_menu "HERRAMIENTAS DE AUTOMATIZACIÓN (IaC)" \
        "Ansible - Gestión de configuración|menu_ansible|nopause" \
        "Terraform - Infraestructura como código|menu_terraform|nopause"
}

# ==============================================================================
#  CRON Y LOGS
# ==============================================================================
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
#  BASES DE DATOS
# ==============================================================================
db_show() {
    print -r -- "--- VERSIÓN ---"
    print -r -- "$1" | head -n 1
    print ""
    print -r -- "--- BASES DE DATOS ---"
    print -r -- "$2" | sed '/^[[:space:]]*$/d; s/^/  > /'
}

db_detect() {
    msg_info "Buscando motores de base de datos instalados..."
    detect_db_engines
    (( DB_FOUND == 0 )) && print "  (ninguno detectado)"
}

db_mssql() {
    local bin
    if ! bin=$(find_sqlcmd); then
        msg_warn "'sqlcmd' no está instalado."; install_hint sqlcmd; return 0
    fi
    local -a extra=()
    "$bin" '-?' 2>&1 | grep -qE 'Version (1[7-9]|[2-9][0-9])' && extra=(-C)

    local host user pass out rc dbs
    prompt_input "Servidor [Default: localhost]: " host;   host="${host:-localhost}"
    prompt_input "Usuario [Default: sa]: " user;           user="${user:-sa}"
    prompt_password "Contraseña: " pass
    [[ -z "$pass" ]] && { msg_err "SQL Server requiere contraseña."; return 0; }
    valid_host "$host" || { msg_err "Servidor no válido."; return 0; }

    msg_info "Consultando versión y bases de datos en $host..."
    out=$(SQLCMDPASSWORD="$pass" "$bin" -S "$host" -U "$user" "${extra[@]}" -l 5 -h -1 -W \
          -Q "SET NOCOUNT ON; SELECT @@VERSION" 2>&1); rc=$?
    if (( rc != 0 )) || [[ "$out" == *"Sqlcmd: Error"* || "$out" == *"Msg "* ]]; then
        msg_err "No se pudo conectar a SQL Server."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        print "        Revisa credenciales, que 'mssql-server' esté activo y el puerto 1433."
        log_action "BBDD: fallo de conexión SQL Server ($host)"
        return 0
    fi
    dbs=$(SQLCMDPASSWORD="$pass" "$bin" -S "$host" -U "$user" "${extra[@]}" -l 5 -h -1 -W \
          -Q "SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name" 2>&1)
    db_show "$out" "$dbs"
    log_action "BBDD: consulta SQL Server ($host)"
}

db_mysql() {
    need mysql || return 0
    local user pass out rc dbs
    prompt_input "Usuario [Default: root]: " user; user="${user:-root}"
    prompt_password "Contraseña (vacía = auth por socket con sudo): " pass
    valid_ident "$user" || { msg_err "Usuario no válido."; return 0; }

    local -a my=(mysql -u "$user" -N -B)
    [[ -z "$pass" ]] && my=("${SUDO[@]}" "${my[@]}")

    msg_info "Consultando versión y bases de datos..."
    out=$(MYSQL_PWD="$pass" "${my[@]}" -e "SELECT VERSION();" 2>&1); rc=$?
    if (( rc != 0 )); then
        msg_err "No se pudo conectar a MySQL/MariaDB."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        print "        Revisa credenciales o que el servicio (mysqld/mariadb) esté activo."
        log_action "BBDD: fallo de conexión MySQL/MariaDB"
        return 0
    fi
    dbs=$(MYSQL_PWD="$pass" "${my[@]}" -e "SHOW DATABASES;" 2>&1)
    db_show "$out" "$dbs"
    log_action "BBDD: consulta MySQL/MariaDB"
}

db_pg() {
    need psql || return 0
    local user dbname pass out rc dbs
    prompt_input "Usuario [Default: postgres]: " user;      user="${user:-postgres}"
    prompt_input "Base de datos [Default: postgres]: " dbname; dbname="${dbname:-postgres}"
    prompt_password "Contraseña (vacía = auth local 'peer' como ese usuario): " pass
    valid_ident "$user" && valid_ident "$dbname" || { msg_err "Usuario o base no válidos."; return 0; }

    local -a pg
    if [[ -n "$pass" ]]; then
        pg=(psql -h localhost -U "$user" -d "$dbname" -At)
    elif (( EUID == 0 )); then
        pg=(runuser -u "$user" -- psql -d "$dbname" -At)
    else
        pg=(sudo -u "$user" psql -d "$dbname" -At)
    fi

    msg_info "Consultando versión y bases de datos..."
    out=$(PGPASSWORD="$pass" "${pg[@]}" -c "SELECT version();" 2>&1); rc=$?
    if (( rc != 0 )); then
        msg_err "No se pudo conectar a PostgreSQL."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        print "        Revisa usuario/base, contraseña o que el servicio (postgresql) esté activo."
        log_action "BBDD: fallo de conexión PostgreSQL"
        return 0
    fi
    dbs=$(PGPASSWORD="$pass" "${pg[@]}" -c "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1;" 2>&1)
    db_show "$out" "$dbs"
    log_action "BBDD: consulta PostgreSQL"
}

menu_db() {
    run_menu "GESTIÓN DE BASES DE DATOS (BBDD)" \
        "Detectar motores instalados|db_detect" \
        "Conectar a SQL Server (mssql) y listar BBDD|db_mssql" \
        "Conectar a MySQL/MariaDB y listar BBDD|db_mysql" \
        "Conectar a PostgreSQL y listar BBDD|db_pg"
}

# ==============================================================================
#  NMAP
# ==============================================================================
nm_target() {
    local _t
    prompt_input "$2" _t
    [[ -z "$_t" ]] && return 1
    valid_host "$_t" || { msg_err "Objetivo no válido."; return 1; }
    typeset -g "$1=$_t"
}
nm_quick() {
    local t; nm_target t "IP o hostname objetivo: " || return 0
    msg_info "Escaneo rápido en '$t'..."; run_interruptible nmap -T4 "$t"
    log_action "Nmap: escaneo rápido en $t"
}
nm_versions() {
    local t; nm_target t "IP o hostname objetivo: " || return 0
    msg_info "Detección de versiones (-sV) en '$t'..."; run_interruptible nmap -sV -T4 "$t"
    log_action "Nmap: -sV en $t"
}
nm_aggressive() {
    local t; nm_target t "IP o hostname objetivo: " || return 0
    msg_info "Escaneo agresivo (-A) en '$t' (requiere root para detectar SO)..."
    run_interruptible "${SUDO[@]}" nmap -A -T4 "$t"
    log_action "Nmap: -A en $t"
}
nm_discover() {
    local def net
    def=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4; exit}')
    prompt_input "Rango de red [Default: ${def:-192.168.1.0/24}]: " net
    net="${net:-${def:-192.168.1.0/24}}"
    valid_host "$net" || { msg_err "Rango no válido."; return 0; }
    msg_info "Descubriendo hosts activos en '$net'..."; run_interruptible nmap -sn "$net"
    log_action "Nmap: ping scan en $net"
}

menu_nmap() {
    if ! need nmap; then pause_screen; return 0; fi
    if (( NMAP_ACK == 0 )); then
        print ""
        msg_warn "Escanear sistemas ajenos sin autorización puede ser ilegal."
        confirm "¿Confirmas que solo escanearás equipos propios o autorizados?" || return 0
        NMAP_ACK=1
    fi
    run_menu "AUDITORÍA DE RED Y SEGURIDAD (NMAP) - $(nmap --version | head -n 1 | cut -c1-40)" \
        "Escaneo rápido de puertos en IP/Host|nm_quick" \
        "Escaneo completo con detección de versiones (-sV)|nm_versions" \
        "Escaneo agresivo (SO, versiones y scripts -A)|nm_aggressive" \
        "Descubrimiento de hosts activos en la red local|nm_discover"
}

# ==============================================================================
#  DIAGNÓSTICO DE RED AVANZADO
# ==============================================================================
na_http() {
    local u
    prompt_input "URL o IP objetivo (ej: https://google.com): " u
    [[ -z "$u" || "$u" == -* ]] && return 0
    msg_info "Análisis HTTP detallado..."
    print -r -- "------------------------------------------"
    curl -I -L -s --max-time 10 \
        -w "\n[Métricas]\nTiempo total: %{time_total}s\nCódigo HTTP: %{http_code}\nIP remota: %{remote_ip}\n" "$u"
    log_action "RedAv: curl detallado a $u"
}

na_ping() {
    local h c
    prompt_input "IP o dominio destino: " h
    valid_host "$h" || { msg_err "Destino no válido."; return 0; }
    prompt_input "Cantidad de paquetes [Default: 4]: " c
    valid_num "$c" && (( c >= 1 && c <= 100 )) || c=4
    msg_info "Enviando $c paquetes ICMP a '$h'..."
    ping -c "$c" "$h"
    log_action "RedAv: ping a $h ($c)"
}

na_port() {
    local h p
    prompt_input "IP o host remoto: " h
    prompt_input "Puerto a verificar (ej: 22, 80, 443): " p
    valid_host "$h" || { msg_err "Host no válido."; return 0; }
    valid_num "$p" && (( p >= 1 && p <= 65535 )) || { msg_err "Puerto no válido (1-65535)."; return 0; }
    msg_info "Probando $h:$p ..."
    if command -v nc &>/dev/null || need nc; then
        nc -zv -w 3 "$h" "$p"
    elif command -v bash &>/dev/null; then
        if timeout 4 bash -c 'exec 3<>/dev/tcp/$0/$1' "$h" "$p" 2>/dev/null; then
            msg_ok "Puerto $p en $h ABIERTO y accesible."
        else
            msg_warn "No se pudo conectar a $h:$p (cerrado o filtrado)."
        fi
    else
        msg_err "Ni nc ni bash disponibles."
    fi
    log_action "RedAv: test de puerto $h:$p"
}

na_trace() {
    local h
    prompt_input "IP o dominio para trazado de ruta: " h
    valid_host "$h" || { msg_err "Destino no válido."; return 0; }
    msg_info "Trazando ruta hacia $h..."
    if   command -v traceroute &>/dev/null; then run_interruptible traceroute "$h"
    elif command -v tracepath  &>/dev/null; then run_interruptible tracepath "$h"
    elif need traceroute;                   then run_interruptible traceroute "$h"
    else msg_err "No hay herramienta de trazado disponible."; fi
    log_action "RedAv: traceroute a $h"
}

na_dns() {
    local d t
    prompt_input "Dominio a consultar (ej: google.com): " d
    valid_host "$d" || { msg_err "Dominio no válido."; return 0; }
    if command -v dig &>/dev/null || need dig; then
        msg_info "Registros DNS de $d:"
        for t in A AAAA MX NS TXT; do
            print -r -- "--- $t ---"
            dig +noall +answer "$d" "$t"
        done
    elif command -v nslookup &>/dev/null; then
        nslookup "$d"
    else
        getent ahosts "$d"
    fi
    log_action "RedAv: DNS de $d"
}

na_publicip() {
    need jq || return 0
    msg_info "Obteniendo información de red pública..."
    local j; j=$(ccurl "https://ipinfo.io/json")
    [[ -z "$j" ]] && { msg_err "Sin respuesta de ipinfo.io."; return 0; }
    print ""
    box_open "FICHA TÉCNICA DE RED (IP PÚBLICA)"
    box_row "IP pública" "$(print -r -- "$j" | jq -r '.ip // "N/A"')"
    box_row "Ciudad" "$(print -r -- "$j" | jq -r '.city // "N/A"')"
    box_row "Región" "$(print -r -- "$j" | jq -r '.region // "N/A"')"
    box_row "País" "$(print -r -- "$j" | jq -r '.country // "N/A"')"
    box_row "ISP / Org" "$(print -r -- "$j" | jq -r '.org // "N/A"')"
    box_row "Zona horaria" "$(print -r -- "$j" | jq -r '.timezone // "N/A"')"
    box_close
    log_action "RedAv: ficha IP pública"
}

na_whois() {
    local t
    prompt_input "Dominio o IP para WHOIS: " t
    valid_host "$t" || { msg_err "Destino no válido."; return 0; }
    need whois || return 0
    whois "$t" | head -n 40
    log_action "RedAv: whois $t"
}

na_ssl() {
    command -v openssl &>/dev/null || { msg_err "openssl no está instalado."; return 0; }
    local h out subj issu not_b not_a cn iss days end_ts
    prompt_input "Dominio para inspeccionar el certificado SSL: " h
    valid_host "$h" || { msg_err "Dominio no válido."; return 0; }
    msg_info "Consultando certificado de $h:443..."
    out=$(timeout 10 openssl s_client -servername "$h" -connect "${h}:443" < /dev/null 2>/dev/null \
          | openssl x509 -noout -subject -issuer -dates 2>/dev/null)
    if [[ -z "$out" ]]; then
        msg_warn "No se pudo obtener el certificado (bloqueo de red o dominio inválido)."
        return 0
    fi
    subj=$(print -r -- "$out" | grep '^subject=');   issu=$(print -r -- "$out" | grep '^issuer=')
    not_b=$(print -r -- "$out" | sed -n 's/^notBefore=//p'); not_a=$(print -r -- "$out" | sed -n 's/^notAfter=//p')
    cn=$(print -r -- "$subj" | sed -nE 's/.*CN ?= ?([^,\/]+).*/\1/p')
    iss=$(print -r -- "$issu" | sed -nE 's/.*O ?= ?([^,\/]+).*/\1/p')
    end_ts=$(date -d "$not_a" +%s 2>/dev/null)
    if [[ -n "$end_ts" ]]; then
        days=$(( (end_ts - $(date +%s)) / 86400 ))
        (( days < 15 )) && days="$days  (¡por vencer!)"
    else
        days="N/D"
    fi
    print ""
    box_open "FICHA TÉCNICA DE CERTIFICADO SSL"
    box_row "Dominio" "$h"
    box_row "CN (subject)" "${cn:-${subj#subject=}}"
    box_row "Emisor" "${iss:-${issu#issuer=}}"
    box_row "Válido desde" "$not_b"
    box_row "Válido hasta" "$not_a"
    box_row "Días restantes" "$days"
    box_close
    log_action "RedAv: SSL de $h"
}

na_httpcard() {
    local u metrics code t_dns t_tcp t_tls t_ttfb t_total
    prompt_input "URL o host a verificar (ej: https://google.com): " u
    [[ -z "$u" || "$u" == -* ]] && return 0
    [[ "$u" != http* ]] && u="https://$u"
    msg_info "Verificando estado HTTP..."
    metrics=$(curl -s -o /dev/null -L --max-time 10 \
        -w "%{http_code}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}" "$u")
    IFS='|' read -r code t_dns t_tcp t_tls t_ttfb t_total <<< "$metrics"
    print ""
    box_open "FICHA TÉCNICA HTTP (tiempos acumulados)"
    box_row "URL objetivo" "$u"
    box_row "Código HTTP" "${code:-000}$([[ "${code:-000}" == 000 ]] && print ' (sin respuesta)')"
    box_sep
    box_row "DNS lookup" "$(ms_fmt "$t_dns")"
    box_row "TCP connect" "$(ms_fmt "$t_tcp")"
    awk -v t="${t_tls:-0}" 'BEGIN{exit !(t>0)}' && box_row "TLS handshake" "$(ms_fmt "$t_tls")"
    box_row "TTFB (1er byte)" "$(ms_fmt "$t_ttfb")"
    box_row "Tiempo total" "$(ms_fmt "$t_total")"
    box_close
    log_action "RedAv: ficha HTTP $u -> ${code:-000}"
}

na_shorten() {
    local u
    prompt_input "URL a acortar: " u
    [[ -z "$u" ]] && return 0
    msg_warn "La URL se enviará a tinyurl.com."
    confirm "¿Continuar?" || return 0
    ccurl --get --data-urlencode "url=$u" "https://tinyurl.com/api-create.php"
    print ""
    log_action "RedAv: TinyURL generado"
}

na_speed() {
    msg_info "Descargando 25 MB de Cloudflare para medir velocidad..."
    local r bps secs
    r=$(curl -o /dev/null -s --max-time 20 -w '%{speed_download}|%{time_total}' \
        -H "User-Agent: Mozilla/5.0" "https://speed.cloudflare.com/__down?bytes=25000000")
    bps="${r%%|*}"; secs="${r##*|}"
    awk -v b="${bps:-0}" -v s="${secs:-0}" 'BEGIN{printf "Velocidad media: %.2f Mbps (%.2f MB/s) en %.1f s\n", b*8/1000000, b/1000000, s}'
    log_action "RedAv: speedtest Cloudflare"
}

menu_netadv() {
    run_menu "DIAGNÓSTICO Y PRUEBAS DE RED AVANZADAS" \
        "#CONECTIVIDAD Y RESOLUCIÓN" \
        "Test HTTP/HTTPS detallado (cabeceras y tiempos)|na_http" \
        "Ping personalizable (ICMP)|na_ping" \
        "Verificación de puerto remoto abierto|na_port" \
        "Trazado de ruta (traceroute / tracepath)|na_trace" \
        "Resolución y consulta DNS (A, AAAA, MX, NS, TXT)|na_dns" \
        "#IDENTIDAD Y METADATOS DE RED" \
        "IP pública y detalles (ficha técnica)|na_publicip" \
        "WHOIS de dominio o IP|na_whois" \
        "Certificado SSL de un dominio (ficha técnica)|na_ssl" \
        "#UTILIDADES WEB" \
        "Verificar estado HTTP y tiempos (ficha técnica)|na_httpcard" \
        "Acortar URL (tinyurl)|na_shorten" \
        "Test de velocidad de descarga (Cloudflare)|na_speed"
}

# ==============================================================================
#  MENÚ PRINCIPAL Y PUNTO DE ENTRADA
# ==============================================================================
menu_main() {
    run_menu __MAIN__ \
        "Panorama general del servidor (Health Check)|act_health" \
        "Herramientas nativas (archivos, servicios, red)|menu_native|nopause" \
        "Monitoreo avanzado de recursos (btop, htop)|menu_monitor|nopause" \
        "Servicios y contenedores Docker|menu_docker|nopause" \
        "Mantenimiento de sistema y sincronización Git|menu_git|nopause" \
        "Utilidades locales y consultas (clima, QR, claves)|menu_utils|nopause" \
        "Herramientas de automatización (Ansible, Terraform)|menu_automation|nopause" \
        "Tareas programadas (cron/timers) y logs del sistema|menu_cron_logs|nopause" \
        "Gestión de bases de datos (BBDD)|menu_db|nopause" \
        "Auditoría de red y seguridad (Nmap)|menu_nmap|nopause" \
        "Diagnóstico y pruebas de red avanzadas|menu_netadv|nopause"
}

usage() {
    cat <<EOF
$SCRIPT_NAME v$VERSION - Prometherion2112 Sysadmin Dashboard (DS Edition)

Uso:
  $SCRIPT_NAME             Menú interactivo
  $SCRIPT_NAME health      Health Check sin menú (SSH / cron)
  $SCRIPT_NAME metrics     Métricas formato Prometheus (textfile collector)
  $SCRIPT_NAME version     Muestra la versión
  $SCRIPT_NAME help        Esta ayuda

Variables de entorno:
  PROM_REPO_DIR   Ruta del repo Git (default: \$HOME/.local/bin/scripts)
  NO_COLOR=1      Desactiva colores

Log de acciones: $LOG_FILE
EOF
}

main() {
    detect_pkg_manager
    OS_NAME=$(get_os_name)

    case "${1:-menu}" in
        menu)
            if [[ ! -t 0 || ! -t 1 ]]; then
                msg_err "El menú requiere una terminal interactiva. Prueba: $SCRIPT_NAME health"
                return 1
            fi
            OLD_STTY=$(stty -g 2>/dev/null)
            trap 'stty "$OLD_STTY" 2>/dev/null' EXIT TERM
            trap 'stty "$OLD_STTY" 2>/dev/null; true' INT
            init_log
            menu_main
            print "¡Hasta luego, Leonardo! Cerrando dashboard."
            ;;
        health)             init_log; health_check ;;
        metrics)            metrics_output ;;
        version|-v|--version) print "$SCRIPT_NAME v$VERSION" ;;
        help|-h|--help)     usage ;;
        *)                  usage; return 1 ;;
    esac
}

main "$@"
