#!/usr/bin/env zsh

# ==============================================================================
#  PROMETHERION2112 - SYSADMIN TOOLKIT & DASHBOARD
#  Repositorio: git@github.com:leocampos81/scripts.git
# ==============================================================================

log_action() {
    local log_file="$HOME/.local/bin/scripts/sysadmin.log"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$log_file"
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
    read -r
}

prompt_input() {
    local prompt_msg="$1"
    local var_name="$2"
    
    local old_stty=$(stty -g 2>/dev/null)
    stty erase '^?' erase '^H' 2>/dev/null
    
    echo -n "$prompt_msg"
    read -r "$var_name"
    
    stty "$old_stty" 2>/dev/null
}

menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                                                                  ║"
        echo "║                  P R O M E T H E R I O N  2 1 1 2                  ║"
        echo "║                 S Y S A D M I N   D A S H B O A R D              ║"
        echo "║                                                                  ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        local sistema_actual=$(get_os_info)
        echo "[*] Usuario Activo : $USER@$(hostname)"
        echo "[*] Servidor actual: $sistema_actual"
        echo "=========================================================="
        echo "1) Herramientas Nativas del Sistema (Archivos, Servicios, Red, Monitoreo)"
        echo "2) Monitoreo Avanzado de Recursos (btop, ps top CPU/RAM)"
        echo "3) Servicios y Contenedores Docker (Avanzado)"
        echo "4) Mantenimiento de Sistema y Sincronización Git"
        echo "5) Utilidades Varias (Clima wttr.in, etc.)"
        echo "6) Herramientas de Automatización (Ansible, Terraform)"
        echo "7) Diagnóstico y Pruebas de Red Avanzadas"
        echo "8) Auditoría de Red y Seguridad (Nmap)"
        echo "9) Salir (o presiona 'q')"
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
                    echo "1) Editar archivos (nvim / nano / vi)"
                    echo "2) Búsqueda y filtrado de texto (grep / egrep)"
                    echo "3) Información y metadatos de archivo (stat, file, wc)"
                    echo "4) Comparación de archivos (diff)"
                    echo "5) Resguardo rápido (rsync)"
                    echo ""
                    echo "--- SERVICIOS Y LOGS (SYSTEMCTL / JOURNALCTL) ---"
                    echo "6) Gestión de servicios systemctl (con autolistado de activos)"
                    echo "7) Inspección de logs journalctl (con autolistado de servicios)"
                    echo ""
                    echo "--- RECURSOS, DISCOS Y RED NATIVA ---"
                    echo "8) Recursos locales y procesos en vivo (top, ps CPU/RAM, free)"
                    echo "9) Almacenamiento y particiones (df -h)"
                    echo "10) Red básica e interfaces (ip a, ip route, ss ports, ping)"
                    echo "11) Volver al menú principal"
                    echo "=========================================================="
                    prompt_input "Elige una opción [1-11]: " nat_opt

                    case $nat_opt in
                        1)
                            echo ""
                            echo "=========================================="
                            echo "        EDITOR DE ARCHIVOS LOCALES"
                            echo "=========================================="
                            echo "1) nvim"
                            echo "2) nano"
                            echo "3) vi"
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
                            echo "=========================================="
                            echo "      INFORMACIÓN DETALLADA DE ARCHIVO"
                            echo "=========================================="
                            prompt_input "Ruta del archivo a analizar: " info_file
                            if [[ -f "$info_file" ]]; then
                                echo ""
                                echo "--- TIPO Y CODIFICACIÓN (file) ---"
                                file "$info_file"
                                echo ""
                                echo "--- METADATOS Y ESTADO (stat) ---"
                                stat "$info_file"
                                echo ""
                                echo "--- MÉTRICAS (Líneas / Palabras / Bytes - wc) ---"
                                wc "$info_file"
                                log_action "Info: Análisis detallado de $info_file"
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
                            prompt_input "Directorio o archivo origen: " r_src
                            prompt_input "Directorio o host destino: " r_dst
                            if [[ -n "$r_src" && -n "$r_dst" ]]; then
                                echo "[-] Ejecutando 'rsync -avh --progress':"
                                rsync -avh --progress "$r_src" "$r_dst"
                                log_action "Rsync: $r_src hacia $r_dst"
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
                                echo "1) Consultar estado (status)"
                                echo "2) Iniciar servicio (start)"
                                echo "3) Reiniciar servicio (restart)"
                                echo "4) Detener servicio (stop)"
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
                            echo "1) Top 10 procesos por CPU"
                            echo "2) Top 10 procesos por Memoria"
                            echo "3) Memoria RAM y Swap en uso (free -h)"
                            echo "4) Monitor interactivo básico (top)"
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
                            echo "1) Direcciones IP e interfaces (ip a)"
                            echo "2) Tabla de ruteo (ip route)"
                            echo "3) Puertos locales en escucha (ss -tulpn)"
                            echo "4) Prueba rápida de conectividad (ping)"
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
                        11) break ;;
                    esac
                done
                ;;
            2)
                while true; do
                    clear
                    echo "=========================================="
                    echo "   MONITOREO AVANZADO DE RECURSOS"
                    echo "=========================================="
                    echo "1) btop (Monitor moderno)"
                    echo "2) htop (Monitor por procesos)"
                    echo "3) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-3]: " sub_opt
                    case $sub_opt in
                        1) command -v btop &> /dev/null && btop || echo "[!] btop no instalado." ;;
                        2) command -v htop &> /dev/null && htop || echo "[!] htop no instalado." ;;
                        3) break ;;
                    esac
                done
                ;;
            3)
                while true; do
                    clear
                    echo "=========================================="
                    echo "      GESTIÓN Y ESTADO DE DOCKER LAB"
                    echo "=========================================="
                    if ! command -v docker &> /dev/null; then
                        echo "[!] Docker no está instalado en este sistema."
                        pause_screen
                        break
                    fi

                    echo "1) Ver contenedores activos (docker ps)"
                    echo "2) Monitoreo de CPU/RAM en tiempo real (docker stats)"
                    echo "3) Inspeccionar logs de un contenedor"
                    echo "4) Reiniciar / Detener / Iniciar contenedor"
                    echo "5) Limpieza general (docker system prune)"
                    echo "6) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-6]: " d_opt

                    case $d_opt in
                        1)
                            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                            pause_screen
                            ;;
                        2)
                            docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
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
                        6) break ;;
                    esac
                done
                ;;
            4)
                while true; do
                    clear
                    echo "=========================================="
                    echo "   MANTENIMIENTO Y SINCRONIZACIÓN GIT"
                    echo "=========================================="
                    echo "1) Actualizar paquetes de sistema (apt/dnf)"
                    echo "2) Sincronizar repositorio de scripts (Git Pull/Push)"
                    echo "3) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-3]: " sub_opt
                    case $sub_opt in
                        1)
                            if command -v apt &> /dev/null; then
                                sudo apt update && sudo apt dist-upgrade -y
                            elif command -v dnf &> /dev/null; then
                                sudo dnf upgrade -y --skip-broken
                            fi
                            pause_screen
                            ;;
                        2)
                            cd ~/.local/bin/scripts || exit 1
                            git status -s
                            echo ""
                            echo "1) git pull | 2) git push"
                            prompt_input "Acción [1-2]: " g_act
                            if [[ "$g_act" == "1" ]]; then
                                git pull origin main
                            elif [[ "$g_act" == "2" ]]; then
                                local default_msg="Actualiza prom.sh"
                                prompt_input "Mensaje para commit [Default: '$default_msg']: " git_msg
                                git_msg="${git_msg:-$default_msg}"
                                git add . && git commit -m "$git_msg" && git push origin main
                            fi
                            pause_screen
                            ;;
                        3) break ;;
                    esac
                done
                ;;
            5)
                curl -s "wttr.in?lang=es"
                pause_screen
                ;;
            6)
                echo "1) Ansible Status | 2) Terraform Status"
                prompt_input "Elige [1-2]: " aut_opt
                case $aut_opt in
                    1) command -v ansible &> /dev/null && ansible --version || echo "Ansible no instalado" ;;
                    2) command -v terraform &> /dev/null && terraform version || echo "Terraform no instalado" ;;
                esac
                pause_screen
                ;;
            7)
                while true; do
                    clear
                    echo "=========================================="
                    echo "    DIAGNÓSTICO Y PRUEBAS DE RED AVANZADAS"
                    echo "=========================================="
                    echo "1) Test HTTP/HTTPS detallado (curl con cabeceras y tiempos)"
                    echo "2) Prueba de conectividad ICMP avanzada (ping con conteo personalizable)"
                    echo "3) Verificación de puerto remoto abierto (nc / /dev/tcp)"
                    echo "4) Trazado de ruta (traceroute / tracepath)"
                    echo "5) Resolución y consulta DNS (dig / nslookup)"
                    echo "6) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-6]: " net_adv_opt

                    case $net_adv_opt in
                        1)
                            echo ""
                            prompt_input "Ingresa la URL o IP objetivo (ej: https://google.com): " c_url
                            if [[ -n "$c_url" ]]; then
                                echo "[-] Ejecutando análisis HTTP detallado..."
                                echo "------------------------------------------"
                                curl -I -L -s -w "\n[Métricas]\nTiempo total: %{time_total}s\nCódigo HTTP: %{http_code}\nIP Remota: %{remote_ip}\n" "$c_url"
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
                                if command -v nc &> /dev/null; then
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
                                if command -v traceroute &> /dev/null; then
                                    traceroute "$t_host"
                                elif command -v tracepath &> /dev/null; then
                                    tracepath "$t_host"
                                else
                                    echo "[!] Ni traceroute ni tracepath están instalados."
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
                                if command -v dig &> /dev/null; then
                                    dig "$d_host" ANY +noall +answer
                                elif command -v nslookup &> /dev/null; then
                                    nslookup "$d_host"
                                else
                                    getent ahosts "$d_host"
                                fi
                                log_action "Red Avanzada: Consulta DNS de $d_host"
                            fi
                            pause_screen
                            ;;
                        6) break ;;
                    esac
                done
                ;;
            8)
                while true; do
                    clear
                    echo "=========================================="
                    echo "     AUDITORÍA DE RED Y SEGURIDAD (NMAP)"
                    echo "=========================================="
                    
                    if ! command -v nmap &> /dev/null; then
                        echo "[!] nmap no está instalado en este sistema."
                        echo ""
                        prompt_input "¿Deseas instalar nmap ahora? (s/n): " inst_nmap
                        if [[ "$inst_nmap" == "s" || "$inst_nmap" == "S" ]]; then
                            echo "[-] Instalando nmap..."
                            if command -v apt &> /dev/null; then
                                sudo apt update && sudo apt install -y nmap
                            elif command -v dnf &> /dev/null; then
                                sudo dnf install -y nmap
                            fi
                            log_action "Instalación completada: nmap."
                        else
                            pause_screen
                            break
                        fi
                    fi

                    clear
                    echo "=========================================="
                    echo "     AUDITORÍA DE RED Y SEGURIDAD (NMAP)"
                    echo "=========================================="
                    echo "[STATUS] : INSTALADO Y OPERATIVO ($(nmap --version | head -n 1))"
                    echo "------------------------------------------"
                    echo "1) Escaneo rápido de puertos abiertos en IP/Host"
                    echo "2) Escaneo completo con detección de versiones (-sV)"
                    echo "3) Escaneo agresivo (SO, versiones y scripts -A)"
                    echo "4) Escaneo de red local (descubrimiento de hosts activos)"
                    echo "5) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-5]: " nmap_opt

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
                        5) break ;;
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
