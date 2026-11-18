#!/usr/bin/env zsh

# ==============================================================================
#  PROMETHERION2112 - MODULAR EDITION
# ==============================================================================

setopt TYPESET_SILENT NO_BEEP
export LC_NUMERIC=C

VERSION="modular-1.3"
SCRIPT_NAME="${0:t}"
SCRIPT_DIR="${0:A:h}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/prometherion"
LOG_FILE="$STATE_DIR/sysadmin.log"

MENU_HOOK=""

# Colores
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RST=$'\e[0m'; C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_CYN=$'\e[36m'
else
    C_RST=""; C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""
fi

msg_info() { print -r -- "${C_CYN}[-]${C_RST} $*"; }
msg_ok()   { print -r -- "${C_GRN}[OK]${C_RST} $*"; }
msg_warn() { print -r -- "${C_YEL}[!]${C_RST} $*"; }
msg_err()  { print -r -- "${C_RED}[ERROR]${C_RST} $*"; }

# Funciones base
init_log() {
    mkdir -p "$STATE_DIR" 2>/dev/null && chmod 700 "$STATE_DIR" 2>/dev/null
    ( umask 077; touch "$LOG_FILE" 2>/dev/null )
}
log_action() { print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null; }

# --- Funciones de utilidad compartida ---
human_bytes() {
    awk -v b="${1:-0}" 'BEGIN{split("B KiB MiB GiB TiB",u," "); i=1; while(b>=1024 && i<5){b/=1024;i++} printf "%.1f %s", b, u[i]}'
}

have_systemd() { command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; }
proc_running() { command -v pgrep &>/dev/null && pgrep -x "$1" &>/dev/null; }

find_sqlcmd() {
    local c
    for c in "$(command -v sqlcmd 2>/dev/null)" /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
        [[ -n "$c" && -x "$c" ]] && { print -r -- "$c"; return 0; }
    done
    return 1
}

# --- Entradas de texto ---
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

pause_screen() {
    [[ -t 0 ]] || return 0
    print ""; read -r "?Presiona Enter para continuar..."
}

# --- Helpers de formato (Cajas) ---
BOX_W=60
BOX_LBL=16
BOX_VW=$(( BOX_W - BOX_LBL - 4 ))

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

run_interruptible() {
    local old_stty=$(stty -g 2>/dev/null)
    stty erase '^?' 2>/dev/null
    ( trap - INT; "$@" )
    local rc=$?
    [[ -n "$old_stty" ]] && stty "$old_stty" 2>/dev/null
    return $rc
}

# --- Funciones auxiliares ---
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

valid_num()   { [[ -n "$1" && "$1" == <-> ]]; }
valid_host()  { local re='^[A-Za-z0-9._:/,%-]+$'; [[ -n "$1" && "$1" != -* && "$1" =~ $re ]]; }
valid_ident() { local re='^[A-Za-z0-9._@:-]+$';   [[ -n "$1" && "$1" != -* && "$1" =~ $re ]]; }

confirm() {
    local ans
    read -r "ans?$1 (s/n): "
    [[ "$ans" == [sSyY] ]]
}

need() {
    local bin="$1" pkg="${2:-}"
    if command -v "$bin" &>/dev/null; then return 0; fi
    
    msg_warn "'$bin' no está instalado."
    if [[ "$PKG_MGR" == "unknown" ]]; then
        msg_warn "No se detectó un gestor de paquetes compatible."
        return 1
    fi
    if [[ -z "$pkg" ]]; then pkg="$bin"; fi
    
    prompt_input "¿Instalar '$pkg' con $PKG_MGR ahora? (s/n): " inst_ans
    if [[ "$inst_ans" != "s" && "$inst_ans" != "S" ]]; then return 1; fi
    
    msg_info "Instalando '$pkg' con $PKG_MGR..."
    eval "$PKG_INSTALL $pkg"
    log_action "Instalación: $pkg vía $PKG_MGR"
    
    if command -v "$bin" &>/dev/null; then
        msg_ok "'$bin' instalado correctamente."
        return 0
    else
        msg_err "La instalación de '$pkg' falló."
        return 1
    fi
}

# --- Gestor de paquetes ---
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MGR="apt"; PKG_INSTALL="sudo apt-get install -y"
    elif command -v dnf &>/dev/null; then
        PKG_MGR="dnf"; PKG_INSTALL="sudo dnf install -y"
    elif command -v pacman &>/dev/null; then
        PKG_MGR="pacman"; PKG_INSTALL="sudo pacman -S --noconfirm"
    else
        PKG_MGR="unknown"; PKG_INSTALL=""
    fi
}

# Motor de menús
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
            if [[ "$it" == "#"* ]]; then print ""; print -r -- "--- ${it#\#} ---"; continue; fi
            parts=("${(@s:|:)it}")
            n=$(( n + 1 ))
            printf " %2d) %s\n" "$n" "${parts[1]}"
            map[$n]="${parts[2]}|${parts[3]}"
        done
        print ""; print -r -- "  q) $quit_label"; print "=========================================================="

        prompt_input "Elige una opción [1-$n o q]: " choice || return 0
        case "$choice" in
            q|Q) return 0 ;;
            *)
                if [[ "$choice" == <-> && -n "${map[$choice]:-}" ]]; then
                    fn="${map[$choice]%%|*}"; flag="${map[$choice]#*|}"
                    print ""; "$fn"
                    [[ "$flag" != nopause ]] && pause_screen
                elif [[ -n "$choice" ]]; then msg_warn "Opción no válida."; sleep 1; fi
                ;;
        esac
    done
}

banner_main() {
    if [[ -x "$SCRIPT_DIR/banner.sh" ]] && "$SCRIPT_DIR/banner.sh"; then return 0; fi
    print "╔══════════════════════════════════════════════════════════════════╗"
    print "║                  P R O M E T H E R I O N  2 1 1 2                ║"
    print "║                 M O D U L A R   E D I T I O N                    ║"
    print "╚══════════════════════════════════════════════════════════════════╝"
}

# ==============================================================================
#  CARGA DE MÓDULOS
# ==============================================================================
source "$SCRIPT_DIR/modules/sysadmin.sh"
source "$SCRIPT_DIR/modules/network.sh"
source "$SCRIPT_DIR/modules/devops.sh"
source "$SCRIPT_DIR/modules/utils.sh"
source "$SCRIPT_DIR/modules/tools.sh"

# ==============================================================================
#  MENÚ PRINCIPAL
# ==============================================================================
menu_main() {
    run_menu __MAIN__ \
        "Sysadmin & Servidor (Health, Recursos, BBDD, Logs)|sysadmin_menu|nopause" \
        "Red & Conectividad (IP, DNS, SSL, Nmap)|network_menu|nopause" \
        "DevOps & Automatización (Git, Ansible, Terraform)|devops_menu|nopause" \
        "Utilidades Locales (Clima, QR, Claves)|utils_menu|nopause" \
        "Herramientas Locales (Scripts antiguos)|tools_menu|nopause"
}

init_log
detect_pkg_manager
menu_main
