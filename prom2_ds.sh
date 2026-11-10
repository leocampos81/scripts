#!/usr/bin/env zsh

# ==============================================================================
#  PROMETHERION2112 - SYSADMIN TOOLKIT & DASHBOARD  (v3.2 - ds edition)
#  Repositorio: git@github.com:leocampos81/scripts.git
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
        echo " 1) Herramientas Nativas del Sistema (Archivos, Servicios, Red, Monitoreo)"
        echo " 2) Monitoreo Avanzado de Recursos (btop, ps top CPU/RAM)"
        echo " 3) Servicios y Contenedores Docker (Avanzado)"
        echo " 4) Mantenimiento de Sistema y Sincronización Git"
        echo " 5) Utilidades Locales y Consultas (Clima, QR, Credenciales)"
        echo " 6) Herramientas de Automatización (Ansible, Terraform)"
        echo " 7) Diagnóstico y Pruebas de Red Avanzadas"
        echo " 8) Auditoría de Red y Seguridad (Nmap)"
        echo ""
        echo " 9) Salir (o presiona 'q')"
        echo "=========================================================="

        prompt_input "LEO-DASHBOARD > Elige una opción [1-9 o q]: " opt

        case $opt in
            1)
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
                    echo " 9) Almacenamiento y particiones (df -h)"
                    echo "10) Red básica e interfaces (ip a, ip route, ss ports, ping)"
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
                                # --- BLOQUE 1: Identidad y Permisos ---
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

                                # --- BLOQUE 2: Fechas de Estado (stat) ---
                                echo ""
                                echo "┌──────────────────────────────────────────────────┐"
                                echo "│ FECHAS DE ESTADO                                 │"
                                echo "├──────────────────────────────────────────────────┤"
                                stat -c "│ Modificado : %-36s │" "%y"
                                stat -c "│ Accedido   : %-36s │" "%x"
                                # Algunos sistemas de archivos no guardan la fecha de creación
                                local f_create=$(stat -c "%w" "$info_file")
                                if [[ "$f_create" == "-" ]]; then
                                    printf "│ Creado     : %-36s │\n" "No disponible (FS)"
                                else
                                    printf "│ Creado     : %-36s │\n" "$f_create"
                                fi
                                echo "└──────────────────────────────────────────────────┘"

                                # --- BLOQUE 3: Métricas de Contenido (WC + Análisis) ---
                                echo ""
                                local wc_data=($(wc -l -w -c -m "$info_file"))
                                local wc_lines=${wc_data[1]}
                                local wc_words=${wc_data[2]}
                                local wc_bytes=${wc_data[3]}
                                local wc_chars=${wc_data[4]}
                                
                                # Análisis extra: Longitud de la línea más larga y líneas vacías
                                local awk_out=$(awk '{ 
                                    if (length($0) > max) max = length($0); 
                                    if (length($0) == 0) empty++; 
                                } END { print max+0, empty+0 }' "$info_file")
                                
                                local max_line_len=$(echo "$awk_out" | awk '{print $1}')
                                local empty_lines=$(echo "$awk_out" | awk '{print $2}')
                                
                                # Calcular promedio de palabras por línea
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
                            echo "[-] Almacenamiento en disco (df -h):"
                            df -h -x tmpfs -x devtmpfs
                            pause_screen
                            ;;
                        10)
                            echo ""
                            echo "=========================================="
                            echo "           RED Y CONECTIVIDAD BÁSICA"
                            echo "=========================================="
                            echo " 1) Direcciones IP e interfaces (ip a)"
                            echo " 2) Tabla de ruteo (ip route)"
                            echo " 3) Puertos locales en escucha (ss -tulpn)"
                            echo " 4) Prueba rápida de conectividad (ping)"
                            prompt_input "Selecciona opción [1-4]: " net_choice
                            case $net_choice in
                                1) ip -brief address ;;
                                2) ip route ;;
                                3) sudo ss -tulpn | grep LISTEN ;;
                                4)
                                    prompt_input "Ingresa IP o host de prueba: " p_target
                                    [[ -n "$p_target" ]] && ping -c 4 "$p_target"
                                    ;;
                            esac
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            2)
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
            3)
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
            4)
                while true; do
                    clear
                    echo "=========================================="
                    echo "   MANTENIMIENTO Y SINCRONIZACIÓN GIT"
                    echo "=========================================="
                    echo " 1) Actualizar paquetes de sistema (apt/dnf/pacman/zypper/apk)"
                    echo " 2) Sincronizar repositorio de scripts (Git Pull/Push)"
                    echo ""
                    echo " q) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-2 o q]: " sub_opt
                    case $sub_opt in
                        1)
                            if [[ "$PKG_MGR" != "unknown" ]]; then
                                echo "[-] Actualizando sistema con $PKG_MGR..."
                                eval "$PKG_UPDATE"
                                case "$PKG_MGR" in
                                    apt) sudo apt dist-upgrade -y ;;
                                    dnf) sudo dnf upgrade -y --skip-broken ;;
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
                            if ! cd "$REPO_DIR"; then
                                echo "[!] No se encontró el repositorio en $REPO_DIR"
                                pause_screen
                                continue
                            fi
                            git status -s
                            echo ""
                            echo "1) git pull | 2) git push"
                            prompt_input "Acción [1-2]: " g_act
                            if [[ "$g_act" == "1" ]]; then
                                git pull
                            elif [[ "$g_act" == "2" ]]; then
                                local default_msg="Actualiza prom.sh"
                                prompt_input "Mensaje para commit [Default: '$default_msg']: " git_msg
                                git_msg="${git_msg:-$default_msg}"
                                git add . && git commit -m "$git_msg" && git push
                            fi
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
            6)
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
            7)
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
                    echo " 6) IP pública y detalles (ifconfig.me / ipinfo.io)"
                    echo " 7) WHOIS de dominio o IP (con autoinstalación)"
                    echo " 8) Certificado SSL de un dominio"
                    echo ""
                    echo "--- UTILIDADES WEB ---"
                    echo " 9) Verificar estado HTTP de un sitio"
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
                            echo "[-] IP Pública (ifconfig.me):"
                            ccurl "https://ifconfig.me" || ccurl "https://api.ipify.org"
                            echo ""
                            echo ""
                            echo "--- Detalles geográficos (ipinfo.io) ---"
                            ccurl "https://ipinfo.io/json"
                            echo ""
                            log_action "Red Avanzada: IP pública"
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
                                echo | openssl s_client -servername "$ssl_host" -connect "$ssl_host:443" 2>/dev/null \
                                    | openssl x509 -noout -subject -issuer -dates
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
                                code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 -L "$check_url")
                                echo "Código HTTP: $code"
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
                            echo "[-] Descargando 100MB de Cloudflare para medir velocidad..."
                            curl -o /dev/null -s --max-time 30 -w 'Velocidad media: %{speed_download} B/s\n' \
                                "https://speed.cloudflare.com/__down?bytes=100000000"
                            log_action "Red Avanzada: Speedtest Cloudflare"
                            pause_screen
                            ;;
                        q|[qQ]) break ;;
                    esac
                done
                ;;
            8)
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
            9|[qQ])
                echo "¡Hasta luego, Leonardo! Cerrando dashboard."
                break
                ;;
        esac
    done
}

menu
