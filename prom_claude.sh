#!/usr/bin/env zsh

# ==============================================================================
#  PROMETHERION2112 - SYSADMIN TOOLKIT & DASHBOARD  (edición prom_claude)
#  Repositorio: git@github.com:leocampos81/scripts.git
#  Autor: Leonardo Campos (https://github.com/leocampos81)
#  Refactor v5.x: Claude (sobre la base v4.8 de la Rama DS, con aportes de DS dsv1.3)
# ==============================================================================
#  USO
#    ./prom_claude.sh            Menú interactivo
#    ./prom_claude.sh health     Health Check sin menú (apto para SSH / cron)
#    ./prom_claude.sh metrics    Métricas en formato Prometheus (textfile collector)
#    ./prom_claude.sh version | help
#
#  DISTROS (el gestor de paquetes se detecta solo)
#    Debian / Ubuntu / Mint (apt) · Rocky / RHEL / Fedora (dnf, yum)
#    Arch (pacman) · openSUSE (zypper) · Alpine (apk, funciones limitadas)
#  Requiere zsh. Health Check completo: iproute2, procps, coreutils.
# ==============================================================================
#  BITÁCORA DE CAMBIOS (CHANGELOG)
# ==============================================================================
#  [2026-11-14] - v5.2 (Rama Claude) - candidata a liberación
#    FUSIÓN CON LA RAMA DS (lo mejor de dsv1.3, con guardarraíles)
#      * BBDD: ejecutar .sql y consultas rápidas en SQL Server, MySQL/MariaDB y
#        PostgreSQL (idea DS). Nuevo: sql_guard pide confirmación si el SQL
#        modifica datos/estructura y exige escribir CONFIRMAR si hay
#        DELETE/UPDATE sin WHERE; confirma el archivo antes de correrlo; se
#        puede cambiar entre archivo/consulta sin salir de la sesión; PostgreSQL
#        con ON_ERROR_STOP y transacción opcional; los .sql entran por stdin
#        (con 'sudo -u postgres' el usuario postgres no lee tu /home).
#      * banner.sh externo opcional (idea DS), ahora resuelto con SCRIPT_DIR.
#    CORRECCIONES
#      * banner.sh solo se hallaba si el cwd era la carpeta del script ($0 dentro
#        de una función es el nombre de la función).
#      * git pull: sin merge automático ni editor; si las ramas divergieron
#        pregunta (merge / rebase / cancelar) y distingue otras causas de error.
#      * ansible-playbook se ejecuta desde la carpeta del playbook (respeta su
#        ansible.cfg y roles/).
#
#  [2026-11-13] - v5.1 (Rama Claude)
#    AUTOMATIZACIÓN (menú 7) completamente rehecho
#      * Panel de estado dinámico bajo el título (run_menu soporta MENU_HOOK).
#      * Autodescubre inventarios, playbooks y proyectos *.tf bajo
#        PROM_AUTOMATION_DIR (default $HOME), sin entrar a .git/.terraform/etc.
#      * Ansible: ping con resumen OK/fallos, facts de distro, ad-hoc guiado,
#        --limit, flujo sintaxis > lint > --check > run (avisa si no hubo
#        check), lista los hosts afectados antes de ejecutar, galaxy, vault.
#      * Terraform y OpenTofu (autodetecta 'tofu'): init/validate/fmt, plan
#        con -out, drift (-detailed-exitcode), APPLY solo desde plan guardado
#        con confirmación escribiendo el nombre del proyecto, DESTROY con
#        confirmación reforzada, state, outputs, workspaces, var-file.
#      * Avisa si el provider necesita Docker/libvirt y el servicio no corre.
#
#  [2026-11-12] - v5.0 (Rama Claude)
#    ARQUITECTURA
#      * Menús dirigidos por datos (run_menu): una función por acción, sin
#        'case' anidados de 20 niveles. Agregar una opción = 1 línea.
#      * Helpers de caja (box_*) y de formato (kv/section): se eliminan ~8
#        bloques copiados de fichas técnicas.
#      * Modo no interactivo: health | metrics | version | help.
#    SEGURIDAD
#      * Contraseñas ya NO viajan por la línea de comandos (visibles en ps):
#        SQLCMDPASSWORD / MYSQL_PWD / PGPASSWORD por entorno.
#      * Se elimina 'eval': gestores de paquetes como arrays.
#      * Validación de entradas (host, puerto, servicio, contenedor, nº).
#      * Confirmación en acciones destructivas (prune, stop de ssh/red, etc.).
#      * Aviso de uso autorizado antes de Nmap. Log con permisos 600.
#    BUGS CORREGIDOS
#      * El log vivía dentro del repo y 'git add .' lo subía: ahora en
#        ~/.local/state/prometherion/ con rotación a 1 MB.
#      * 'cd' al repo cambiaba el directorio de trabajo y bloqueaba la 'q'
#        del menú Git si el repo no existía: ahora 'git -C'.
#      * Ficha de archivo: columnas CARACTERES y BYTES estaban invertidas
#        (wc imprime siempre líneas, palabras, caracteres, bytes).
#      * Test de puerto sin nc: '/dev/tcp' no existe en zsh (siempre
#        reportaba "cerrado"); ahora usa bash/timeout.
#      * sqlcmd (mssql-tools18) exige -C con certificado autofirmado: era
#        una causa probable de "no se pudo conectar" aun con clave correcta.
#      * Health Check llamaba sqlcmd sin credenciales (colgaba el panel).
#      * 'ps aux | NR>=1' mostraba la cabecera como un proceso más.
#      * 'dig ANY' suele ser rechazado (RFC 8482): ahora A/AAAA/MX/NS/TXT.
#      * 'df' sin -P podía partir líneas con dispositivos de nombre largo.
#      * Ctrl+C en 'tail -f' / 'docker logs -f' / 'top' ahora vuelve al menú.
#      * LC_NUMERIC=C para que awk/printf no fallen con locale es_CL.
#      * 'hostname' no existe en Arch mínimo: se usa $HOST de zsh.
#    PORTABILIDAD
#      * Nombres de paquete por distro (dig, nc, mysql, psql, docker...).
#      * IP/gateway sin 'grep -P'; estado de actualizaciones por gestor
#        (apt, dnf/yum, pacman, zypper, apk).
#    FUNCIONES NUEVAS
#      * Health Check: unidades fallidas, errores del boot, reinicio
#        pendiente, alertas de disco (>=85%), carga vs núcleos, puertos.
#      * Timers systemd junto a cron; dry-run en rsync; CN y días restantes
#        en el certificado SSL; Mbps en el test de velocidad.
# ==============================================================================

# --- Opciones de zsh ----------------------------------------------------------
setopt TYPESET_SILENT NO_BEEP
export LC_NUMERIC=C

# --- Rutas y variables globales ------------------------------------------------
VERSION="5.2"
SCRIPT_NAME="${0:t}"
SCRIPT_DIR="${0:A:h}"
REPO_DIR="${PROM_REPO_DIR:-$HOME/.local/bin/scripts}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/prometherion"
LOG_FILE="$STATE_DIR/sysadmin.log"
LOG_MAX_BYTES=1048576
BOX_W=60                              # ancho interior de las cajas
BOX_LBL=16                            # ancho de la etiqueta
BOX_VW=$(( BOX_W - BOX_LBL - 4 ))     # ancho del valor
NMAP_ACK=0
DB_FOUND=0
CHOSEN_LOG=""

# --- Colores (solo con terminal y sin NO_COLOR) ------------------------------
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

# Validadores (evitan inyección de opciones y caracteres raros)
valid_num()   { [[ -n "$1" && "$1" == <-> ]]; }
valid_host()  { local re='^[A-Za-z0-9._:/,%-]+$'; [[ -n "$1" && "$1" != -* && "$1" =~ $re ]]; }
valid_ident() { local re='^[A-Za-z0-9._@:-]+$';   [[ -n "$1" && "$1" != -* && "$1" =~ $re ]]; }

# Entrada de texto (se mantiene el arreglo de backspace de la v4.x)
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

# Contraseña sin eco (read -s: no hay que tocar stty a mano)
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

# Ejecuta un comando largo (tail -f, top...) de modo que Ctrl+C lo corte a él
# y no al dashboard completo.
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

# --- Gestor de paquetes (arrays: sin eval) ------------------------------------
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

# Nombre del paquete según distro. Vacío = no está en repos oficiales.
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
        sqlcmd)    msg_info "Instala mssql-tools18 desde el repo de Microsoft:"
                   msg_info "https://learn.microsoft.com/sql/linux/sql-server-linux-setup-tools" ;;
        terraform) msg_info "Terraform no viene en los repos base: https://developer.hashicorp.com/terraform/install (o OpenTofu: https://opentofu.org/docs/intro/install/)" ;;
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
    [[ "$bin" == docker ]] && install_hint docker
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

# --- Motor de menús dirigido por datos ----------------------------------------
# Cada ítem:  "Etiqueta|funcion"            -> ejecuta y pausa
#             "Etiqueta|funcion|nopause"    -> submenús (no pausa)
#             "#Título de sección"          -> encabezado
run_menu() {
    local title="$1"; shift
    local -a items=("$@") parts
    local -A map
    local choice it n fn flag hook="${MENU_HOOK:-}" quit_label="Volver al menú anterior"
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
        [[ -n "$hook" ]] && "$hook"

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
    # banner.sh opcional junto al script (SCRIPT_DIR se calcula al inicio: dentro
    # de una función $0 es el nombre de la función y no sirve para esto)
    if [[ -x "$SCRIPT_DIR/banner.sh" ]] && "$SCRIPT_DIR/banner.sh"; then
        return 0
    fi
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
}

# ==============================================================================
#  DATOS DEL SISTEMA (compartidos por Health Check y metrics)
# ==============================================================================
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

# ==============================================================================
#  MÉTRICAS (formato Prometheus, para node_exporter --collector.textfile)
#    ./prom_claude.sh metrics > /var/lib/node_exporter/textfile/prom_claude.prom
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
#  2) HERRAMIENTAS NATIVAS
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

    # wc imprime SIEMPRE: líneas, palabras, caracteres, bytes (se piden por separado)
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
#  3) MONITOREO AVANZADO
# ==============================================================================
mon_btop() { need btop && run_interruptible btop; }
mon_htop() { need htop && run_interruptible htop; }

menu_monitor() {
    run_menu "MONITOREO AVANZADO DE RECURSOS" \
        "btop (monitor moderno)|mon_btop" \
        "htop (monitor por procesos)|mon_htop"
}

# ==============================================================================
#  4) DOCKER
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
#  5) MANTENIMIENTO Y GIT
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
    msg_info "Descargando cambios (git pull --ff-only)..."
    if git -C "$REPO_DIR" pull --ff-only; then log_action "Git: pull (ff-only)"; return 0; fi

    local counts ahead behind
    counts=$(git -C "$REPO_DIR" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null)
    ahead="${counts%%[[:space:]]*}"; behind="${counts##*[[:space:]]}"
    if [[ "$ahead" == <-> && "$behind" == <-> ]] && (( ahead > 0 && behind > 0 )); then
        msg_warn "Las ramas divergieron: $ahead commit(s) locales y $behind remoto(s)."
        local choice
        print " 1) Merge  (git pull --no-rebase --no-edit)"
        print " 2) Rebase (git pull --rebase)"
        print " 3) Cancelar y revisar a mano"
        prompt_input "Elige [1-3]: " choice
        case "$choice" in
            1) git -C "$REPO_DIR" pull --no-rebase --no-edit ;;
            2) git -C "$REPO_DIR" pull --rebase ;;
            *) msg_info "Cancelado."; return 0 ;;
        esac
        if (( $? != 0 )); then msg_err "Hay conflictos: resuélvelos en $REPO_DIR (git status) o aborta con git merge/rebase --abort."; fi
        log_action "Git: pull con ramas divergidas (opción $choice)"
    else
        msg_err "El pull falló por otra causa (red, credenciales o cambios locales sin commitear). Revisa el mensaje anterior."
    fi
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
#  6) UTILIDADES LOCALES Y CONSULTAS
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
#  7) AUTOMATIZACIÓN: ANSIBLE Y TERRAFORM / OPENTOFU
#     Descubre proyectos bajo AUTO_BASE (default $HOME; cámbialo con
#     PROM_AUTOMATION_DIR o desde el menú) y guía los flujos con guardarraíles.
# ==============================================================================
AUTO_BASE="${PROM_AUTOMATION_DIR:-$HOME}"
AUTO_PRUNE=( '(' -name .git -o -name .terraform -o -name .ansible -o -name ansible_collections
             -o -name node_modules -o -name .cache -o -name venv -o -name .venv
             -o -name site-packages -o -name snap -o -name .local ')' -prune -o )
PICKED=""
ANS_VER=""; ANS_CFG=""; ANS_INV=""; ANS_INV_INFO=""; ANS_PLAY=""; ANS_LIMIT=""; ANS_CHECKED=""
typeset -a ANS_ARGS
TF_BIN=""; TF_VER=""; TF_DIR=""; TF_VARFILE=""; TF_PLAN="prom.tfplan"
typeset -a TF_ARGS

# find acotado: auto_find <profundidad> <tests de find...>
auto_find() {
    timeout 20 find "$AUTO_BASE" -maxdepth "$1" "${AUTO_PRUNE[@]}" "${@:2}" -print 2>/dev/null
}

# Muestra una lista numerada y deja la elección en $PICKED
pick_from_list() {
    PICKED=""
    local title="$1"; shift
    local -a items=("$@")
    if (( ${#items} == 0 )); then msg_warn "No se encontró nada."; return 1; fi
    msg_info "$title"
    local i=1 it num
    for it in "${items[@]}"; do printf " %3d) %s\n" "$i" "$it"; i=$(( i + 1 )); done
    prompt_input "Número (Enter = cancelar): " num
    [[ -z "$num" ]] && return 1
    if [[ "$num" == <-> ]] && (( num >= 1 && num <= ${#items} )); then
        PICKED="${items[$num]}"; return 0
    fi
    msg_err "Selección no válida."; return 1
}

auto_set_base() {
    local d
    prompt_input "Carpeta base de búsqueda [actual: $AUTO_BASE]: " d
    [[ -z "$d" ]] && return 0
    if [[ ! -d "$d" ]]; then msg_err "No existe la carpeta '$d'."; return 0; fi
    AUTO_BASE="${d:A}"
    msg_ok "Carpeta base: $AUTO_BASE"
    log_action "Automatización: base = $AUTO_BASE"
}

# ------------------------------------------------------------------------------
#  Descubrimiento
# ------------------------------------------------------------------------------
ans_find_playbooks() {
    local f
    auto_find 5 -type f '(' -name '*.yml' -o -name '*.yaml' ')' | while IFS= read -r f; do
        [[ "$f" == */roles/* || "$f" == */group_vars/* || "$f" == */host_vars/* || "$f" == */molecule/* ]] && continue
        grep -qE '^[[:space:]]*-?[[:space:]]*hosts:' "$f" 2>/dev/null || continue
        grep -qE '^[[:space:]]*-?[[:space:]]*(tasks|roles|pre_tasks|post_tasks|import_playbook):' "$f" 2>/dev/null \
            && print -r -- "$f"
    done | sort
}

ans_find_inventories() {
    {
        auto_find 5 -type f '(' -iname 'inventory*' -o -name hosts -o -name 'hosts.ini' -o -name 'hosts.yml' -o -name 'hosts.yaml' ')' \
            | grep -vE '\.(md|txt|sh|py|j2)$'
        [[ -f /etc/ansible/hosts ]] && print -r -- /etc/ansible/hosts
    } | sort -u
}

tf_find_dirs() {
    auto_find 5 -type f -name '*.tf' | grep -v '/modules/' | sed 's#/[^/]*$##' | sort -u
}

auto_overview() {
    section "ENTORNO DE AUTOMATIZACIÓN"
    kv "Carpeta base" "$AUTO_BASE"
    local v
    if command -v ansible &>/dev/null; then v=$(ansible --version 2>/dev/null | head -n1); else v="no instalado"; fi
    kv "Ansible" "$v"
    command -v ansible-lint &>/dev/null && kv "ansible-lint" "instalado" || kv "ansible-lint" "no instalado"
    if command -v terraform &>/dev/null; then v=$(terraform version 2>/dev/null | head -n1); else v="no instalado"; fi
    kv "Terraform" "$v"
    if command -v tofu &>/dev/null; then v=$(tofu version 2>/dev/null | head -n1); else v="no instalado"; fi
    kv "OpenTofu" "$v"
    msg_info "Buscando proyectos (hasta 5 niveles bajo la base)..."
    kv "Playbooks" "$(ans_find_playbooks | wc -l | tr -d ' ') encontrados"
    kv "Inventarios" "$(ans_find_inventories | wc -l | tr -d ' ') encontrados"
    kv "Proyectos TF" "$(tf_find_dirs | wc -l | tr -d ' ') carpetas con *.tf"
    local nk rc
    nk=$(ssh-add -l 2>/dev/null); rc=$?
    case $rc in
        0) kv "ssh-agent" "${C_GRN}[OK]${C_RST} $(print -r -- "$nk" | wc -l | tr -d ' ') clave(s) cargada(s)" ;;
        1) kv "ssh-agent" "${C_YEL}[!]${C_RST} activo pero sin claves (ssh-add)" ;;
        *) kv "ssh-agent" "${C_YEL}[!]${C_RST} sin agente (Ansible usará claves por defecto o -K)" ;;
    esac
}

# ==============================================================================
#  ANSIBLE
# ==============================================================================
ans_inv_info() {
    local g hosts groups
    g=$(ansible-inventory -i "$ANS_INV" --graph 2>/dev/null)
    if [[ -z "$g" ]]; then ANS_INV_INFO="no se pudo leer: revisa la sintaxis"; return; fi
    hosts=$(print -r -- "$g" | grep -E '\|--[^@]' | sed 's/.*|--//' | sort -u | wc -l | tr -d ' ')
    groups=$(print -r -- "$g" | grep -c '@')
    ANS_INV_INFO="$hosts hosts / $groups grupos"
}

ans_panel() {
    print ""
    kv "Versión" "${ANS_VER:-N/D}"
    kv "Config" "${ANS_CFG:-ninguno}"
    kv "Inventario" "${ANS_INV:-(sin seleccionar)}${ANS_INV:+  [$ANS_INV_INFO]}"
    kv "Playbook" "${ANS_PLAY:-(sin seleccionar)}"
    kv "Límite" "${ANS_LIMIT:-(todos los hosts)}"
    local nk rc
    nk=$(ssh-add -l 2>/dev/null); rc=$?
    case $rc in
        0) kv "ssh-agent" "${C_GRN}[OK]${C_RST} $(print -r -- "$nk" | wc -l | tr -d ' ') clave(s) cargada(s)" ;;
        1) kv "ssh-agent" "${C_YEL}[!]${C_RST} activo pero sin claves" ;;
        *) kv "ssh-agent" "${C_YEL}[!]${C_RST} sin agente" ;;
    esac
}

# Ejecuta ansible-playbook desde la carpeta del playbook (ansible.cfg y roles/ del proyecto)
ans_pb() { ( cd "${ANS_PLAY:h}" && ansible-playbook "$@" ); }

ans_need_inv()  { [[ -n "$ANS_INV"  ]] && return 0; msg_warn "Primero selecciona un inventario."; return 1; }
ans_need_play() { [[ -n "$ANS_PLAY" ]] && return 0; msg_warn "Primero selecciona un playbook.";  return 1; }

# Argumentos comunes: inventario + límite
ans_base_opts() {
    ANS_ARGS=(-i "$ANS_INV")
    [[ -n "$ANS_LIMIT" ]] && ANS_ARGS+=(--limit "$ANS_LIMIT")
}

ans_ask_become() {
    if confirm "¿Elevar privilegios (become/sudo)?"; then
        ANS_ARGS+=(-b)
        confirm "¿Pedir contraseña de sudo (-K)?" && ANS_ARGS+=(-K)
    fi
}

ans_select_inv() {
    local -a found
    found=( ${(f)"$(ans_find_inventories)"} )
    found+=("[escribir ruta manualmente]")
    pick_from_list "Inventarios encontrados bajo $AUTO_BASE:" "${found[@]}" || return 0
    local choice="$PICKED"
    if [[ "$choice" == "[escribir ruta manualmente]" ]]; then
        prompt_input "Ruta del inventario (archivo o carpeta): " choice
    fi
    [[ -z "$choice" ]] && return 0
    if [[ ! -e "$choice" ]]; then msg_err "No existe: $choice"; return 0; fi
    ANS_INV="${choice:A}"; ANS_LIMIT=""
    ans_inv_info
    msg_ok "Inventario activo: $ANS_INV ($ANS_INV_INFO)"
    log_action "Ansible: inventario $ANS_INV"
}

ans_select_play() {
    local -a found
    found=( ${(f)"$(ans_find_playbooks)"} )
    found+=("[escribir ruta manualmente]")
    pick_from_list "Playbooks encontrados bajo $AUTO_BASE:" "${found[@]}" || return 0
    local choice="$PICKED"
    if [[ "$choice" == "[escribir ruta manualmente]" ]]; then
        prompt_input "Ruta del playbook: " choice
    fi
    [[ -z "$choice" ]] && return 0
    if [[ ! -f "$choice" ]]; then msg_err "No existe: $choice"; return 0; fi
    ANS_PLAY="${choice:A}"; ANS_CHECKED=""
    msg_ok "Playbook activo: $ANS_PLAY"
    log_action "Ansible: playbook $ANS_PLAY"
}

ans_set_limit() {
    local l re='^[A-Za-z0-9_.:,!&*@-]+$'
    prompt_input "Límite de hosts/grupos (ej: web,db o 'srv*'; Enter = quitar): " l
    if [[ -z "$l" ]]; then ANS_LIMIT=""; msg_ok "Límite eliminado."; return 0; fi
    if [[ "$l" =~ $re ]]; then ANS_LIMIT="$l"; msg_ok "Límite: $ANS_LIMIT"; else msg_err "Patrón no válido."; fi
}

ans_graph() {
    ans_need_inv || return 0
    ansible-inventory -i "$ANS_INV" --graph
}

ans_list_inv() {
    ans_need_inv || return 0
    ansible-inventory -i "$ANS_INV" --list | head -n 200
    msg_info "(se muestran las primeras 200 líneas)"
}

ans_ping() {
    ans_need_inv || return 0
    ans_base_opts
    msg_info "ansible all -m ping (timeout 10 s)..."
    local out ok bad
    out=$(ansible all "${ANS_ARGS[@]}" -m ping -T 10 2>&1)
    print -r -- "$out"
    ok=$(print -r -- "$out" | grep -c 'SUCCESS')
    bad=$(print -r -- "$out" | grep -cE 'UNREACHABLE|FAILED')
    print ""
    print -r -- " Resumen: ${C_GRN}$ok OK${C_RST} / ${C_RED}$bad con problemas${C_RST}"
    log_action "Ansible: ping ($ok ok, $bad fallos)"
}

ans_adhoc() {
    ans_need_inv || return 0
    local choice cmd svc
    print " 1) uptime"
    print " 2) df -hP (discos)"
    print " 3) free -h (memoria)"
    print " 4) Estado de un servicio (systemctl is-active)"
    print " 5) Comando personalizado"
    prompt_input "Elige [1-5]: " choice
    case "$choice" in
        1) cmd="uptime" ;;
        2) cmd="df -hP" ;;
        3) cmd="free -h" ;;
        4) prompt_input "Nombre del servicio: " svc
           valid_ident "$svc" || { msg_err "Nombre no válido."; return 0; }
           cmd="systemctl is-active $svc" ;;
        5) prompt_input "Comando (módulo 'command', sin pipes ni redirecciones): " cmd
           [[ -z "$cmd" ]] && return 0
           confirm "¿Ejecutar '$cmd' en todos los hosts del alcance?" || return 0 ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    ans_base_opts
    ans_ask_become
    ansible all "${ANS_ARGS[@]}" -m command -a "$cmd"
    log_action "Ansible: ad-hoc '$cmd'"
}

ans_facts() {
    ans_need_inv || return 0
    ans_base_opts
    msg_info "Distribución y versión de cada host:"
    ansible all "${ANS_ARGS[@]}" -m setup -a 'filter=ansible_distribution*' -T 10 2>&1 \
        | grep -E 'SUCCESS|UNREACHABLE|FAILED|"ansible_distribution(_version)?"'
    log_action "Ansible: facts de distribución"
}

# Tags opcionales para playbooks
ans_pb_opts() {
    ans_base_opts
    local tags re='^[A-Za-z0-9_,.-]+$'
    prompt_input "Tags (separados por coma, Enter = todos): " tags
    if [[ -n "$tags" ]]; then
        [[ "$tags" =~ $re ]] && ANS_ARGS+=(--tags "$tags") || { msg_err "Tags no válidos."; return 1; }
    fi
    return 0
}

ans_syntax() {
    ans_need_play || return 0
    ans_base_opts
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY" --syntax-check \
        && msg_ok "Sintaxis correcta." || msg_err "Se encontraron errores de sintaxis."
    log_action "Ansible: syntax-check $ANS_PLAY"
}

ans_lint() {
    ans_need_play || return 0
    if ! command -v ansible-lint &>/dev/null; then
        msg_warn "ansible-lint no está instalado."
        need ansible-lint || { msg_info "Alternativa: pipx install ansible-lint"; return 0; }
    fi
    ansible-lint "$ANS_PLAY"
    log_action "Ansible: lint $ANS_PLAY"
}

ans_tasks() {
    ans_need_play || return 0
    ans_base_opts
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY" --list-tasks --list-tags
}

ans_check() {
    ans_need_inv || return 0
    ans_need_play || return 0
    ans_pb_opts || return 0
    ans_ask_become
    msg_info "Dry-run (--check --diff): no se aplican cambios."
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY" --check --diff
    ANS_CHECKED="$ANS_PLAY"
    log_action "Ansible: check $ANS_PLAY"
}

ans_run() {
    ans_need_inv || return 0
    ans_need_play || return 0
    ans_pb_opts || return 0
    ans_ask_become
    msg_info "Hosts que se verán afectados:"
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY" --list-hosts
    if [[ "$ANS_CHECKED" != "$ANS_PLAY" ]]; then
        msg_warn "No has ejecutado --check con este playbook en esta sesión."
    fi
    confirm "¿EJECUTAR el playbook de verdad?" || { msg_info "Cancelado."; return 0; }
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY"
    log_action "Ansible: RUN $ANS_PLAY (rc=$?)"
}

ans_galaxy() {
    local req
    [[ -n "$ANS_PLAY" && -f "${ANS_PLAY:h}/requirements.yml" ]] && req="${ANS_PLAY:h}/requirements.yml"
    if [[ -n "$req" ]] && confirm "Se encontró $req. ¿Instalar dependencias?"; then
        ansible-galaxy install -r "$req"
        log_action "Ansible: galaxy install $req"
    fi
    msg_info "Collections instaladas:"
    ansible-galaxy collection list 2>/dev/null | head -n 30
    msg_info "Roles instalados:"
    ansible-galaxy role list 2>/dev/null | head -n 30
}

ans_vault() {
    local f choice
    prompt_input "Archivo (vault): " f
    [[ -f "$f" ]] || { msg_err "El archivo no existe."; return 0; }
    print " 1) Ver (view)   2) Editar (edit)   3) Cifrar (encrypt)"
    prompt_input "Elige [1-3]: " choice
    case "$choice" in
        1) ansible-vault view "$f" ;;
        2) ansible-vault edit "$f" ;;
        3) ansible-vault encrypt "$f" ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    log_action "Ansible: vault ($choice) en $f"
}

ans_config() {
    msg_info "Configuración modificada respecto a los valores por defecto:"
    ansible-config dump --only-changed
}

menu_ansible() {
    if ! need ansible; then pause_screen; return 0; fi
    ANS_VER=$(ansible --version 2>/dev/null | head -n1)
    ANS_CFG=$(ansible --version 2>/dev/null | awk -F' = ' '/config file/{print $2; exit}')
    MENU_HOOK=ans_panel
    run_menu "ANSIBLE - CENTRO DE CONTROL" \
        "#PROYECTO ACTIVO" \
        "Seleccionar inventario (autodetección)|ans_select_inv" \
        "Seleccionar playbook (autodetección)|ans_select_play" \
        "Definir límite de hosts (--limit)|ans_set_limit" \
        "#DIAGNÓSTICO DE HOSTS" \
        "Ver inventario como árbol (--graph)|ans_graph" \
        "Ver inventario completo (--list)|ans_list_inv" \
        "Ping a todos los hosts (con resumen OK/fallos)|ans_ping" \
        "Distro y versión de cada host (facts)|ans_facts" \
        "Comando ad-hoc (uptime, df, free, servicio...)|ans_adhoc" \
        "#PLAYBOOK (flujo seguro: sintaxis > lint > check > run)" \
        "Validar sintaxis|ans_syntax" \
        "Lint (ansible-lint)|ans_lint" \
        "Listar tareas y tags|ans_tasks" \
        "Dry-run (--check --diff)|ans_check" \
        "EJECUTAR playbook (lista hosts y pide confirmación)|ans_run" \
        "#MANTENIMIENTO" \
        "Galaxy: dependencias, collections y roles|ans_galaxy" \
        "Vault: ver / editar / cifrar|ans_vault" \
        "Configuración activa (ansible-config)|ans_config"
    MENU_HOOK=""
}

# ==============================================================================
#  TERRAFORM / OPENTOFU
# ==============================================================================
tfx() { "$TF_BIN" -chdir="$TF_DIR" "$@"; }

tf_need_dir() { [[ -n "$TF_DIR" && -d "$TF_DIR" ]] && return 0; msg_warn "Primero selecciona un proyecto."; return 1; }

tf_need_init() {
    [[ -d "$TF_DIR/.terraform" ]] && return 0
    msg_warn "El proyecto no está inicializado."
    confirm "¿Ejecutar '$TF_BIN init' ahora?" || return 1
    tfx init
}

tf_var_args() {
    TF_ARGS=()
    [[ -n "$TF_VARFILE" ]] && TF_ARGS+=(-var-file="$TF_VARFILE")
}

tf_panel() {
    print ""
    kv "Binario" "${TF_VER:-N/D}"
    kv "Proyecto" "${TF_DIR:-(sin seleccionar)}"
    [[ -n "$TF_DIR" && -d "$TF_DIR" ]] || return 0

    local -a tfs=("$TF_DIR"/*.tf(N))
    kv "Archivos .tf" "${#tfs}"
    if [[ -d "$TF_DIR/.terraform" ]]; then
        kv "Init" "${C_GRN}[OK]${C_RST} inicializado"
        local ws; ws=$(timeout 5 "$TF_BIN" -chdir="$TF_DIR" workspace show 2>/dev/null)
        kv "Workspace" "${ws:-N/D}"
        local sl rc
        sl=$(TF_INPUT=0 timeout 5 "$TF_BIN" -chdir="$TF_DIR" state list 2>/dev/null < /dev/null); rc=$?
        if (( rc == 0 )); then
            if [[ -z "$sl" ]]; then kv "Estado" "vacío (nada desplegado)"
            else kv "Estado" "$(print -r -- "$sl" | wc -l | tr -d ' ') recursos gestionados"; fi
        else
            kv "Estado" "no consultable ahora (¿backend remoto sin credenciales?)"
        fi
    else
        kv "Init" "${C_YEL}[!]${C_RST} pendiente (ejecuta init)"
    fi

    local prov=""
    if [[ -f "$TF_DIR/.terraform.lock.hcl" ]]; then
        prov=$(grep -E '^provider "' "$TF_DIR/.terraform.lock.hcl" | sed -E 's#^provider "[^/]*/##; s#".*##' | tr '\n' ' ')
        kv "Providers" "${prov:-ninguno}"
    fi
    # Servicios locales de los que dependen ciertos providers
    if [[ "$prov" == *docker* ]]; then
        if timeout 3 docker info &>/dev/null; then kv "Docker" "${C_GRN}[OK]${C_RST} daemon activo"
        else kv "Docker" "${C_YEL}[!]${C_RST} daemon inactivo o sin permisos (provider docker)"; fi
    fi
    if [[ "$prov" == *libvirt* ]]; then
        if systemctl is-active --quiet libvirtd 2>/dev/null || systemctl is-active --quiet virtqemud 2>/dev/null; then
            kv "libvirt" "${C_GRN}[OK]${C_RST} servicio activo"
        else
            kv "libvirt" "${C_YEL}[!]${C_RST} servicio inactivo (provider libvirt)"
        fi
    fi
    if [[ -f "$TF_DIR/$TF_PLAN" ]]; then
        kv "Plan guardado" "${C_YEL}sí${C_RST} ($(stat -c %y "$TF_DIR/$TF_PLAN" 2>/dev/null | cut -c1-16)) listo para apply"
    else
        kv "Plan guardado" "no"
    fi
    [[ -n "$TF_VARFILE" ]] && kv "Var-file" "${TF_VARFILE:t}"
    return 0
}

tf_select_dir() {
    local -a found
    found=( ${(f)"$(tf_find_dirs)"} )
    found+=("[escribir ruta manualmente]")
    pick_from_list "Proyectos Terraform bajo $AUTO_BASE (se omiten carpetas modules/):" "${found[@]}" || return 0
    local choice="$PICKED"
    if [[ "$choice" == "[escribir ruta manualmente]" ]]; then
        prompt_input "Ruta de la carpeta del proyecto: " choice
    fi
    [[ -z "$choice" ]] && return 0
    if [[ ! -d "$choice" ]]; then msg_err "No existe la carpeta: $choice"; return 0; fi
    TF_DIR="${choice:A}"; TF_VARFILE=""
    msg_ok "Proyecto activo: $TF_DIR"
    log_action "Terraform: proyecto $TF_DIR"
}

tf_select_varfile() {
    tf_need_dir || return 0
    local -a vf
    vf=( ${(f)"$(find "$TF_DIR" -maxdepth 1 -type f '(' -name '*.tfvars' -o -name '*.tfvars.json' ')' 2>/dev/null | sort)"} )
    vf+=("(ninguno)")
    pick_from_list "Archivos de variables en $TF_DIR:" "${vf[@]}" || return 0
    if [[ "$PICKED" == "(ninguno)" ]]; then TF_VARFILE=""; msg_ok "Sin var-file."
    else TF_VARFILE="$PICKED"; msg_ok "Var-file: $TF_VARFILE"; fi
}

tf_init() {
    tf_need_dir || return 0
    local -a extra=()
    confirm "¿Incluir -upgrade (actualiza providers)?" && extra=(-upgrade)
    tfx init "${extra[@]}"
    log_action "Terraform: init en $TF_DIR"
}

tf_validate() {
    tf_need_dir || return 0
    tf_need_init || return 0
    tfx validate
}

tf_fmt() {
    tf_need_dir || return 0
    msg_info "Archivos que no cumplen el formato canónico:"
    tfx fmt -check -diff -recursive
    local rc=$?
    if (( rc == 3 )); then
        confirm "¿Aplicar 'fmt -recursive' para corregirlos?" && tfx fmt -recursive
    elif (( rc == 0 )); then
        msg_ok "Todo el código ya está formateado."
    fi
}

tf_plan() {
    tf_need_dir || return 0
    tf_need_init || return 0
    tf_var_args
    msg_info "$TF_BIN plan -out=$TF_PLAN"
    tfx plan -out="$TF_PLAN" "${TF_ARGS[@]}"
    local rc=$?
    (( rc == 0 )) && chmod 600 "$TF_DIR/$TF_PLAN" 2>/dev/null
    (( rc == 0 )) && msg_ok "Plan guardado. Revísalo y luego usa 'apply'."
    log_action "Terraform: plan en $TF_DIR (rc=$rc)"
}

tf_show_plan() {
    tf_need_dir || return 0
    [[ -f "$TF_DIR/$TF_PLAN" ]] || { msg_warn "No hay plan guardado."; return 0; }
    tfx show -no-color "$TF_PLAN" | ${PAGER:-less}
}

tf_drift() {
    tf_need_dir || return 0
    tf_need_init || return 0
    tf_var_args
    msg_info "Buscando diferencias entre el código y la infraestructura real..."
    local out rc
    out=$(tfx plan -detailed-exitcode -input=false -lock=false -no-color "${TF_ARGS[@]}" 2>&1); rc=$?
    print -r -- "$out" | tail -n 30
    print ""
    case $rc in
        0) msg_ok "Sin cambios: la infraestructura coincide con el código." ;;
        2) msg_warn "Hay diferencias (cambios pendientes o drift)." ;;
        *) msg_err "El plan falló (revisa credenciales/backend/variables)." ;;
    esac
    log_action "Terraform: drift en $TF_DIR (rc=$rc)"
}

tf_apply() {
    tf_need_dir || return 0
    if [[ ! -f "$TF_DIR/$TF_PLAN" ]]; then
        msg_warn "No hay plan guardado. 'apply' solo se permite desde un plan revisado: ejecuta 'plan' primero."
        return 0
    fi
    msg_info "Plan guardado el $(stat -c %y "$TF_DIR/$TF_PLAN" 2>/dev/null | cut -c1-16). Resumen:"
    tfx show -no-color "$TF_PLAN" | tail -n 25
    local ws ans
    ws=$(tfx workspace show 2>/dev/null)
    print ""
    msg_warn "Se aplicarán cambios REALES (workspace '${ws:-default}')."
    prompt_input "Escribe el nombre del proyecto (${TF_DIR:t}) para confirmar: " ans
    [[ "$ans" == "${TF_DIR:t}" ]] || { msg_info "Cancelado."; return 0; }
    tfx apply "$TF_PLAN"
    local rc=$?
    (( rc == 0 )) && rm -f "$TF_DIR/$TF_PLAN"
    log_action "Terraform: APPLY en $TF_DIR (rc=$rc)"
}

tf_destroy() {
    tf_need_dir || return 0
    tf_need_init || return 0
    tf_var_args
    msg_info "Generando plan de destrucción (aún no se destruye nada)..."
    tfx plan -destroy -out="$TF_PLAN" "${TF_ARGS[@]}" || return 0
    chmod 600 "$TF_DIR/$TF_PLAN" 2>/dev/null
    local ws ans
    ws=$(tfx workspace show 2>/dev/null)
    print ""
    msg_warn "PELIGRO: esto ELIMINARÁ la infraestructura del workspace '${ws:-default}'."
    prompt_input "Escribe exactamente 'DESTRUIR ${TF_DIR:t}' para continuar: " ans
    if [[ "$ans" != "DESTRUIR ${TF_DIR:t}" ]]; then
        rm -f "$TF_DIR/$TF_PLAN"; msg_info "Cancelado. Plan de destrucción descartado."; return 0
    fi
    tfx apply "$TF_PLAN"
    local rc=$?
    rm -f "$TF_DIR/$TF_PLAN"
    log_action "Terraform: DESTROY en $TF_DIR (rc=$rc)"
}

tf_state_list() { tf_need_dir || return 0; tf_need_init || return 0; tfx state list; }

tf_state_show() {
    tf_need_dir || return 0
    tf_need_init || return 0
    local -a res
    res=( ${(f)"$(tfx state list 2>/dev/null)"} )
    pick_from_list "Recursos en el estado:" "${res[@]}" || return 0
    tfx state show "$PICKED"
}

tf_output()    { tf_need_dir || return 0; tf_need_init || return 0; tfx output; }
tf_providers() { tf_need_dir || return 0; tf_need_init || return 0; tfx providers; }

tf_workspace() {
    tf_need_dir || return 0
    tf_need_init || return 0
    msg_info "Workspaces:"
    tfx workspace list
    local act name
    print " 1) Cambiar a un workspace existente   2) Crear uno nuevo"
    prompt_input "Elige [1-2, Enter = nada]: " act
    [[ -z "$act" ]] && return 0
    prompt_input "Nombre del workspace: " name
    valid_ident "$name" || { msg_err "Nombre no válido."; return 0; }
    case "$act" in
        1) tfx workspace select "$name" ;;
        2) tfx workspace new "$name" ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    log_action "Terraform: workspace $act $name en $TF_DIR"
}

menu_terraform() {
    TF_BIN=""
    if   command -v terraform &>/dev/null; then TF_BIN=terraform
    elif command -v tofu      &>/dev/null; then TF_BIN=tofu
    else
        need terraform
        msg_info "Alternativa libre y compatible: OpenTofu (https://opentofu.org/docs/intro/install/)"
        pause_screen; return 0
    fi
    TF_VER=$("$TF_BIN" version 2>/dev/null | head -n1)
    MENU_HOOK=tf_panel
    run_menu "TERRAFORM / OPENTOFU - CENTRO DE CONTROL" \
        "#PROYECTO ACTIVO" \
        "Seleccionar proyecto (autodetección de carpetas *.tf)|tf_select_dir" \
        "Seleccionar archivo de variables (var-file)|tf_select_varfile" \
        "#PREPARAR Y VALIDAR" \
        "init (opcional -upgrade)|tf_init" \
        "validate|tf_validate" \
        "fmt (revisar y corregir formato)|tf_fmt" \
        "#CAMBIOS (flujo seguro: plan > revisar > apply)" \
        "plan (guarda plan en $TF_PLAN)|tf_plan" \
        "Ver el plan guardado|tf_show_plan" \
        "Detectar drift (plan -detailed-exitcode)|tf_drift" \
        "APPLY del plan guardado (pide escribir el nombre del proyecto)|tf_apply" \
        "DESTROY (plan previo + confirmación reforzada)|tf_destroy" \
        "#ESTADO" \
        "Listar recursos (state list)|tf_state_list" \
        "Ver un recurso (state show)|tf_state_show" \
        "Outputs|tf_output" \
        "Providers|tf_providers" \
        "Workspaces: listar / cambiar / crear|tf_workspace"
    MENU_HOOK=""
}

auto_panel() { print ""; kv "Carpeta base" "$AUTO_BASE"; }

menu_automation() {
    MENU_HOOK=auto_panel
    run_menu "HERRAMIENTAS DE AUTOMATIZACIÓN" \
        "Ansible: inventarios, playbooks, ad-hoc, vault|menu_ansible|nopause" \
        "Terraform / OpenTofu: init, plan, apply seguro, drift|menu_terraform|nopause" \
        "Estado del entorno (versiones, proyectos detectados, ssh-agent)|auto_overview" \
        "Cambiar carpeta base de búsqueda|auto_set_base"
    MENU_HOOK=""
}

# ==============================================================================
#  8) CRON Y LOGS
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
#  9) BASES DE DATOS  (las claves viajan por variables de entorno, no por -p/-P)
# ==============================================================================
db_show() {   # db_show "<salida de versión>" "<salida de bases>"
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
    # mssql-tools18 cifra por defecto: con certificado autofirmado exige -C
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

# --- Ejecución de SQL (archivos y consultas) con guardarraíles ----------------
# Conexión en variables globales SQL_*; la clave se borra al salir de la sesión.
typeset -a SQL_CMD SQL_EXTRA
SQL_BIN=""; SQL_HOST=""; SQL_USER=""; SQL_PASS=""; SQL_DB=""; SQL_LABEL=""; SQL_TX=0

_sql_q_mssql() {
    local -a dbarg=(); [[ -n "$SQL_DB" ]] && dbarg=(-d "$SQL_DB")
    SQLCMDPASSWORD="$SQL_PASS" "$SQL_BIN" -S "$SQL_HOST" -U "$SQL_USER" "${SQL_EXTRA[@]}" "${dbarg[@]}" \
        -l 5 -b -W -s '|' -Q "SET NOCOUNT ON; $1" 2>&1
}
_sql_f_mssql() {
    local -a dbarg=(); [[ -n "$SQL_DB" ]] && dbarg=(-d "$SQL_DB")
    SQLCMDPASSWORD="$SQL_PASS" "$SQL_BIN" -S "$SQL_HOST" -U "$SQL_USER" "${SQL_EXTRA[@]}" "${dbarg[@]}" \
        -l 5 -b -i "$1" 2>&1
}
_sql_q_mysql() {
    local -a d=(); [[ -n "$SQL_DB" ]] && d=("$SQL_DB")
    MYSQL_PWD="$SQL_PASS" "${SQL_CMD[@]}" -t "${d[@]}" -e "$1" 2>&1
}
_sql_f_mysql() {   # redirección por stdin: sirve aunque el cliente corra vía sudo
    local -a d=(); [[ -n "$SQL_DB" ]] && d=("$SQL_DB")
    MYSQL_PWD="$SQL_PASS" "${SQL_CMD[@]}" "${d[@]}" < "$1" 2>&1
}
_sql_q_pg() {
    PGPASSWORD="$SQL_PASS" "${SQL_CMD[@]}" -v ON_ERROR_STOP=1 -c "$1" 2>&1
}
_sql_f_pg() {      # stdin: el usuario 'postgres' no puede leer archivos de tu /home
    local -a tx=(); (( SQL_TX )) && tx=(-1)
    PGPASSWORD="$SQL_PASS" "${SQL_CMD[@]}" -v ON_ERROR_STOP=1 "${tx[@]}" -f - < "$1" 2>&1
}

# Pide confirmación si el SQL modifica datos/estructura. Retorna 0 = continuar.
sql_guard() {
    local q="$1" typed
    local re_mod='(^|[^[:alnum:]_])(drop|delete|update|truncate|alter|insert|create|grant|revoke|merge|exec|execute|shutdown|xp_cmdshell)([^[:alnum:]_]|$)'
    local re_dml='(^|[^[:alnum:]_])(delete|update)([^[:alnum:]_]|$)'
    local re_whr='(^|[^[:alnum:]_])where([^[:alnum:]_]|$)'
    print -r -- "$q" | grep -qiE "$re_mod" || return 0

    msg_warn "Se detectaron sentencias que MODIFICAN datos o estructura."
    if print -r -- "$q" | grep -qiE "$re_dml" && ! print -r -- "$q" | grep -qiE "$re_whr"; then
        msg_warn "DELETE/UPDATE SIN cláusula WHERE: afectaría TODAS las filas."
        prompt_input "Escribe CONFIRMAR para continuar: " typed
        [[ "$typed" == CONFIRMAR ]]
        return $?
    fi
    confirm "¿Ejecutar de todos modos?"
}

# Menú de la sesión SQL:  sql_loop mssql|mysql|pg
sql_loop() {
    local eng="$1" mode f q n
    while true; do
        print ""
        print " 1) Ejecutar archivo .sql"
        print " 2) Ejecutar consulta rápida"
        print " q) Volver al menú de BBDD   [conectado a: $SQL_LABEL]"
        prompt_input "Selecciona modo [1-2 o q]: " mode || break
        case "$mode" in
            1)
                prompt_input "Ruta del archivo .sql: " f
                [[ -z "$f" ]] && continue
                [[ -f "$f" && -r "$f" ]] || { msg_err "El archivo no existe o no es legible."; continue; }
                n=$(wc -l < "$f" | tr -d ' ')
                sql_guard "$(cat -- "$f")" || { msg_info "Cancelado."; continue; }
                confirm "¿Ejecutar '${f:t}' ($n líneas) en $SQL_LABEL?" || { msg_info "Cancelado."; continue; }
                SQL_TX=0
                if [[ "$eng" == pg ]] && confirm "¿En una sola transacción (rollback si algo falla)?"; then SQL_TX=1; fi
                msg_info "Ejecutando '${f:t}'..."
                "_sql_f_$eng" "$f"
                log_action "BBDD($eng): archivo ${f:t} en $SQL_LABEL (rc=$?)"
                ;;
            2)
                prompt_input "Consulta SQL: " q
                [[ -z "$q" ]] && { msg_warn "Consulta vacía."; continue; }
                sql_guard "$q" || { msg_info "Cancelado."; continue; }
                "_sql_q_$eng" "$q"
                log_action "BBDD($eng): consulta rápida en $SQL_LABEL (rc=$?)"
                ;;
            q|Q|"") break ;;
            *) msg_warn "Modo no válido." ;;
        esac
    done
}

db_mssql_exec() {
    local bin host user pass dbn out rc
    if ! bin=$(find_sqlcmd); then msg_warn "'sqlcmd' no está instalado."; install_hint sqlcmd; return 0; fi
    SQL_EXTRA=()
    "$bin" '-?' 2>&1 | grep -qE 'Version (1[7-9]|[2-9][0-9])' && SQL_EXTRA=(-C)

    prompt_input "Servidor [Default: localhost]: " host;  host="${host:-localhost}"
    prompt_input "Usuario [Default: sa]: " user;          user="${user:-sa}"
    prompt_password "Contraseña: " pass
    prompt_input "Base de datos [Enter = la predeterminada del login]: " dbn
    [[ -z "$pass" ]] && { msg_err "SQL Server requiere contraseña."; return 0; }
    valid_host "$host" || { msg_err "Servidor no válido."; return 0; }
    [[ -n "$dbn" ]] && ! valid_ident "$dbn" && { msg_err "Nombre de base no válido."; return 0; }

    SQL_BIN="$bin"; SQL_HOST="$host"; SQL_USER="$user"; SQL_PASS="$pass"; SQL_DB="$dbn"
    SQL_LABEL="$host${dbn:+/$dbn}"
    out=$(_sql_q_mssql "SELECT 1 AS ok"); rc=$?
    if (( rc != 0 )) || [[ "$out" == *"Sqlcmd: Error"* || "$out" == *"Msg "* ]]; then
        msg_err "No se pudo conectar a SQL Server."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        log_action "BBDD(mssql): fallo de conexión en $SQL_LABEL"
        SQL_PASS=""; return 0
    fi
    msg_ok "Conectado a $SQL_LABEL"
    sql_loop mssql
    SQL_PASS=""
}

db_mysql_exec() {
    need mysql || return 0
    local user pass dbn out rc
    prompt_input "Usuario [Default: root]: " user; user="${user:-root}"
    prompt_password "Contraseña (vacía = auth por socket con sudo): " pass
    prompt_input "Base de datos [Enter = ninguna]: " dbn
    valid_ident "$user" || { msg_err "Usuario no válido."; return 0; }
    [[ -n "$dbn" ]] && ! valid_ident "$dbn" && { msg_err "Nombre de base no válido."; return 0; }

    SQL_CMD=(mysql -u "$user")
    [[ -z "$pass" ]] && SQL_CMD=("${SUDO[@]}" "${SQL_CMD[@]}")
    SQL_PASS="$pass"; SQL_DB="$dbn"; SQL_LABEL="mysql:$user${dbn:+/$dbn}"
    out=$(_sql_q_mysql "SELECT 1 AS ok"); rc=$?
    if (( rc != 0 )); then
        msg_err "No se pudo conectar a MySQL/MariaDB."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        log_action "BBDD(mysql): fallo de conexión ($SQL_LABEL)"
        SQL_PASS=""; return 0
    fi
    msg_ok "Conectado a $SQL_LABEL"
    sql_loop mysql
    SQL_PASS=""
}

db_pg_exec() {
    need psql || return 0
    local user dbname pass out rc
    prompt_input "Usuario [Default: postgres]: " user;        user="${user:-postgres}"
    prompt_input "Base de datos [Default: postgres]: " dbname; dbname="${dbname:-postgres}"
    prompt_password "Contraseña (vacía = auth local 'peer' como ese usuario): " pass
    valid_ident "$user" && valid_ident "$dbname" || { msg_err "Usuario o base no válidos."; return 0; }

    if [[ -n "$pass" ]]; then   SQL_CMD=(psql -h localhost -U "$user" -d "$dbname")
    elif (( EUID == 0 )); then  SQL_CMD=(runuser -u "$user" -- psql -d "$dbname")
    else                        SQL_CMD=(sudo -u "$user" psql -d "$dbname")
    fi
    SQL_PASS="$pass"; SQL_LABEL="pg:$user/$dbname"
    out=$(_sql_q_pg "SELECT 1 AS ok"); rc=$?
    if (( rc != 0 )); then
        msg_err "No se pudo conectar a PostgreSQL."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        log_action "BBDD(pg): fallo de conexión ($SQL_LABEL)"
        SQL_PASS=""; return 0
    fi
    msg_ok "Conectado a $SQL_LABEL"
    sql_loop pg
    SQL_PASS=""
}

menu_db() {
    run_menu "GESTIÓN DE BASES DE DATOS (BBDD)" \
        "Detectar motores instalados|db_detect" \
        "#SQL SERVER (MSSQL)" \
        "Listar BBDD|db_mssql" \
        "Ejecutar script .sql / consulta|db_mssql_exec|nopause" \
        "#MYSQL / MARIADB" \
        "Listar BBDD|db_mysql" \
        "Ejecutar script .sql / consulta|db_mysql_exec|nopause" \
        "#POSTGRESQL" \
        "Listar BBDD|db_pg" \
        "Ejecutar script .sql / consulta|db_pg_exec|nopause"
}

# ==============================================================================
#  10) NMAP
# ==============================================================================
nm_target() {   # nm_target VAR "mensaje"
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
#  11) DIAGNÓSTICO DE RED AVANZADO
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
        # zsh no tiene /dev/tcp: se delega en bash con timeout
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
$SCRIPT_NAME v$VERSION - Prometherion2112 Sysadmin Dashboard

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
