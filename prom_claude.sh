#!/usr/bin/env zsh

# ==============================================================================
#  PROMETHERION2112 - SYSADMIN / DEVOPS DASHBOARD  (prom_claude v6.0 modular)
#  Repositorio: git@github.com:leocampos81/scripts.git
#  Autor: Leonardo Campos (https://github.com/leocampos81)
#  Refactor modular: Claude. Historial completo en CHANGELOG.md
# ==============================================================================
#  USO
#    ./prom_claude.sh              Menú interactivo
#    ./prom_claude.sh sysadmin     Entra directo al menú Sysadmin
#    ./prom_claude.sh devops       Entra directo al menú DevOps
#    ./prom_claude.sh secops       Entra directo al menú DevSecOps
#    ./prom_claude.sh console      Consola DevOps: comandos reales con contexto y guardarraíles
#    ./prom_claude.sh health       Health Check sin menú (SSH / cron)
#    ./prom_claude.sh health-csv   Health Check en CSV (stdout o archivo; --excel)
#    ./prom_claude.sh metrics      Métricas formato Prometheus (textfile collector)
#    ./prom_claude.sh selftest     Verifica módulos, menús y dependencias
#    ./prom_claude.sh version | help
#
#  ESTRUCTURA
#    prom_claude.sh   core: helpers, motor de menús, carga de módulos, CLI
#    modules/*.sh     un módulo por tema; se cargan con 'source' (deben ser zsh)
#
#  REGLAS PARA MÓDULOS
#    - No ejecutan nada al cargarse: solo definen funciones y variables.
#    - Un prefijo por módulo y un único menú público (menu_xxx).
#    - Entrada de texto SIEMPRE con prompt_input / prompt_password / confirm
#      (no 'read' directo: así el backspace funciona en cualquier terminal).
# ==============================================================================

# --- Opciones de zsh ----------------------------------------------------------
setopt TYPESET_SILENT NO_BEEP
export LC_NUMERIC=C

# ZLE (edición de línea). DEBE inicializarse aquí, a nivel superior: dentro de
# una función el backspace ^H no queda enlazado. Con ZLE, ^H y DEL (0x7f)
# funcionan sin depender de 'stty erase'.
# Ctrl+D: en una línea vacía significa "fin de entrada" (sale del menú/consola).
# Sin esto zsh lo interpreta como autocompletado ("¿ver las 1444 posibilidades?").
_PROM_EOF=0
_prom_eof_widget() { if [[ -z "$BUFFER" ]]; then _PROM_EOF=1; zle accept-line; else zle delete-char; fi }
if [[ -t 0 && -t 1 ]]; then
    if zmodload zsh/zle 2>/dev/null; then      # (no hace falta 'setopt zle' en scripts)
        bindkey -e 2>/dev/null
        zle -N _prom_eof_widget 2>/dev/null && bindkey '^D' _prom_eof_widget 2>/dev/null
    fi
fi

# --- Rutas y variables globales ------------------------------------------------
VERSION="6.1"
SCRIPT_NAME="${0:t}"
SCRIPT_DIR="${0:A:h}"          # a nivel superior (dentro de una función $0 es el nombre de la función)
SCRIPT_PATH="${0:A}"
MODULE_DIR="${PROM_MODULE_DIR:-$SCRIPT_DIR/modules}"
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
MENU_HOOK=""
PICKED=""
OS_NAME=""
PKG_MGR="unknown"
typeset -a LOADED_MODULES LOAD_ERRORS
MODULES=(banner sysadmin files network data git iac docker secops console devops utils)

# Carpeta base para descubrir proyectos (Ansible / Terraform / Compose)
AUTO_BASE="${PROM_AUTOMATION_DIR:-$HOME}"
AUTO_PRUNE=( '(' -name .git -o -name .terraform -o -name .ansible -o -name ansible_collections
             -o -name node_modules -o -name .cache -o -name venv -o -name .venv
             -o -name site-packages -o -name snap -o -name .local ')' -prune -o )

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


# --- Utilidades internas ------------------------------------------------------
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

# --- Entrada de texto ----------------------------------------------------------
# prompt_input "mensaje" VARIABLE   (VARIABLE debe ser local del llamador)
# Con terminal usa ZLE (vared): ^H y DEL borran igual y hay edición de línea.
# Sin terminal (pipe, cron) cae a 'read'.
prompt_input() {
    local prompt_msg="$1" var_name="$2" rc
    if [[ -t 0 && -t 1 ]] && zle -l &>/dev/null; then
        typeset -g -- "$var_name="          # vared necesita que la variable exista
        vared -p "$prompt_msg" "$var_name"
        rc=$?
        if (( _PROM_EOF )); then _PROM_EOF=0; typeset -g -- "$var_name="; return 1; fi   # Ctrl+D en vacío
    else
        print -rn -- "$prompt_msg"
        read -r "$var_name"
        rc=$?
    fi
    return $rc
}

# Contraseña sin eco. Lee tecla a tecla para soportar ^H y DEL (read -s común
# depende de 'stty erase' y podría colar un \b dentro de la clave).
prompt_password() {
    local prompt_msg="$1" var_name="$2" ch ch2 buf=""
    if [[ ! -t 0 ]]; then
        read -rs "${var_name}?${prompt_msg}"
        local rc=$?; print ""; return $rc
    fi
    print -rn -- "$prompt_msg"
    while IFS= read -rsk 1 ch; do
        case "$ch" in
            $'\n'|$'\r')  break ;;
            $'\x7f'|$'\b') buf="${buf%?}" ;;
            $'\x15')       buf="" ;;                      # Ctrl+U
            $'\x03')       print ""; return 130 ;;        # Ctrl+C
            $'\e')         # secuencia de escape (flechas, etc.): se descarta
                if read -rsk 1 -t 0.05 ch2 && [[ "$ch2" == "[" || "$ch2" == "O" ]]; then
                    while read -rsk 1 -t 0.05 ch2; do [[ "$ch2" == [A-Za-z~] ]] && break; done
                fi ;;
            *) buf+="$ch" ;;
        esac
    done
    print ""
    typeset -g -- "$var_name=$buf"
    return 0
}

confirm() {
    local ans
    prompt_input "$1 (s/n): " ans
    [[ "$ans" == [sSyY] ]]
}

pause_screen() {
    [[ -t 0 ]] || return 0
    print ""
    read -r "?Presiona Enter para continuar..."
    while read -r -t 0.01 -k 1 2>/dev/null; do :; done
}

# --- Carga de módulos ----------------------------------------------------------
# Verifica existencia y sintaxis antes de hacer 'source'; un módulo roto no
# tumba el dashboard: se informa y el resto sigue funcionando.
load_module() {
    local name="$1" f="$MODULE_DIR/$1.sh" err
    if [[ ! -f "$f" ]]; then LOAD_ERRORS+=("$name: no existe ($f)"); return 1; fi
    if ! err=$(zsh -n "$f" 2>&1); then
        LOAD_ERRORS+=("$name: error de sintaxis -> ${err%%$'\n'*}")
        return 1
    fi
    if ! source "$f"; then LOAD_ERRORS+=("$name: falló al cargarse"); return 1; fi
    LOADED_MODULES+=("$name")
}

load_all_modules() {
    local m
    for m in "${MODULES[@]}"; do load_module "$m"; done
}

# Banner mínimo de respaldo; modules/banner.sh lo reemplaza si se carga.
banner_main() {
    print "╔══════════════════════════════════════════════════════════════════╗"
    print "║                  P R O M E T H E R I O N  2 1 1 2                ║"
    print "║                 S Y S A D M I N   D A S H B O A R D              ║"
    print "╚══════════════════════════════════════════════════════════════════╝"
    print -r -- "[*] Usuario Activo : ${USER:-$(id -un)}@$HOST"
    print -r -- "[*] Servidor actual: $OS_NAME"
    print -r -- "[*] Versión script : v$VERSION ($SCRIPT_NAME)"
}


# --- Gestor de paquetes, motor de menús y descubrimiento ----------------------
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
        ip:dnf|ip:yum|ss:dnf|ss:yum)    print iproute ;;
        ip:*|ss:*)                      print iproute2 ;;
        ps:dnf|ps:yum)                  print procps-ng ;;
        ps:*)                           print procps ;;
        timeout:*|stat:*|df:*|sort:*)   print coreutils ;;
        find:*)                         print findutils ;;
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

# Cada ítem:  "Etiqueta|funcion"            -> ejecuta y pausa
#             "Etiqueta|funcion|nopause"    -> submenús (no pausa)
#             "#Título de sección"          -> encabezado
run_menu() {
    local title="$1"; shift
    local -a items=("$@") parts
    local -A map
    local choice it n fn flag hook="${MENU_HOOK:-}" quit_label="Volver al menú anterior"
    MENU_HOOK=""      # el hook es solo para ESTE menú: los submenús no lo heredan
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
                    if (( ${+functions[$fn]} )); then
                        "$fn"
                        [[ "$flag" != nopause ]] && pause_screen
                    else
                        msg_err "La función '$fn' no está definida (revisa el cableado: ./$SCRIPT_NAME selftest)."
                        pause_screen
                    fi
                elif [[ -n "$choice" ]]; then
                    msg_warn "Opción no válida."
                    sleep 1
                fi
                ;;
        esac
    done
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

# find acotado: auto_find <profundidad> <tests de find...>
auto_find() {
    timeout 20 find "$AUTO_BASE" -maxdepth "$1" "${AUTO_PRUNE[@]}" "${@:2}" -print 2>/dev/null
}

# ==============================================================================
#  MENÚ PRINCIPAL
# ==============================================================================
menu_main() {
    run_menu __MAIN__ \
        "Panorama general del servidor (Health Check)|act_health" \
        "SYSADMIN: servidor, servicios, seguridad, archivos, BBDD|menu_sysadmin|nopause" \
        "RED: diagnóstico, DNS, SSL, puertos, Nmap|menu_network|nopause" \
        "DEVOPS: Git, Ansible, Terraform, Docker|menu_devops|nopause" \
        "DEVSECOPS: secretos, IaC, imágenes, SSH, parches|menu_secops|nopause" \
        "CONSOLA: comandos reales con contexto y guardarraíles|console_start|nopause" \
        "UTILIDADES: clima, claves, QR, conversores, divisas|menu_utils|nopause"
}

# ==============================================================================
#  AUTODIAGNÓSTICO:  ./prom_claude.sh selftest
#  Verifica módulos, finales de línea, cableado de menús y dependencias.
#  Pásame su salida si algo falla en otra distro.
# ==============================================================================
selftest() {
    local -a files=("$SCRIPT_PATH" "$MODULE_DIR"/*.sh(N))
    local fn f c n=0 missing=0 req_missing=0 crlf=0 sudo_note=""

    section "MÓDULOS"
    for c in "${MODULES[@]}"; do
        if (( ${LOADED_MODULES[(Ie)$c]} )); then print -r -- " ${C_GRN}[ OK ]${C_RST} $c"
        else print -r -- " ${C_RED}[FALLA]${C_RST} $c"; fi
    done
    for f in "${LOAD_ERRORS[@]}"; do print -r -- "   - $f"; done

    section "FINALES DE LÍNEA"
    for f in "${files[@]}"; do
        if grep -q $'\r' "$f" 2>/dev/null; then
            print -r -- " ${C_RED}[CRLF]${C_RST} ${f:t}  ->  sed -i 's/\\r\$//' $f"; crlf=$(( crlf + 1 ))
        fi
    done
    (( crlf == 0 )) && print -r -- " ${C_GRN}[ OK ]${C_RST} todos los archivos usan LF"

    section "CABLEADO DE MENÚS"
    for fn in ${(u)${(f)"$(sed -nE 's/^[[:space:]]*"[^"|]*\|([a-z_0-9]+)(\|nopause)?".*/\1/p' "${files[@]}")"}}; do
        n=$(( n + 1 ))
        if (( ! ${+functions[$fn]} )); then
            print -r -- " ${C_RED}[FALTA]${C_RST} función '$fn' no está definida"; missing=$(( missing + 1 ))
        fi
    done
    print -r -- " $n handlers revisados, $missing sin definir"

    section "ENTORNO"
    kv "Script" "v$VERSION ($SCRIPT_PATH)"
    kv "Módulos" "$MODULE_DIR"
    kv "zsh" "$ZSH_VERSION"
    kv "OS" "$OS_NAME"
    kv "Gestor" "$PKG_MGR"
    kv "systemd" "$(have_systemd && print sí || print no)"
    (( EUID != 0 )) && ! command -v sudo &>/dev/null && sudo_note="  [!] sin sudo"
    kv "Usuario" "${USER:-$(id -un)} (EUID $EUID)$sudo_note"
    kv "Repo Git" "$REPO_DIR"
    kv "Estado/log" "$STATE_DIR"
    kv "Locale" "${LC_ALL:-${LANG:-N/D}}"
    kv "ZLE" "$([[ -t 0 && -t 1 ]] && { zle -l &>/dev/null && print activo || print inactivo; } || print 'sin terminal')"

    section "DEPENDENCIAS BASE (necesarias)"
    for c in awk sed grep ps ip ss df stat curl openssl timeout find sort; do
        if command -v "$c" &>/dev/null; then print -r -- " ${C_GRN}[ OK ]${C_RST} $c"
        else print -r -- " ${C_RED}[FALTA]${C_RST} $c  (paquete: $(pkg_for "$c"))"; req_missing=$(( req_missing + 1 )); fi
    done
    section "HERRAMIENTAS OPCIONALES"
    for c in jq git docker ansible terraform tofu nmap rsync btop htop dig whois traceroute nc \
             qrencode mysql psql sqlcmd fuser lsof firewall-cmd getenforce chronyc \
             trivy gitleaks checkov tfsec hadolint ansible-lint yamllint kubectl; do
        if command -v "$c" &>/dev/null || { [[ "$c" == sqlcmd ]] && find_sqlcmd &>/dev/null; }; then
            print -r -- " ${C_GRN}[ OK ]${C_RST} $c"
        else
            print -r -- " [  -  ] $c"
        fi
    done
    print ""
    if (( missing + req_missing + crlf + ${#LOAD_ERRORS} == 0 )); then msg_ok "Selftest correcto."; return 0; fi
    msg_err "Selftest con problemas: ${#LOAD_ERRORS} módulo(s) con error, $crlf archivo(s) CRLF, $missing handler(s) sin definir, $req_missing dependencia(s) base ausente(s)."
    return 1
}

usage() {
    cat <<EOF
$SCRIPT_NAME v$VERSION - Prometherion2112 Dashboard (modular)

Uso:
  $SCRIPT_NAME             Menú interactivo
  $SCRIPT_NAME sysadmin    Entra directo al menú Sysadmin
  $SCRIPT_NAME network     Entra directo al menú Red
  $SCRIPT_NAME devops      Entra directo al menú DevOps
  $SCRIPT_NAME secops      Entra directo al menú DevSecOps
  $SCRIPT_NAME console     Consola DevOps (comandos reales con contexto)
  $SCRIPT_NAME utils       Entra directo al menú Utilidades
  $SCRIPT_NAME health      Health Check sin menú (SSH / cron)
  $SCRIPT_NAME health-csv [--excel] [archivo]   Health Check en CSV (stdout si no hay archivo; con archivo agrega filas)
  $SCRIPT_NAME metrics     Métricas formato Prometheus (textfile collector)
  $SCRIPT_NAME selftest    Verifica módulos, menús y dependencias
  $SCRIPT_NAME version     Muestra la versión
  $SCRIPT_NAME help        Esta ayuda

Variables de entorno:
  PROM_REPO_DIR         Repo Git activo        (default: \$HOME/.local/bin/scripts)
  PROM_MODULE_DIR       Carpeta de módulos     (default: <script>/modules)
  PROM_AUTOMATION_DIR   Base para buscar proyectos Ansible/Terraform/Compose (default: \$HOME)
  PROM_BANNER_ONLINE=0  Desactiva clima/IP pública en el banner
  PROM_CONSOLE_ALLOW    Herramientas extra permitidas en la consola (ej: "k9s kustomize")
  NO_COLOR=1            Desactiva colores

Log de acciones: $LOG_FILE
EOF
}

_interactive_setup() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        msg_err "El menú requiere una terminal interactiva. Prueba: $SCRIPT_NAME health"
        return 1
    fi
    OLD_STTY=$(stty -g 2>/dev/null)
    trap 'stty "$OLD_STTY" 2>/dev/null' EXIT TERM
    trap 'stty "$OLD_STTY" 2>/dev/null; true' INT       # Ctrl+C no cierra el dashboard
    init_log
    if (( ${#LOAD_ERRORS} )); then
        msg_warn "Hay módulos con problemas (detalle: ./$SCRIPT_NAME selftest):"
        printf '   - %s\n' "${LOAD_ERRORS[@]}"
        pause_screen
    fi
}

main() {
    detect_pkg_manager
    OS_NAME=$(get_os_name)
    load_all_modules

    case "${1:-menu}" in
        menu)
            _interactive_setup || return 1
            menu_main
            print "¡Hasta luego, Leonardo! Cerrando dashboard."
            ;;
        sysadmin|devops|network|utils|secops)
            _interactive_setup || return 1
            if (( ! ${+functions[menu_$1]} )); then msg_err "El menú '$1' no está disponible (módulo no cargado)."; return 1; fi
            "menu_$1"
            ;;
        console)
            _interactive_setup || return 1
            (( ${+functions[console_start]} )) || { msg_err "Falta el módulo console."; return 1; }
            console_start ;;
        health-csv)
            (( ${+functions[health_csv_cli]} )) || { msg_err "Falta el módulo sysadmin."; return 1; }
            shift; health_csv_cli "$@" ;;
        health)
            (( ${+functions[health_check]} )) || { msg_err "Falta el módulo sysadmin."; return 1; }
            init_log; health_check ;;
        metrics)
            (( ${+functions[metrics_output]} )) || { msg_err "Falta el módulo sysadmin."; return 1; }
            metrics_output ;;
        selftest)           selftest ;;
        version|-v|--version) print "$SCRIPT_NAME v$VERSION" ;;
        help|-h|--help)     usage ;;
        *)                  usage; return 1 ;;
    esac
}

main "$@"
