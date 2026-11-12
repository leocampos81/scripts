#!/usr/bin/env zsh

# ==============================================================================
#  PROMETHERION2112 - SYSADMIN TOOLKIT & DASHBOARD
#  Repositorio: git@github.com:leocampos81/scripts.git
#  Autor: Leonardo Campos (https://github.com/leocampos81)
# ==============================================================================
#  BITÁCORA DE CAMBIOS (CHANGELOG)
# ==============================================================================
#  [2026-11-09] - v3.0 a v3.9 (Rama DS)
#    * Evolución del script: Health Check, autoinstalación de paquetes, 
#      formatos de tabla, fichas técnicas de red, arreglos de DNF, etc.
#
#  [2026-11-11] - v4.0 (Rama DS)
#    * Rediseño total del Health Check (Opción 1): formato lista sin bordes.
#
#  [2026-11-11] - v4.1 (Rama DS)
#    * Robustecimiento del menú Git (Sección 5).
#
#  [2026-11-11] - v4.2 (Rama DS)
#    * Nueva Opción 8 en el menú principal: "Tareas Programadas y Logs".
#
#  [2026-11-11] - v4.3 (Rama DS)
#    * Rediseño de la búsqueda de logs (Opciones 5 y 6 de la Sección 8):
#      - Ahora escanea /var/log y subcarpetas buscando archivos de texto.
#      - Muestra una lista numerada interactiva para evitar escribir rutas a mano.
#      - Filtra archivos binarios (btmp, wtmp) y comprimidos.
# ==============================================================================

# --- Rutas y variables globales -----------------------------------------------
SCRIPT_DIR="${0:A:h}"
REPO_DIR="$HOME/.local/bin/scripts"
LOG_FILE="$REPO_DIR/sysadmin.log"

mkdir -p "$REPO_DIR" 2>/dev/null

OLD_STTY=$(stty -g 2>/dev/null)
trap 'stty "$OLD_STTY" 2>/dev/null' INT TERM EXIT

# --- Detección centralizada de gestor de paquetes -----------------------------
detect_pkg_manager() {
    if command -v apt &>/dev/null; then
        PKG_MGR="apt"; PKG_INSTALL="sudo apt install -y"; PKG_UPDATE="sudo apt update"
    elif command -v dnf &>/dev/null; then
        PKG_MGR="dnf"; PKG_INSTALL="sudo dnf install -y"; PKG_UPDATE="sudo dnf check-update"
    elif command -v pacman &>/dev/null; then
        PKG_MGR="pacman"; PKG_INSTALL="sudo pacman -S --noconfirm"; PKG_UPDATE="sudo pacman -Sy"
    elif command -v zypper &>/dev/null; then
        PKG_MGR="zypper"; PKG_INSTALL="sudo zypper install -y"; PKG_UPDATE="sudo zypper refresh"
    elif command -v apk &>/dev/null; then
        PKG_MGR="apk"; PKG_INSTALL="sudo apk add"; PKG_UPDATE="sudo apk update"
    else
        PKG_MGR="unknown"; PKG_INSTALL=""; PKG_UPDATE=""
    fi
}
detect_pkg_manager

# --- Utilidades internas ------------------------------------------------------
log_action() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

get_os_info() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$PRETTY_NAME"
    else
        echo "Linux genérico"
    fi
}

pause_screen() {
    echo ""
    echo -n "Presiona Enter para continuar..."
    read -r _
    while read -r -t 0.01 -k 1 2>/dev/null; do :; done
}

prompt_input() {
    local prompt_msg="$1"
    local var_name="$2"

    local old_stty_local=$(stty -g 2>/dev/null)
    stty erase '^?' erase '^H' 2>/dev/null

    echo -n "$prompt_msg"
    read -r "$var_name"

    stty "$old_stty_local" 2>/dev/null
}

ccurl() {
    curl -s --max-time 10 "$@"
}

# --- Instalación inteligente de dependencias ----------------------------------
ensure_pkg() {
    local bin="$1"
    local pkg="${2:-$1}"

    if command -v "$bin" &>/dev/null; then
        return 0
    fi

    echo "[!] '$bin' no está instalado."
    if [[ "$PKG_MGR" == "unknown" ]]; then
        echo "[!] No se detectó un gestor de paquetes compatible."
        return 1
    fi

    prompt_input "¿Deseas instalar '$pkg' ahora con $PKG_MGR? (s/n): " inst_ans
    if [[ "$inst_ans" != "s" && "$inst_ans" != "S" ]]; then
        return 1
    fi

    echo "[-] Instalando '$pkg' con $PKG_MGR..."
    eval "$PKG_INSTALL $pkg"
    log_action "Instalación: $pkg vía $PKG_MGR"

    if command -v "$bin" &>/dev/null; then
        echo "[OK] '$bin' instalado correctamente."
        return 0
    else
        echo "[!] La instalación de '$pkg' falló o el binario '$bin' no está en PATH."
        return 1
    fi
}

need() {
    ensure_pkg "$1" "${2:-$1}"
}

# --- Menú principal -----------------------------------------------------------
menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                                                                  ║"
        echo "║                  P R O M E T H E R I O N  2 1 1 2                ║"
        echo "║                 S Y S A D M I N   D A S H B O A R D              ║"
        echo "║                                                                  ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        local sistema_actual=$(get_os_info)
        echo "[*] Usuario Activo : $USER@$(hostname)"
        echo "[*] Servidor actual: $sistema_actual"
        echo "[*] Gestor paquetes: $PKG_MGR"
        echo "=========================================================="
        echo " 1) Panorama general del servidor (Health Check)"
        echo " 2) Herramientas Nativas (Archivos, Servicios, Red, Monitoreo)"
        echo " 3) Monitoreo Avanzado de Recursos (btop, ps top CPU/RAM)"
        echo " 4) Servicios y Contenedores Docker (Avanzado)"
        echo " 5) Mantenimiento de Sistema y Sincronización Git"
        echo " 6) Utilidades Locales y Consultas (Clima, QR, Credenciales)"
        echo " 7) Herramientas de Automatización (Ansible, Terraform)"
        echo " 8) Tareas Programadas (Cron) y Logs del Sistema"
        echo " 9) Auditoría de Red y Seguridad (Nmap)"
        echo "10) Diagnóstico y Pruebas de Red Avanzadas"
        echo ""
        echo " q) Salir (o presiona 'q')"
        echo "=========================================================="

        prompt_input "LEO-DASHBOARD > Elige una opción [1-10 o q]: " opt

        case $opt in
            1)
                clear
                echo "===================================================================="
                echo "               PANORAMA GENERAL DEL SERVIDOR (HEALTH)               "
                echo "===================================================================="
                echo ""
                
                local os_name=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
                local kernel=$(uname -r | sed 's/\.x86_64//')
                local arch=$(uname -m)
                local uptime=$(uptime -p | sed 's/up //')
                local cpu_model=$(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | xargs | sed 's/ CPU.*//')
                local cpu_cores=$(nproc)
                local ram_total=$(free -h | awk '/^Mem:/{print $2}')
                local ram_used=$(free -h | awk '/^Mem:/{print $3}')
                local swap_total=$(free -h | awk '/^Swap:/{print $2}')
                local swap_used=$(free -h | awk '/^Swap:/{print $3}')
                
                echo "--- SISTEMA Y HARDWARE ---------------------------------------------"
                echo " Hostname    : $(hostname)"
                echo " OS          : $os_name"
                echo " Kernel      : $kernel ($arch)"
                echo " Uptime      : $uptime"
                echo " CPU         : $cpu_model"
                echo " Núcleos     : $cpu_cores vCPU"
                echo " RAM         : $ram_used / $ram_total en uso"
                if [[ "$swap_used" != "0B" && "$swap_used" != "0" ]]; then
                    echo " Swap        : ¡ALERTA! $swap_used de $swap_total en uso"
                else
                    echo " Swap        : No utilizado ($swap_total)"
                fi
                echo ""

                local updates_pending=0
                if [[ "$PKG_MGR" == "apt" ]]; then
                    updates_pending=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
                elif [[ "$PKG_MGR" == "dnf" ]]; then
                    updates_pending=$(dnf -C -q check-update 2>/dev/null | grep -c "^[a-zA-Z0-9]")
                fi
                
                echo "--- ACTUALIZACIONES DEL SISTEMA ------------------------------------"
                if [[ $updates_pending -gt 0 ]]; then
                    echo " [!] Paquetes pendientes: $updates_pending actualizaciones"
                else
                    echo " [OK] Sistema actualizado (sin pendientes)"
                fi
                echo ""

                echo "--- ALMACENAMIENTO -------------------------------------------------"
                df -h -x tmpfs -x devtmpfs -x squashfs | awk 'NR>1 {
                    printf " %-22s %-10s %-10s %-10s %-6s\n", "Montaje: "$6, "Total: "$2, "Usado: "$3, "Disp: "$4, "Uso: "$5
                }'
                echo ""

                local primary_iface=$(ip route show default | awk '{print $5}' | head -n 1)
                local primary_ip=$(ip -4 addr show "$primary_iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
                local gateway=$(ip route show default | awk '{print $3}' | head -n 1)
                
                echo "--- CONECTIVIDAD DE RED PRINCIPAL ----------------------------------"
                echo " Interfaz    : ${primary_iface:-N/A}"
                echo " IP Local    : ${primary_ip:-N/A}"
                echo " Gateway     : ${gateway:-N/A}"
                echo ""

                echo "--- SERVICIOS CRÍTICOS (Activos) -----------------------------------"
                local critical_services=(
                    "ssh" "sshd" "docker" "cron" "crond" 
                    "systemd-resolved" "firewalld" "ufw" 
                    "NetworkManager" "network" "chronyd" "ntp" 
                    "auditd" "rsyslog" "nginx" "apache2" "httpd" 
                    "mariadb" "mysql" "postgresql"
                )
                local active_found=0
                for svc in "${critical_services[@]}"; do
                    if systemctl is-active --quiet "$svc" 2>/dev/null; then
                        echo " [ OK ] $svc"
                        active_found=1
                    fi
                done
                if [[ $active_found -eq 0 ]]; then
                    echo " No se detectaron servicios críticos corriendo."
                fi
                echo ""

                local load_avg=$(cat /proc/loadavg | awk '{print $1 ", " $2 ", " $3}')
                local total_procs=$(ps -e --no-headers | wc -l)
                local zombie_procs=$(ps -eo stat --no-headers | grep -c '^Z')
                
                echo "--- ESTADO DE CARGA Y PROCESOS -------------------------------------"
                echo " Load Average: $load_avg"
                echo " Total Procs : $total_procs procesos"
                if [[ "$zombie_procs" -gt 0 ]]; then
                    echo " Zombies     : ¡ALERTA! $zombie_procs procesos Z"
                else
                    echo " Zombies     : 0 (Saludable)"
                fi
                echo ""
                echo " TOP 5 RAM:"
                ps aux --sort=-%mem | grep -v "ps aux" | awk 'NR>=1 && NR<=5 {printf "  %-15.15s %-6s %-25.25s\n", $1, $4"%", $11}'
                echo ""
                echo " TOP 5 CPU:"
                ps aux --sort=-%cpu | grep -v "ps aux" | awk 'NR>=1 && NR<=5 {printf "  %-15.15s %-6s %-25.25s\n", $1, $3"%", $11}'
                echo ""

                log_action "Panorama general del servidor generado"
                pause_screen
                ;;
            2)
                while true; do
                    clear
                    echo "=========================================================="
                    echo "          HERRAMIENTAS NATIVAS Y DIAGNÓSTICO LINUX"
                    echo "=========================================================="
                    echo "--- TRABAJAR CON ARCHIVOS ---"
                    echo " 1) Editar archivos (nvim / nano / vi)"
                    echo " 2) Búsqueda y filtrado de texto (grep / egrep)"
                    echo " 3) Análisis técnico de archivo (stat, file, wc, awk)"
                    echo " 4) Comparación de archivos (diff)"
                    echo " 5) Resguardo rápido (rsync)"
                    echo ""
                    echo "--- SERVICIOS Y LOGS (SYSTEMCTL / JOURNALCTL) ---"
                    echo " 6) Gestión de servicios systemctl (con autolistado de activos)"
                    echo " 7) Inspección de logs journalctl (con autolistado de servicios)"
                    echo ""
                    echo "--- RECURSOS, DISCOS Y RED NATIVA ---"
                    echo " 8) Recursos locales y procesos en vivo (top, ps CPU/RAM, free)"
                    echo " 9) Almacenamiento y particiones (df -h formateado)"
                    echo "10) Red básica e interfaces (resumen de interfaces y rutas)"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================================="
                    prompt_input "Elige una opción [1-10 o q]: " nat_opt

                    case $nat_opt in
                        1)
                            echo ""
                            echo "=========================================="
                            echo "        EDITOR DE ARCHIVOS LOCALES"
                            echo "=========================================="
                            echo " 1) nvim"
                            echo " 2) nano"
                            echo " 3) vi"
                            prompt_input "Selecciona el editor [1-3]: " ed_opt
                            prompt_input "Ruta del archivo a editar: " target_file

                            if [[ -n "$target_file" ]]; then
                                case $ed_opt in
                                    1) nvim "$target_file" ;;
                                    2) nano "$target_file" ;;
                                    3) vi "$target_file" ;;
                                    *) nano "$target_file" ;;
                                esac
                                log_action "Editor: Abierto archivo $target_file"
                            fi
                            pause_screen
                            ;;
                        2)
                            echo ""
                            echo "=========================================="
                            echo "    BÚSQUEDA Y FILTRADO EN TEXTO / LOGS"
                            echo "=========================================="
                            prompt_input "Ruta del archivo a inspeccionar (ej: /var/log/syslog): " log_file
                            if [[ -f "$log_file" ]]; then
                                prompt_input "Patrón o término de búsqueda (ej: ERROR|FAIL): " pattern
                                if [[ -n "$pattern" ]]; then
                                    echo "[-] Resultado de la búsqueda en '$log_file':"
                                    grep -iE "$pattern" "$log_file" | head -n 30
                                    log_action "Grep: Búsqueda de '$pattern' en $log_file"
                                fi
                            else
                                echo "[ERROR] El archivo '$log_file' no existe o no se puede leer."
                            fi
                            pause_screen
                            ;;
                        3)
                            echo ""
                            echo "╔══════════════════════════════════════════════════╗"
                            echo "║        ANÁLISIS TÉCNICO DE ARCHIVO (SYSADMIN)    ║"
                            echo "╚══════════════════════════════════════════════════╝"
                            prompt_input "Ruta del archivo a analizar: " info_file
                            
                            if [[ -f "$info_file" ]]; then
                                local file_out=$(file -b "$info_file")
                                local f_size=$(stat -c "%s" "$info_file")
                                local f_perm=$(stat -c "%A (%a)" "$info_file")
                                local f_owner=$(stat -c "%U:%G" "$info_file")
                                
                                echo ""
                                echo "┌──────────────────────────────────────────────────┐"
                                echo "│ IDENTIDAD DEL ARCHIVO                            │"
                                echo "├──────────────────────────────────────────────────┤"
                                printf "│ Tipo       : %-36.36s │\n" "$file_out"
                                printf "│ Tamaño     : %-36s │\n" "$f_size bytes"
                                printf "│ Permisos   : %-36s │\n" "$f_perm"
                                printf "│ Propietario: %-36s │\n" "$f_owner"
                                echo "└──────────────────────────────────────────────────┘"

                                echo ""
                                echo "┌──────────────────────────────────────────────────┐"
                                echo "│ FECHAS DE ESTADO                                 │"
                                echo "├──────────────────────────────────────────────────┤"
                                local f_mod=$(stat -c "%y" "$info_file")
                                local f_acc=$(stat -c "%x" "$info_file")
                                local f_cre=$(stat -c "%w" "$info_file")
                                
                                printf "│ Modificado : %-36.36s │\n" "$f_mod"
                                printf "│ Accedido   : %-36.36s │\n" "$f_acc"
                                
                                if [[ "$f_cre" == "-" ]]; then
                                    printf "│ Creado     : %-36.36s │\n" "No disponible (FS)"
                                else
                                    printf "│ Creado     : %-36.36s │\n" "$f_cre"
                                fi
                                echo "└──────────────────────────────────────────────────┘"

                                echo ""
                                local wc_data=($(wc -l -w -c -m "$info_file"))
                                local wc_lines=${wc_data[1]}
                                local wc_words=${wc_data[2]}
                                local wc_bytes=${wc_data[3]}
                                local wc_chars=${wc_data[4]}
                                
                                local awk_out=$(awk '{ 
                                    if (length($0) > max) max = length($0); 
                                    if (length($0) == 0) empty++; 
                                } END { print max+0, empty+0 }' "$info_file")
                                
                                local max_line_len=$(echo "$awk_out" | awk '{print $1}')
                                local empty_lines=$(echo "$awk_out" | awk '{print $2}')
                                
                                local avg_words=0
                                if [[ "$wc_lines" -gt 0 ]]; then
                                    avg_words=$(awk "BEGIN {printf \"%.2f\", $wc_words / $wc_lines}")
                                fi

                                echo "┌──────────────┬──────────────┬──────────────┬──────────────┐"
                                echo "│    LÍNEAS    │   PALABRAS   │  CARACTERES  │    BYTES     │"
                                echo "├──────────────┼──────────────┼──────────────┼──────────────┤"
                                printf "│ %12s │ %12s │ %12s │ %12s │\n" "$wc_lines" "$wc_words" "$wc_chars" "$wc_bytes"
                                echo "└──────────────┴──────────────┴──────────────┴──────────────┘"
                                
                                echo ""
                                echo "┌──────────────────────────────────────────────────┐"
                                echo "│ DENSIDAD Y ESTRUCTURA                            │"
                                echo "├──────────────────────────────────────────────────┤"
                                printf "│ Línea más larga    : %-27s │\n" "$max_line_len caracteres"
                                printf "│ Líneas vacías      : %-27s │\n" "$empty_lines"
                                printf "│ Promedio palabras/L: %-27s │\n" "$avg_words"
                                echo "└──────────────────────────────────────────────────┘"

                                log_action "Info: Análisis técnico de $info_file"
                            else
                                echo "[ERROR] El archivo no existe."
                            fi
                            pause_screen
                            ;;
                        4)
                            echo ""
                            prompt_input "Ruta del Archivo 1: " f1
                            prompt_input "Ruta del Archivo 2: " f2
                            if [[ -f "$f1" && -f "$f2" ]]; then
                                echo "[-] Diferencias encontradas (diff -u):"
                                diff -u "$f1" "$f2" || true
                                log_action "Diff: Comparación entre $f1 y $f2"
                            else
                                echo "[ERROR] Uno o ambos archivos no existen."
                            fi
                            pause_screen
                            ;;
                        5)
                            echo ""
                            echo "=========================================="
                            echo "      SINCRONIZACIÓN CON RSYNC"
                            echo "=========================================="
                            if need rsync; then
                                prompt_input "Directorio o archivo origen: " r_src
                                prompt_input "Directorio o host destino (user@host:/ruta o /ruta): " r_dst
                                if [[ -n "$r_src" && -n "$r_dst" ]]; then
                                    echo "[-] Ejecutando 'rsync -avh --progress':"
                                    echo "    (si el destino es remoto, se requiere SSH configurado)"
                                    rsync -avh --progress "$r_src" "$r_dst"
                                    log_action "Rsync: $r_src hacia $r_dst"
                                fi
                            fi
                            pause_screen
                            ;;
                        6)
                            echo ""
                            echo "=========================================="
                            echo "      GESTIÓN DE SERVICIOS (SYSTEMCTL)"
                            echo "=========================================="
                            echo "[-] Listando servicios activos en el servidor:"
                            echo "------------------------------------------"
                            systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print "  > " $1, " (" $4 ")"}'
                            echo "------------------------------------------"

                            prompt_input "Indica el servicio a gestionar (ej: ssh.service o apache2): " svc_target

                            if [[ -n "$svc_target" ]]; then
                                [[ "$svc_target" != *.service ]] && svc_target="${svc_target}.service"

                                echo ""
                                echo "Servicio seleccionado: $svc_target"
                                echo " 1) Consultar estado (status)"
                                echo " 2) Iniciar servicio (start)"
                                echo " 3) Reiniciar servicio (restart)"
                                echo " 4) Detener servicio (stop)"
                                prompt_input "Elige la acción [1-4]: " act_svc

                                case $act_svc in
                                    1) sudo systemctl status "$svc_target" --no-pager ;;
                                    2) sudo systemctl start "$svc_target" && echo "[OK] Servicio iniciado." ; log_action "Systemctl: Start $svc_target" ;;
                                    3) sudo systemctl restart "$svc_target" && echo "[OK] Servicio reiniciado." ; log_action "Systemctl: Restart $svc_target" ;;
                                    4) sudo systemctl stop "$svc_target" && echo "[OK] Servicio detenido." ; log_action "Systemctl: Stop $svc_target" ;;
                                esac
                            fi
                            pause_screen
                            ;;
                        7)
                            echo ""
                            echo "=========================================="
                            echo "       INSPECCIÓN DE LOGS (JOURNALCTL)"
                            echo "=========================================="
                            echo "[-] Listando servicios activos disponibles para consulta:"
                            echo "------------------------------------------"
                            systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print "  > " $1}'
                            echo "------------------------------------------"

                            prompt_input "Nombre del servicio a consultar (ej: ssh, apache2, docker): " svc_name
                            if [[ -n "$svc_name" ]]; then
                                [[ "$svc_name" != *.service ]] && svc_name="${svc_name}.service"
                                echo "[-] Mostrando últimas 40 líneas de registro para '$svc_name':"
                                journalctl -u "$svc_name" -n 40 --no-pager
                                log_action "Journalctl: Consulta de logs en $svc_name"
                            fi
                            pause_screen
                            ;;
                        8)
                            echo ""
                            echo "=========================================="
                            echo "       RECURSOS Y PROCESOS LOCALES"
                            echo "=========================================="
                            echo " 1) Top 10 procesos por CPU"
                            echo " 2) Top 10 procesos por Memoria"
                            echo " 3) Memoria RAM y Swap en uso (free -h)"
                            echo " 4) Monitor interactivo básico (top)"
                            prompt_input "Selecciona opción [1-4]: " res_opt
                            case $res_opt in
                                1) ps aux --sort=-%cpu | head -n 11 ;;
                                2) ps aux --sort=-%mem | head -n 11 ;;
                                3) free -h ;;
                                4) top ;;
                            esac
                            log_action "Nativo: Monitoreo de recursos ejecutado."
                            pause_screen
                            ;;
                        9)
                            echo ""
                            echo "╔══════════════════════════════════════════════════╗"
                            echo "║           ALMACENAMIENTO Y PARTICIONES           ║"
                            echo "╚══════════════════════════════════════════════════╝"
                            echo ""
                            echo "┌──────────────────────┬──────────┬──────────┬──────────┬────────┐"
                            echo "│ PUNTO DE MONTAJE     │ TAMAÑO   │ USADO    │ DISP     │ USO %  │"
                            echo "├──────────────────────┼──────────┼──────────┼──────────┼────────┤"
                            df -h -x tmpfs -x devtmpfs -x squashfs | awk 'NR>1 {
                                printf "│ %-20.20s │ %-8s │ %-8s │ %-8s │ %-6s │\n", $6, $2, $3, $4, $5
                            }'
                            echo "└──────────────────────┴──────────┴──────────┴──────────┴────────┘"
                            log_action "Nativo: Consulta de almacenamiento df -h formateado"
                            pause_screen
                            ;;
                        10)
                            echo ""
                            echo "╔══════════════════════════════════════════════════╗"
                            echo "║             RED BÁSICA E INTERFACES              ║"
                            echo "╚══════════════════════════════════════════════════╝"
                            echo ""
                            echo "[-] Interfaces de red detectadas:"
                            ip -brief address | awk '{print "  > " $1 " (" $2 ")"}'
                            echo "------------------------------------------"
                            
                            echo " 1) Ver direcciones IP detalladas (ip a)"
                            echo " 2) Ver tabla de ruteo (ip route)"
                            echo " 3) Puertos locales en escucha (ss -tulpn)"
                            echo " 4) Prueba rápida de conectividad (ping)"
                            echo " 5) Ficha técnica de una interfaz específica"
                            prompt_input "Selecciona opción [1-5]: " net_choice
                            
                            case $net_choice in
                                1) ip -brief address ;;
                                2) ip route ;;
                                3) sudo ss -tulpn | grep LISTEN ;;
                                4)
                                    prompt_input "Ingresa IP o host de prueba: " p_target
                                    [[ -n "$p_target" ]] && ping -c 4 "$p_target"
                                    ;;
                                5)
                                    prompt_input "Ingresa el nombre de la interfaz (ej: eth0, wlan0): " iface
                                    if [[ -n "$iface" ]]; then
                                        local state=$(ip link show "$iface" 2>/dev/null | grep -oP 'state \K\w+')
                                        local mac=$(ip link show "$iface" 2>/dev/null | awk '/link\/ether/ {print $2}')
                                        local ipv4=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
                                        local ipv6=$(ip -6 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet6\s)[\da-f:]+' | head -n 1)
                                        local gw=$(ip route show default dev "$iface" 2>/dev/null | awk '{print $3}')
                                        
                                        echo ""
                                        echo "┌──────────────────────────────────────────────────┐"
                                        echo "│ FICHA TÉCNICA DE INTERFAZ                        │"
                                        echo "├──────────────────────────────────────────────────┤"
                                        printf "│ Interfaz   : %-36s │\n" "$iface"
                                        printf "│ Estado     : %-36s │\n" "${state:-Desconocido}"
                                        printf "│ MAC Address: %-36s │\n" "${mac:-N/A}"
                                        printf "│ IPv4       : %-36s │\n" "${ipv4:-N/A}"
                                        printf "│ IPv6       : %-36.36s │\n" "${ipv6:-N/A}"
                                        printf "│ Gateway    : %-36s │\n" "${gw:-N/A}"
                                        echo "└──────────────────────────────────────────────────┘"
                                    fi
                                    ;;
                            esac
                            log_action "Nativo: Consulta de red básica ejecutada."
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            3)
                while true; do
                    clear
                    echo "=========================================="
                    echo "   MONITOREO AVANZADO DE RECURSOS"
                    echo "=========================================="
                    echo " 1) btop (Monitor moderno)"
                    echo " 2) htop (Monitor por procesos)"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-2 o q]: " sub_opt
                    case $sub_opt in
                        1) need btop && btop ; pause_screen ;;
                        2) need htop && htop ; pause_screen ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            4)
                while true; do
                    clear
                    echo "=========================================="
                    echo "      GESTIÓN Y ESTADO DE DOCKER LAB"
                    echo "=========================================="
                    if ! need docker docker.io; then
                        pause_screen
                        break
                    fi

                    echo " 1) Ver contenedores activos (docker ps)"
                    echo " 2) Monitoreo de CPU/RAM en tiempo real (docker stats)"
                    echo " 3) Inspeccionar logs de un contenedor"
                    echo " 4) Reiniciar / Detener / Iniciar contenedor"
                    echo " 5) Limpieza general (docker system prune)"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-5 o q]: " d_opt

                    case $d_opt in
                        1)
                            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                            pause_screen
                            ;;
                        2)
                            echo "[-] Capturando snapshot de docker stats (no interactivo)..."
                            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
                            pause_screen
                            ;;
                        3)
                            prompt_input "Nombre del contenedor: " cnt_name
                            [[ -n "$cnt_name" ]] && docker logs -f --tail 50 "$cnt_name"
                            pause_screen
                            ;;
                        4)
                            prompt_input "Nombre del contenedor: " cnt_name
                            if [[ -n "$cnt_name" ]]; then
                                echo "1) Restart | 2) Stop | 3) Start"
                                prompt_input "Acción [1-3]: " act_c
                                case $act_c in
                                    1) sudo docker restart "$cnt_name" ;;
                                    2) sudo docker stop "$cnt_name" ;;
                                    3) sudo docker start "$cnt_name" ;;
                                esac
                            fi
                            pause_screen
                            ;;
                        5)
                            sudo docker system prune -f
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            5)
                while true; do
                    clear
                    echo "=========================================="
                    echo "   MANTENIMIENTO Y SINCRONIZACIÓN GIT"
                    echo "=========================================="
                    echo " 1) Actualizar paquetes de sistema (apt/dnf/pacman/zypper/apk)"
                    echo " 2) Ver estado del repositorio local (rama y cambios)"
                    echo " 3) Ver últimos commits (historial reciente)"
                    echo " 4) Descargar cambios del servidor (git pull)"
                    echo " 5) Subir cambios locales (git add + commit + push)"
                    echo " 6) Crear nueva rama de trabajo (git checkout -b)"
                    echo " 7) Descartar cambios locales (git restore .) [PELIGRO]"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-7 o q]: " git_opt

                    if ! cd "$REPO_DIR" 2>/dev/null; then
                        echo "[!] No se encontró el repositorio en $REPO_DIR"
                        pause_screen
                        continue
                    fi

                    case $git_opt in
                        1)
                            if [[ "$PKG_MGR" != "unknown" ]]; then
                                echo "[-] Actualizando sistema con $PKG_MGR..."
                                eval "$PKG_UPDATE"
                                case "$PKG_MGR" in
                                    apt) sudo apt dist-upgrade -y ;;
                                    dnf) sudo dnf upgrade -y --nobest --skip-broken ;;
                                    pacman) sudo pacman -Su --noconfirm ;;
                                    zypper) sudo zypper update -y ;;
                                    apk) sudo apk upgrade ;;
                                esac
                                log_action "Sistema: Actualización con $PKG_MGR"
                            else
                                echo "[!] No se detectó gestor de paquetes."
                            fi
                            pause_screen
                            ;;
                        2)
                            echo ""
                            local current_branch=$(git branch --show-current)
                            echo "[-] Rama actual: $current_branch"
                            echo ""
                            echo "[-] Estado del repositorio (archivos modificados/nuevos):"
                            if [[ -z $(git status -s) ]]; then
                                echo "    (El árbol de trabajo está limpio, no hay cambios)"
                            else
                                git status -s
                            fi
                            log_action "Git: Status consultado"
                            pause_screen
                            ;;
                        3)
                            echo ""
                            echo "[-] Últimos 5 commits:"
                            git log --oneline -n 5
                            log_action "Git: Log consultado"
                            pause_screen
                            ;;
                        4)
                            echo ""
                            echo "[-] Descargando cambios (git pull)..."
                            git pull
                            log_action "Git: Pull ejecutado"
                            pause_screen
                            ;;
                        5)
                            echo ""
                            if [[ -z $(git status -s) ]]; then
                                echo "[!] No hay cambios para subir."
                                pause_screen
                                continue
                            fi
                            
                            echo "[-] Archivos modificados:"
                            git status -s
                            echo ""
                            local default_msg="Actualiza prom.sh"
                            prompt_input "Mensaje para commit [Default: '$default_msg']: " git_msg
                            git_msg="${git_msg:-$default_msg}"
                            
                            echo "[-] Subiendo cambios..."
                            git add . && git commit -m "$git_msg" && git push
                            log_action "Git: Push ejecutado ($git_msg)"
                            pause_screen
                            ;;
                        6)
                            echo ""
                            prompt_input "Nombre de la nueva rama (ej: feature-red, fix-docker): " new_branch
                            if [[ -n "$new_branch" ]]; then
                                echo "[-] Creando y cambiando a la rama '$new_branch'..."
                                git checkout -b "$new_branch"
                                log_action "Git: Nueva rama creada ($new_branch)"
                            fi
                            pause_screen
                            ;;
                        7)
                            echo ""
                            echo "[!] ADVERTENCIA: Esto borrará TODOS los cambios no guardados (commits) en los archivos."
                            prompt_input "¿Estás seguro de descartar los cambios locales? (s/n): " confirm
                            if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                                echo "[-] Descartando cambios..."
                                git restore . 2>/dev/null || git checkout . 2>/dev/null
                                echo "[OK] Cambios locales descartados."
                                log_action "Git: Cambios locales descartados"
                            else
                                echo "[-] Operación cancelada."
                            fi
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            6)
                while true; do
                    clear
                    echo "=========================================="
                    echo "      UTILIDADES LOCALES Y CONSULTAS"
                    echo "=========================================="
                    echo "--- CLIMA Y ASTRONOMÍA ---"
                    echo " 1) Clima actual completo (wttr.in)"
                    echo " 2) Clima compacto de una línea (wttr.in/?format=3)"
                    echo " 3) Fase lunar actual (wttr.in/moon)"
                    echo " 4) Amanecer y atardecer (sunrise-sunset.org)"
                    echo ""
                    echo "--- GENERACIÓN LOCAL (SIN RED) ---"
                    echo " 5) Generar contraseña segura (openssl)"
                    echo " 6) Generar UUID v4 local"
                    echo " 7) Generar código QR en terminal (mkqr / qrencode)"
                    echo ""
                    echo "--- CONSULTAS Y REFERENCIA ---"
                    echo " 8) Diccionario / Definición de palabras (dict.org)"
                    echo " 9) Hojas de ayuda rápida de comandos (cht.sh)"
                    echo "10) Resumen de Wikipedia"
                    echo ""
                    echo "--- FINANZAS ---"
                    echo "11) Tipo de cambio de divisas (open.er-api.com)"
                    echo "12) Cotización de criptomonedas (coingecko)"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-12 o q]: " util_opt
                    case $util_opt in
                        1)
                            echo ""
                            prompt_input "Ciudad (Enter para autodetectar): " city
                            echo "[-] Consultando wttr.in..."
                            ccurl "wttr.in/${city}?lang=es&m"
                            log_action "Utilidades: Clima completo wttr.in (${city:-auto})"
                            pause_screen
                            ;;
                        2)
                            echo ""
                            echo "[-] Consultando clima compacto..."
                            ccurl "wttr.in/?format=3&m"
                            log_action "Utilidades: Clima compacto"
                            pause_screen
                            ;;
                        3)
                            echo ""
                            echo "[-] Consultando fase lunar..."
                            ccurl "wttr.in/moon"
                            log_action "Utilidades: Fase lunar"
                            pause_screen
                            ;;
                        4)
                            echo ""
                            if need jq; then
                                prompt_input "Latitud [Default: -33.45 (Santiago)]: " lat
                                prompt_input "Longitud [Default: -70.66 (Santiago)]: " lng
                                lat="${lat:--33.45}"
                                lng="${lng:--70.66}"
                                echo "[-] Amanecer/atardecer para ($lat, $lng):"
                                ccurl "https://api.sunrise-sunset.org/json?lat=$lat&lng=$lng&formatted=0" | jq '.results'
                                log_action "Utilidades: Sunrise/Sunset ($lat,$lng)"
                            fi
                            pause_screen
                            ;;
                        5)
                            echo ""
                            echo "[-] Generando contraseña aleatoria segura (20 chars alfanuméricos):"
                            openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-20
                            echo ""
                            log_action "Utilidades: Contraseña local generada"
                            pause_screen
                            ;;
                        6)
                            echo ""
                            echo "[-] UUID v4 generado localmente:"
                            if [[ -r /proc/sys/kernel/random/uuid ]]; then
                                cat /proc/sys/kernel/random/uuid
                            elif command -v uuidgen &>/dev/null; then
                                uuidgen | tr '[:upper:]' '[:lower:]'
                            else
                                openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
                            fi
                            echo ""
                            log_action "Utilidades: UUID generado localmente"
                            pause_screen
                            ;;
                        7)
                            echo ""
                            prompt_input "Ingresa el texto o URL para generar el QR: " qr_text
                            if [[ -n "$qr_text" ]]; then
                                if command -v mkqr &>/dev/null; then
                                    echo "[-] Generando QR con mkqr (local)..."
                                    mkqr "$qr_text"
                                elif command -v qrencode &>/dev/null; then
                                    echo "[-] Generando QR con qrencode (local)..."
                                    qrencode -t ansiutf8 "$qr_text"
                                elif need qrencode; then
                                    qrencode -t ansiutf8 "$qr_text"
                                else
                                    echo "[-] Fallback remoto: qrenco.de..."
                                    ccurl --get "qrenco.de/$(printf '%s' "$qr_text" | jq -sRr @uri 2>/dev/null || printf '%s' "$qr_text" | sed 's/ /%20/g')"
                                fi
                                log_action "Utilidades: Código QR generado"
                            fi
                            pause_screen
                            ;;
                        8)
                            echo ""
                            prompt_input "Ingresa la palabra a consultar (en inglés/término tech): " dict_word
                            if [[ -n "$dict_word" ]]; then
                                echo "[-] Buscando definición para '$dict_word'..."
                                ccurl "dict.org/d:$dict_word" | grep -v '^$' | head -n 40
                                log_action "Utilidades: Diccionario para $dict_word"
                            fi
                            pause_screen
                            ;;
                        9)
                            echo ""
                            prompt_input "Ingresa el comando a consultar (ej: rsync, tar, git): " c_cmd
                            if [[ -n "$c_cmd" ]]; then
                                echo "[-] Consultando cheat.sh para '$c_cmd'..."
                                ccurl "cht.sh/$c_cmd"
                                log_action "Utilidades: Cheat sheet de $c_cmd"
                            fi
                            pause_screen
                            ;;
                        10)
                            echo ""
                            if need jq; then
                                prompt_input "Término o título en Wikipedia (ej: Linux): " wiki_term
                                if [[ -n "$wiki_term" ]]; then
                                    echo "[-] Resumen de '$wiki_term' en es.wikipedia:"
                                    ccurl "https://es.wikipedia.org/api/rest_v1/page/summary/$(printf '%s' "$wiki_term" | jq -sRr @uri 2>/dev/null)" \
                                        | jq -r '.extract // .detail // "No encontrado"'
                                    log_action "Utilidades: Wikipedia $wiki_term"
                                fi
                            fi
                            pause_screen
                            ;;
                        11)
                            echo ""
                            if need jq; then
                                prompt_input "Moneda base (ej: USD, CLP, EUR) [Default: USD]: " base_cur
                                base_cur="${base_cur:-USD}"
                                echo "[-] Tasas de cambio para $base_cur:"
                                ccurl "https://open.er-api.com/v6/latest/$base_cur" | jq '.rates // .'
                                log_action "Utilidades: Tipo de cambio base $base_cur"
                            fi
                            pause_screen
                            ;;
                        12)
                            echo ""
                            if need jq; then
                                prompt_input "IDs de cripto separados por coma [Default: bitcoin,ethereum]: " crypto_ids
                                crypto_ids="${crypto_ids:-bitcoin,ethereum}"
                                prompt_input "Moneda fiat (ej: usd, eur, clp) [Default: usd]: " fiat
                                fiat="${fiat:-usd}"
                                echo "[-] Cotización de $crypto_ids en $fiat:"
                                ccurl "https://api.coingecko.com/api/v3/simple/price?ids=${crypto_ids}&vs_currencies=${fiat}" | jq .
                                log_action "Utilidades: Cripto $crypto_ids/$fiat"
                            fi
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            7)
                while true; do
                    clear
                    echo "=========================================="
                    echo "      HERRAMIENTAS DE AUTOMATIZACIÓN"
                    echo "=========================================="
                    echo " 1) Ansible Status"
                    echo " 2) Terraform Status"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-2 o q]: " aut_opt
                    case $aut_opt in
                        1) need ansible && ansible --version ; pause_screen ;;
                        2) need terraform && terraform version ; pause_screen ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            8)
                while true; do
                    clear
                    echo "===================================================================="
                    echo "              TAREAS PROGRAMADAS (CRON) Y LOGS DEL SISTEMA          "
                    echo "===================================================================="
                    echo " 1) Listar mis tareas programadas (crontab actual)"
                    echo " 2) Editar mis tareas programadas (crontab -e)"
                    echo " 3) Listar tareas del sistema (/etc/crontab y /etc/cron.d/)"
                    echo ""
                    echo " 4) Listar carpetas y archivos de logs comunes (por tamaño)"
                    echo " 5) Ver un log en tiempo real (tail -f) [Interactivo]"
                    echo " 6) Buscar errores recientes en un log [Interactivo]"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================================="
                    prompt_input "Elige una opción [1-6 o q]: " cron_log_opt
                    
                    case $cron_log_opt in
                        1)
                            echo ""
                            echo "[-] Tareas cron del usuario actual ($USER):"
                            echo "------------------------------------------"
                            crontab -l 2>/dev/null || echo "No hay tareas programadas para este usuario."
                            pause_screen
                            ;;
                        2)
                            echo ""
                            echo "[-] Abriendo editor de crontab (guarda y sal para aplicar)..."
                            crontab -e
                            log_action "Cron: Edición de crontab de usuario"
                            pause_screen
                            ;;
                        3)
                            echo ""
                            echo "[-] Tareas programadas del sistema:"
                            echo "--- /etc/crontab ---"
                            cat /etc/crontab 2>/dev/null | grep -v "^#" | grep -v "^$"
                            echo ""
                            echo "--- Archivos en /etc/cron.d/ ---"
                            if [[ -d /etc/cron.d ]]; then
                                ls -1 /etc/cron.d/ 2>/dev/null
                            else
                                echo "(Directorio no existe o está vacío)"
                            fi
                            pause_screen
                            ;;
                        4)
                            echo ""
                            echo "[-] Buscando directorios de logs comunes..."
                            local log_dirs=("/var/log" "/var/log/apache2" "/var/log/nginx" "/var/log/mysql" "/var/log/httpd")
                            
                            for dir in "${log_dirs[@]}"; do
                                if [[ -d "$dir" ]]; then
                                    echo ""
                                    echo "--- Contenido de $dir (Top 10 archivos más grandes) ---"
                                    find "$dir" -maxdepth 1 -type f -exec ls -lhS {} + 2>/dev/null | awk 'NR<=10 {printf " %-8s %-6s %-12s %s\n", $5, $6$7, $8, $9}'
                                fi
                            done
                            pause_screen
                            ;;
                        5)
                            echo ""
                            echo "[-] Buscando archivos de log de texto comunes..."
                            local logs_found=($(find /var/log -maxdepth 2 -type f ! -name "*.gz" ! -name "*.xz" ! -name "*.zip" ! -name "btmp*" ! -name "wtmp*" ! -name "lastlog" 2>/dev/null | sort))
                            
                            if [[ ${#logs_found[@]} -eq 0 ]]; then
                                echo "[!] No se encontraron archivos de log de texto."
                                pause_screen
                                continue
                            fi

                            echo ""
                            local i=1
                            for logfile in "${logs_found[@]}"; do
                                printf " %2d) %s\n" "$i" "$logfile"
                                ((i++))
                            done
                            
                            echo ""
                            prompt_input "Selecciona el número del log a ver (o 'q' para cancelar): " log_num
                            if [[ "$log_num" == "q" || -z "$log_num" ]]; then
                                continue
                            fi
                            
                            if [[ "$log_num" =~ ^[0-9]+$ ]] && (( log_num >= 1 && log_num <= ${#logs_found[@]} )); then
                                local target_log="${logs_found[$log_num]}"
                                echo "[-] Mostrando '$target_log' en vivo (Presiona Ctrl+C para salir)..."
                                sleep 1
                                sudo tail -f "$target_log"
                                log_action "Logs: Tail -f en $target_log"
                            else
                                echo "[ERROR] Selección no válida."
                            fi
                            pause_screen
                            ;;
                        6)
                            echo ""
                            echo "[-] Buscando archivos de log de texto comunes..."
                            local logs_found=($(find /var/log -maxdepth 2 -type f ! -name "*.gz" ! -name "*.xz" ! -name "*.zip" ! -name "btmp*" ! -name "wtmp*" ! -name "lastlog" 2>/dev/null | sort))
                            
                            if [[ ${#logs_found[@]} -eq 0 ]]; then
                                echo "[!] No se encontraron archivos de log de texto."
                                pause_screen
                                continue
                            fi

                            echo ""
                            local i=1
                            for logfile in "${logs_found[@]}"; do
                                printf " %2d) %s\n" "$i" "$logfile"
                                ((i++))
                            done
                            
                            echo ""
                            prompt_input "Selecciona el número del log a analizar (o 'q' para cancelar): " log_num
                            if [[ "$log_num" == "q" || -z "$log_num" ]]; then
                                continue
                            fi
                            
                            if [[ "$log_num" =~ ^[0-9]+$ ]] && (( log_num >= 1 && log_num <= ${#logs_found[@]} )); then
                                local target_log="${logs_found[$log_num]}"
                                echo ""
                                echo "[-] Buscando errores/fallos en las últimas 100 líneas de '$target_log':"
                                echo "--------------------------------------------------------"
                                sudo tail -n 100 "$target_log" | grep -iE "error|fail|crit|warn|severe|denied|refused" || echo "No se encontraron patrones de error recientes."
                                log_action "Logs: Filtro de errores en $target_log"
                            else
                                echo "[ERROR] Selección no válida."
                            fi
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            9)
                while true; do
                    clear
                    echo "=========================================="
                    echo "     AUDITORÍA DE RED Y SEGURIDAD (NMAP)"
                    echo "=========================================="

                    if ! need nmap; then
                        pause_screen
                        break
                    fi

                    clear
                    echo "=========================================="
                    echo "     AUDITORÍA DE RED Y SEGURIDAD (NMAP)"
                    echo "=========================================="
                    echo "[STATUS] : INSTALADO Y OPERATIVO ($(nmap --version | head -n 1))"
                    echo "------------------------------------------"
                    echo " 1) Escaneo rápido de puertos abiertos en IP/Host"
                    echo " 2) Escaneo completo con detección de versiones (-sV)"
                    echo " 3) Escaneo agresivo (SO, versiones y scripts -A)"
                    echo " 4) Escaneo de red local (descubrimiento de hosts activos)"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-4 o q]: " nmap_opt

                    case $nmap_opt in
                        1)
                            echo ""
                            prompt_input "Ingresa la IP o hostname objetivo: " target_ip
                            if [[ -n "$target_ip" ]]; then
                                echo "[-] Ejecutando escaneo rápido en '$target_ip'..."
                                nmap -T4 "$target_ip"
                                log_action "Nmap: Escaneo rápido en $target_ip"
                            fi
                            pause_screen
                            ;;
                        2)
                            echo ""
                            prompt_input "Ingresa la IP o hostname objetivo: " target_ip
                            if [[ -n "$target_ip" ]]; then
                                echo "[-] Ejecutando detección de versiones (-sV) en '$target_ip'..."
                                sudo nmap -sV -T4 "$target_ip"
                                log_action "Nmap: Escaneo de versiones en $target_ip"
                            fi
                            pause_screen
                            ;;
                        3)
                            echo ""
                            prompt_input "Ingresa la IP o hostname objetivo: " target_ip
                            if [[ -n "$target_ip" ]]; then
                                echo "[-] Ejecutando escaneo agresivo (-A) en '$target_ip'..."
                                sudo nmap -A -T4 "$target_ip"
                                log_action "Nmap: Escaneo agresivo en $target_ip"
                            fi
                            pause_screen
                            ;;
                        4)
                            echo ""
                            prompt_input "Ingresa el rango de red (ej: 192.168.1.0/24): " target_net
                            if [[ -n "$target_net" ]]; then
                                echo "[-] Descubriendo hosts activos en '$target_net'..."
                                nmap -sn "$target_net"
                                log_action "Nmap: Ping scan en red $target_net"
                            fi
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            10)
                while true; do
                    clear
                    echo "=========================================="
                    echo "    DIAGNÓSTICO Y PRUEBAS DE RED AVANZADAS"
                    echo "=========================================="
                    echo "--- CONECTIVIDAD Y RESOLUCIÓN ---"
                    echo " 1) Test HTTP/HTTPS detallado (curl con cabeceras y tiempos)"
                    echo " 2) Prueba de conectividad ICMP avanzada (ping personalizable)"
                    echo " 3) Verificación de puerto remoto abierto (nc / /dev/tcp)"
                    echo " 4) Trazado de ruta (traceroute / tracepath)"
                    echo " 5) Resolución y consulta DNS (dig / nslookup)"
                    echo ""
                    echo "--- IDENTIDAD Y METADATOS DE RED ---"
                    echo " 6) IP pública y detalles (ficha técnica)"
                    echo " 7) WHOIS de dominio o IP (con autoinstalación)"
                    echo " 8) Certificado SSL de un dominio (ficha técnica)"
                    echo ""
                    echo "--- UTILIDADES WEB ---"
                    echo " 9) Verificar estado HTTP y tiempos (ficha técnica)"
                    echo "10) Acortar URL (tinyurl)"
                    echo "11) Test de velocidad de descarga (Cloudflare)"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-11 o q]: " net_adv_opt

                    case $net_adv_opt in
                        1)
                            echo ""
                            prompt_input "Ingresa la URL o IP objetivo (ej: https://google.com): " c_url
                            if [[ -n "$c_url" ]]; then
                                echo "[-] Ejecutando análisis HTTP detallado..."
                                echo "------------------------------------------"
                                curl -I -L -s --max-time 10 -w "\n[Métricas]\nTiempo total: %{time_total}s\nCódigo HTTP: %{http_code}\nIP Remota: %{remote_ip}\n" "$c_url"
                                log_action "Red Avanzada: Curl detallado a $c_url"
                            fi
                            pause_screen
                            ;;
                        2)
                            echo ""
                            prompt_input "Ingresa la IP o Dominio destino: " p_host
                            if [[ -n "$p_host" ]]; then
                                prompt_input "Cantidad de paquetes a enviar [Por defecto: 4]: " p_count
                                p_count="${p_count:-4}"
                                echo "[-] Enviando $p_count paquetes ICMP a '$p_host'..."
                                ping -c "$p_count" "$p_host"
                                log_action "Red Avanzada: Ping a $p_host ($p_count paquetes)"
                            fi
                            pause_screen
                            ;;
                        3)
                            echo ""
                            prompt_input "Ingresa la IP o Host remoto: " r_host
                            prompt_input "Ingresa el puerto a verificar (ej: 80, 443, 22): " r_port
                            if [[ -n "$r_host" && -n "$r_port" ]]; then
                                echo "[-] Probando conectividad hacia $r_host en el puerto $r_port..."
                                if command -v nc &>/dev/null; then
                                    nc -zv -w 3 "$r_host" "$r_port"
                                elif need nc netcat-openbsd; then
                                    nc -zv -w 3 "$r_host" "$r_port"
                                else
                                    if (echo >/dev/tcp/"$r_host"/"$r_port") &>/dev/null; then
                                        echo "[OK] Puerto $r_port en $r_host está ABIERTO y accesible."
                                    else
                                        echo "[!] No se pudo conectar al puerto $r_port en $r_host (Cerrado o filtrado)."
                                    fi
                                fi
                                log_action "Red Avanzada: Test puerto $r_port en $r_host"
                            fi
                            pause_screen
                            ;;
                        4)
                            echo ""
                            prompt_input "Ingresa la IP o Dominio para trazado de ruta: " t_host
                            if [[ -n "$t_host" ]]; then
                                echo "[-] Trazando ruta hacia $t_host..."
                                if command -v traceroute &>/dev/null; then
                                    traceroute "$t_host"
                                elif command -v tracepath &>/dev/null; then
                                    tracepath "$t_host"
                                elif need traceroute; then
                                    traceroute "$t_host"
                                else
                                    echo "[!] No hay herramienta de trazado disponible."
                                fi
                                log_action "Red Avanzada: Traceroute a $t_host"
                            fi
                            pause_screen
                            ;;
                        5)
                            echo ""
                            prompt_input "Ingresa el dominio a consultar (ej: google.com): " d_host
                            if [[ -n "$d_host" ]]; then
                                echo "[-] Resolviendo registros DNS para $d_host..."
                                if command -v dig &>/dev/null; then
                                    dig "$d_host" ANY +noall +answer
                                elif command -v nslookup &>/dev/null; then
                                    nslookup "$d_host"
                                elif need dnsutils bind-utils; then
                                    dig "$d_host" ANY +noall +answer
                                else
                                    getent ahosts "$d_host"
                                fi
                                log_action "Red Avanzada: Consulta DNS de $d_host"
                            fi
                            pause_screen
                            ;;
                        6)
                            echo ""
                            if need jq; then
                                echo "[-] Obteniendo información de red..."
                                local ip_json=$(ccurl "https://ipinfo.io/json")
                                local ip=$(echo "$ip_json" | jq -r '.ip // "N/A"')
                                local city=$(echo "$ip_json" | jq -r '.city // "N/A"')
                                local region=$(echo "$ip_json" | jq -r '.region // "N/A"')
                                local country=$(echo "$ip_json" | jq -r '.country // "N/A"')
                                local org=$(echo "$ip_json" | jq -r '.org // "N/A"')
                                local tz=$(echo "$ip_json" | jq -r '.timezone // "N/A"')
                                
                                echo ""
                                echo "┌──────────────────────────────────────────────────┐"
                                echo "│ FICHA TÉCNICA DE RED (IP PÚBLICA)                │"
                                echo "├──────────────────────────────────────────────────┤"
                                printf "│ IP Pública : %-36.36s │\n" "$ip"
                                printf "│ Ciudad     : %-36.36s │\n" "$city"
                                printf "│ Región     : %-36.36s │\n" "$region"
                                printf "│ País       : %-36.36s │\n" "$country"
                                printf "│ ISP / Org  : %-36.36s │\n" "$org"
                                printf "│ Zona Horaria: %-35.35s │\n" "$tz"
                                echo "└──────────────────────────────────────────────────┘"
                                
                                log_action "Red Avanzada: Ficha IP pública"
                            fi
                            pause_screen
                            ;;
                        7)
                            echo ""
                            prompt_input "Dominio o IP para WHOIS: " whois_target
                            if [[ -n "$whois_target" ]]; then
                                if need whois; then
                                    whois "$whois_target" | head -n 40
                                    log_action "Red Avanzada: WHOIS $whois_target"
                                fi
                            fi
                            pause_screen
                            ;;
                        8)
                            echo ""
                            prompt_input "Dominio para inspeccionar certificado SSL: " ssl_host
                            if [[ -n "$ssl_host" ]]; then
                                echo "[-] Consultando certificado de $ssl_host:443..."
                                
                                local ssl_out=$(echo | openssl s_client -servername "$ssl_host" -connect "$ssl_host:443" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null)
                                
                                if [[ -n "$ssl_out" ]]; then
                                    local subj=$(echo "$ssl_out" | grep "subject=" | sed 's/subject=//')
                                    local issu=$(echo "$ssl_out" | grep "issuer=" | sed 's/issuer=//')
                                    local not_b=$(echo "$ssl_out" | grep "notBefore=" | sed 's/notBefore=//')
                                    local not_a=$(echo "$ssl_out" | grep "notAfter=" | sed 's/notAfter=//')
                                    
                                    echo ""
                                    echo "┌──────────────────────────────────────────────────┐"
                                    echo "│ FICHA TÉCNICA DE CERTIFICADO SSL                 │"
                                    echo "├──────────────────────────────────────────────────┤"
                                    printf "│ Dominio    : %-36.36s │\n" "$ssl_host"
                                    printf "│ Subject    : %-36.36s │\n" "$subj"
                                    printf "│ Issuer     : %-36.36s │\n" "$issu"
                                    printf "│ Válido desde: %-35.35s │\n" "$not_b"
                                    printf "│ Válido hasta: %-35.35s │\n" "$not_a"
                                    echo "└──────────────────────────────────────────────────┘"
                                else
                                    echo "[!] No se pudo obtener el certificado (posible bloqueo de red o dominio inválido)."
                                fi
                                log_action "Red Avanzada: SSL cert $ssl_host"
                            fi
                            pause_screen
                            ;;
                        9)
                            echo ""
                            prompt_input "URL o host a verificar (ej: https://google.com): " check_url
                            if [[ -n "$check_url" ]]; then
                                [[ "$check_url" != http* ]] && check_url="https://$check_url"
                                echo "[-] Verificando estado HTTP..."
                                
                                local metrics=$(curl -s -o /dev/null -L -w \
                                    "%{http_code}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}" \
                                    --max-time 10 "$check_url")
                                
                                local code=$(echo "$metrics" | cut -d'|' -f1)
                                local t_dns=$(echo "$metrics" | cut -d'|' -f2)
                                local t_tcp=$(echo "$metrics" | cut -d'|' -f3)
                                local t_tls=$(echo "$metrics" | cut -d'|' -f4)
                                local t_ttfb=$(echo "$metrics" | cut -d'|' -f5)
                                local t_total=$(echo "$metrics" | cut -d'|' -f6)
                                
                                echo ""
                                echo "┌──────────────────────────────────────────────────┐"
                                echo "│ FICHA TÉCNICA HTTP                               │"
                                echo "├──────────────────────────────────────────────────┤"
                                printf "│ URL Objetivo: %-36.36s │\n" "$check_url"
                                printf "│ Código HTTP : %-36s │\n" "$code"
                                echo "├──────────────────────────────────────────────────┤"
                                printf "│ DNS Lookup  : %-32.4fs │\n" "$t_dns"
                                printf "│ TCP Connect : %-32.4fs │\n" "$t_tcp"
                                if [[ "$t_tls" != "0.000000" && "$t_tls" != "0.0000" ]]; then
                                    printf "│ TLS Handshake: %-31.4fs │\n" "$t_tls"
                                fi
                                printf "│ TTFB (1er byte): %-29.4fs │\n" "$t_ttfb"
                                printf "│ Tiempo Total: %-33.4fs │\n" "$t_total"
                                echo "└──────────────────────────────────────────────────┘"
                                
                                log_action "Red Avanzada: Check HTTP $check_url -> $code"
                            fi
                            pause_screen
                            ;;
                        10)
                            echo ""
                            if need jq; then
                                prompt_input "URL a acortar: " long_url
                                if [[ -n "$long_url" ]]; then
                                    echo "[-] Acortando URL..."
                                    ccurl "https://tinyurl.com/api-create.php?url=$(printf '%s' "$long_url" | jq -sRr @uri 2>/dev/null)"
                                    echo ""
                                    log_action "Red Avanzada: TinyURL generado"
                                fi
                            fi
                            pause_screen
                            ;;
                        11)
                            echo ""
                            echo "[-] Descargando 25MB de Cloudflare para medir velocidad..."
                            curl -o /dev/null -s --max-time 15 -w 'Velocidad media: %{speed_download} B/s (Tiempo: %{time_total}s)\n' \
                                -H "User-Agent: Mozilla/5.0" \
                                "https://speed.cloudflare.com/__down?bytes=25000000"
                            log_action "Red Avanzada: Speedtest Cloudflare"
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            q|[qQ])
                echo "¡Hasta luego, Leonardo! Cerrando dashboard."
                break
                ;;
        esac
    done
}

menu
