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
        echo "1) Herramientas de sistema nativas (grep, rsync, diff, journalctl)"
        echo "2) Monitoreo de recursos locales y disco (btop, ps top CPU/RAM)"
        echo "3) Servicios y Contenedores Docker (Avanzado)"
        echo "4) Mantenimiento de Sistema y Sincronización Git"
        echo "5) Utilidades Varias (Clima wttr.in, etc.)"
        echo "6) Herramientas de Automatización (Ansible, Terraform)"
        echo "7) Diagnóstico y Pruebas de Red (IP, Ping, DNS, Curl, SS)"
        echo "8) Auditoría de Red y Seguridad (Nmap)"
        echo "9) Salir (o presiona 'q')"
        echo "=========================================================="
        
        prompt_input "LEO-DASHBOARD > Elige una opción [1-9 o q]: " opt

        case $opt in
            1)
                while true; do
                    clear
                    echo "=========================================="
                    echo "     HERRAMIENTAS DE SISTEMA NATIVAS"
                    echo "=========================================="
                    echo "1) Análisis de logs y búsqueda (grep / egrep)"
                    echo "2) Inspección de servicios y logs del sistema (journalctl)"
                    echo "3) Conteo de líneas, palabras y bytes (wc)"
                    echo "4) Comparación de archivos y diferencias (diff)"
                    echo "5) Sincronización y respaldo rápido (rsync)"
                    echo "6) Resumen de espacio en disco (df -h)"
                    echo "7) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-7]: " nat_opt

                    case $nat_opt in
                        1)
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
                        2)
                            echo ""
                            echo "=========================================="
                            echo "       INSPECCIÓN CON JOURNALCTL"
                            echo "=========================================="
                            prompt_input "Nombre del servicio a consultar (ej: sshd, nginx, docker): " svc_name
                            if [[ -n "$svc_name" ]]; then
                                echo "[-] Mostrando últimas 30 líneas de registro para '$svc_name':"
                                journalctl -u "$svc_name" -n 30 --no-pager
                                log_action "Journalctl: Consulta de servicio $svc_name"
                            fi
                            pause_screen
                            ;;
                        3)
                            echo ""
                            prompt_input "Ruta del archivo a contar (wc): " wc_file
                            if [[ -f "$wc_file" ]]; then
                                echo "[-] Métricas del archivo (Líneas / Palabras / Bytes):"
                                wc "$wc_file"
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
                            echo "[-] Resumen de discos (df -h):"
                            df -h -x tmpfs -x devtmpfs
                            pause_screen
                            ;;
                        7) break ;;
                    esac
                done
                ;;
            2)
                while true; do
                    clear
                    echo "=========================================="
                    echo "   MONITOREO DE RECURSOS LOCALES Y DISCO"
                    echo "=========================================="
                    echo "1) Monitores interactivos de procesos (btop / htop / top)"
                    echo "2) Top procesos con mayor consumo de CPU (ps)"
                    echo "3) Top procesos con mayor consumo de Memoria (ps)"
                    echo "4) Diagnóstico tradicional de disco (df -h)"
                    echo "5) Visualizador visual de almacenamiento (duf)"
                    echo "6) Explorador interactivo de carpetas pesadas (ncdu)"
                    echo "7) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-7]: " sub_opt
                    case $sub_opt in
                        1)
                            echo ""
                            echo "1) btop (Monitor moderno)"
                            echo "2) htop (Monitor por procesos)"
                            echo "3) top (Monitor básico nativo)"
                            prompt_input "Selecciona monitor [1-3]: " m_opt
                            case $m_opt in
                                1) command -v btop &> /dev/null && btop || echo "[!] btop no instalado." ;;
                                2) command -v htop &> /dev/null && htop || echo "[!] htop no instalado." ;;
                                3) top ;;
                            esac
                            pause_screen
                            ;;
                        2)
                            echo ""
                            echo "[-] Top 10 procesos consumiendo más CPU:"
                            ps aux --sort=-%cpu | head -n 11
                            log_action "Monitoreo: Top procesos por CPU ejecutado."
                            pause_screen
                            ;;
                        3)
                            echo ""
                            echo "[-] Top 10 procesos consumiendo más Memoria:"
                            ps aux --sort=-%mem | head -n 11
                            log_action "Monitoreo: Top procesos por Memoria ejecutado."
                            pause_screen
                            ;;
                        4)
                            echo ""
                            echo "[-] Resumen de almacenamiento local (df):"
                            df -h -x tmpfs -x devtmpfs
                            pause_screen
                            ;;
                        5)
                            echo ""
                            if command -v duf &> /dev/null; then
                                duf
                            else
                                echo "[!] duf no está instalado."
                                prompt_input "¿Deseas instalar duf ahora? (s/n): " inst_duf
                                if [[ "$inst_duf" == "s" || "$inst_duf" == "S" ]]; then
                                    if command -v apt &> /dev/null; then
                                        sudo apt update && sudo apt install -y duf
                                    elif command -v dnf &> /dev/null; then
                                        sudo dnf install -y duf
                                    fi
                                    log_action "Instalación completada: duf."
                                fi
                            fi
                            pause_screen
                            ;;
                        6)
                            if command -v ncdu &> /dev/null; then
                                ncdu /
                            else
                                echo "[!] ncdu no está instalado."
                            fi
                            pause_screen
                            ;;
                        7) break ;;
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

                    if ! systemctl is-active --quiet docker 2>/dev/null; then
                        echo "[!] El servicio Docker no está activo en systemd."
                        pause_screen
                        break
                    fi

                    echo "1) Ver contenedores activos (docker ps)"
                    echo "2) Ver TODOS los contenedores (activos e inactivos)"
                    echo "3) Monitoreo de CPU/RAM en tiempo real (docker stats)"
                    echo "4) Inspeccionar logs de un contenedor (con fzf)"
                    echo "5) Iniciar / Detener / Reiniciar contenedor (con fzf)"
                    echo "6) Ver IP/Redes de un contenedor (docker inspect)"
                    echo "7) Ver uso de disco e imágenes guardadas"
                    echo "8) Mantenimiento / Limpieza (prune de contenedores e imágenes huérfanas)"
                    echo "9) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-9]: " d_opt

                    case $d_opt in
                        1)
                            echo ""
                            echo "[-] Contenedores en ejecución:"
                            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                            pause_screen
                            ;;
                        2)
                            echo ""
                            echo "[-] Listado completo de contenedores:"
                            docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
                            pause_screen
                            ;;
                        3)
                            echo ""
                            echo "[-] Monitoreo en vivo de consumo de CPU/RAM/RED (Ctrl+C para salir):"
                            sleep 1
                            docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
                            pause_screen
                            ;;
                        4)
                            echo ""
                            local target_cnt=""
                            if command -v fzf &> /dev/null; then
                                target_cnt=$(docker ps -a --format "{{.Names}}" | fzf --prompt="Selecciona contenedor para ver logs > ")
                            else
                                prompt_input "Nombre del contenedor: " target_cnt
                            fi

                            if [[ -n "$target_cnt" ]]; then
                                echo ""
                                echo "[-] Mostrando últimas 50 líneas de log para '$target_cnt' (Ctrl+C para salir):"
                                sleep 1
                                docker logs -f --tail 50 "$target_cnt"
                                log_action "Docker: Consulta de logs en $target_cnt."
                            fi
                            pause_screen
                            ;;
                        5)
                            echo ""
                            local action_cnt=""
                            if command -v fzf &> /dev/null; then
                                action_cnt=$(docker ps -a --format "{{.Names}}" | fzf --prompt="Selecciona contenedor a gestionar > ")
                            else
                                prompt_input "Nombre del contenedor: " action_cnt
                            fi

                            if [[ -n "$action_cnt" ]]; then
                                echo ""
                                echo "Gestión para '$action_cnt':"
                                echo "1) Reiniciar (restart)"
                                echo "2) Detener (stop)"
                                echo "3) Iniciar (start)"
                                prompt_input "Selecciona acción [1-3]: " act_choice
                                case $act_choice in
                                    1) sudo docker restart "$action_cnt" && log_action "Docker: Restart $action_cnt" ;;
                                    2) sudo docker stop "$action_cnt" && log_action "Docker: Stop $action_cnt" ;;
                                    3) sudo docker start "$action_cnt" && log_action "Docker: Start $action_cnt" ;;
                                esac
                            fi
                            pause_screen
                            ;;
                        6)
                            echo ""
                            local inspect_cnt=""
                            if command -v fzf &> /dev/null; then
                                inspect_cnt=$(docker ps -a --format "{{.Names}}" | fzf --prompt="Selecciona contenedor a inspeccionar > ")
                            else
                                prompt_input "Nombre del contenedor: " inspect_cnt
                            fi

                            if [[ -n "$inspect_cnt" ]]; then
                                echo ""
                                echo "[-] IP y Redes asignadas a '$inspect_cnt':"
                                docker inspect --format '{{range .NetworkSettings.Networks}}IP: {{.IPAddress}} | Gateway: {{.Gateway}} {{end}}' "$inspect_cnt"
                            fi
                            pause_screen
                            ;;
                        7)
                            echo ""
                            echo "[-] Imágenes locales:"
                            docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
                            echo ""
                            echo "[-] Uso global de recursos de Docker:"
                            docker system df
                            log_action "Docker: Consulta de espacio e imágenes."
                            pause_screen
                            ;;
                        8)
                            echo ""
                            echo "[!] Limpieza de elementos en desuso en Docker..."
                            prompt_input "¿Deseas ejecutar 'docker system prune -f'? (s/n): " confirm_prune
                            if [[ "$confirm_prune" == "s" || "$confirm_prune" == "S" ]]; then
                                sudo docker system prune -f
                                log_action "Docker: Executed docker system prune."
                            fi
                            pause_screen
                            ;;
                        9) break ;;
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
                            local update_date=$(date +'%Y%m%d_%H%M%S')
                            local log_dir="$HOME/.local/bin/scripts/logs"
                            mkdir -p "$log_dir"
                            local update_log="$log_dir/update_$update_date.log"
                            
                            if command -v apt &> /dev/null; then
                                echo "[-] Actualizando con apt (Detalle en $update_log)..."
                                { sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y; } > "$update_log" 2>&1
                            elif command -v dnf &> /dev/null; then
                                echo "[-] Actualizando con dnf omitiendo conflictos (Detalle en $update_log)..."
                                { sudo dnf upgrade -y --skip-broken --nobest && sudo dnf autoremove -y; } > "$update_log" 2>&1
                            fi
                            echo "[OK] Proceso finalizado."
                            pause_screen
                            ;;
                        2)
                            cd ~/.local/bin/scripts || exit 1
                            git pull
                            pause_screen
                            ;;
                        3) break ;;
                    esac
                done
                ;;
            5)
                while true; do
                    clear
                    echo "=========================================="
                    echo "            UTILIDADES VARIAS"
                    echo "=========================================="
                    echo "1) Clima actual (wttr.in)"
                    echo "2) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-2]: " sub_opt
                    case $sub_opt in
                        1)
                            echo ""
                            echo "[-] Consultando wttr.in..."
                            curl -s "wttr.in?lang=es"
                            pause_screen
                            ;;
                        2) break ;;
                    esac
                done
                ;;
            6)
                while true; do
                    clear
                    echo "=========================================="
                    echo "     AUTOMATIZACIÓN E INFRAESTRUCTURA"
                    echo "=========================================="
                    echo "1) Diagnóstico / Instalación de Ansible"
                    echo "2) Diagnóstico / Instalación de Terraform"
                    echo "3) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-3]: " auto_opt

                    case $auto_opt in
                        1)
                            echo ""
                            echo "=========================================="
                            echo "           DIAGNÓSTICO DE ANSIBLE"
                            echo "=========================================="
                            if command -v ansible &> /dev/null; then
                                echo "[STATUS] : INSTALADO Y OPERATIVO"
                                echo "Ruta binary  : $(which ansible)"
                                echo "Versión      : $(ansible --version | head -n 1)"
                                echo "Python Ver   : $(ansible --version | grep 'python version')"
                                echo "Config File  : $(ansible --version | grep 'config file')"
                                echo ""
                                echo "[-] Búsqueda rápida de Playbooks y Roles en $HOME:"
                                local pb_files=$(find $HOME -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | grep -iE 'playbook|ansible' | head -n 10)
                                if [[ -n "$pb_files" ]]; then
                                    echo "$pb_files"
                                else
                                    echo "[i] No se detectaron archivos de playbook evidentes en $HOME."
                                fi
                            else
                                echo "[STATUS] : NO INSTALADO"
                                echo ""
                                prompt_input "¿Deseas instalar Ansible ahora? (s/n): " inst_ansible
                                if [[ "$inst_ansible" == "s" || "$inst_ansible" == "S" ]]; then
                                    echo "[-] Instalando Ansible..."
                                    if command -v apt &> /dev/null; then
                                        sudo apt update && sudo apt install -y ansible
                                    elif command -v dnf &> /dev/null; then
                                        sudo dnf install -y ansible-core || sudo dnf install -y ansible
                                    fi
                                    log_action "Instalación completada: Ansible."
                                fi
                            fi
                            log_action "Diagnóstico Ansible ejecutado."
                            pause_screen
                            ;;
                        2)
                            echo ""
                            echo "=========================================="
                            echo "          DIAGNÓSTICO DE TERRAFORM"
                            echo "=========================================="
                            if command -v terraform &> /dev/null; then
                                echo "[STATUS] : INSTALADO Y OPERATIVO"
                                echo "Ruta binary  : $(which terraform)"
                                echo "Versión      : $(terraform version | head -n 1)"
                                echo ""
                                echo "[-] Búsqueda rápida de proyectos Terraform (.tf) en $HOME:"
                                local tf_files=$(find $HOME -type f -name "*.tf" 2>/dev/null | head -n 10)
                                if [[ -n "$tf_files" ]]; then
                                    echo "$tf_files"
                                else
                                    echo "[i] No se detectaron archivos .tf en $HOME."
                                fi
                            else
                                echo "[STATUS] : NO INSTALADO"
                                echo ""
                                prompt_input "¿Deseas instalar Terraform (HashiCorp Repo) ahora? (s/n): " inst_tf
                                if [[ "$inst_tf" == "s" || "$inst_tf" == "S" ]]; then
                                    echo "[-] Configurando repositorio oficial e instalando Terraform..."
                                    if command -v dnf &> /dev/null; then
                                        sudo dnf install -y dnf-plugins-core
                                        sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
                                        sudo dnf install -y terraform
                                    elif command -v apt &> /dev/null; then
                                        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
                                        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                                        sudo apt update && sudo apt install -y terraform
                                    fi
                                    log_action "Instalación completada: Terraform."
                                fi
                            fi
                            log_action "Diagnóstico Terraform ejecutado."
                            pause_screen
                            ;;
                        3) break ;;
                    esac
                done
                ;;
            7)
                while true; do
                    clear
                    echo "=========================================="
                    echo "    DIAGNÓSTICO Y PRUEBAS DE RED LOCAL"
                    echo "=========================================="
                    echo "1) Direcciones IP y Rutas de red (ip a / ip route)"
                    echo "2) Prueba de latencia y conectividad (ping)"
                    echo "3) Trazado de ruta hacia host/IP (traceroute / tracepath)"
                    echo "4) Diagnóstico HTTP/HTTPS y cabeceras (curl)"
                    echo "5) Verificación y resolución DNS (nslookup / dig / resolv.conf)"
                    echo "6) Puertos locales escuchando en el sistema (ss -tulpn)"
                    echo "7) Volver al menú principal"
                    echo "=========================================="
                    prompt_input "Elige una opción [1-7]: " net_opt

                    case $net_opt in
                        1)
                            echo ""
                            echo "[-] Interfaces de red y direcciones IP:"
                            ip -brief address
                            echo ""
                            echo "[-] Tabla de ruteo por defecto:"
                            ip route
                            pause_screen
                            ;;
                        2)
                            echo ""
                            prompt_input "Ingresa la IP o Dominio a probar (ej: 8.8.8.8 o google.com): " ping_target
                            if [[ -n "$ping_target" ]]; then
                                echo "[-] Enviando 4 paquetes ICMP a '$ping_target'..."
                                ping -c 4 "$ping_target"
                                log_action "Red: Ping ejecutado hacia $ping_target"
                            fi
                            pause_screen
                            ;;
                        3)
                            echo ""
                            prompt_input "Ingresa la IP o Dominio a trazar: " trace_target
                            if [[ -n "$trace_target" ]]; then
                                if command -v traceroute &> /dev/null; then
                                    traceroute "$trace_target"
                                elif command -v tracepath &> /dev/null; then
                                    tracepath "$trace_target"
                                else
                                    echo "[!] Ni traceroute ni tracepath están instalados."
                                fi
                                log_action "Red: Traceroute a $trace_target"
                            fi
                            pause_screen
                            ;;
                        4)
                            echo ""
                            prompt_input "Ingresa la URL objetivo (ej: https://google.com): " curl_target
                            if [[ -n "$curl_target" ]]; then
                                echo "[-] Obteniendo cabeceras HTTP y código de respuesta..."
                                curl -I -L -s "$curl_target" | head -n 20
                                log_action "Red: Curl cabeceras en $curl_target"
                            fi
                            pause_screen
                            ;;
                        5)
                            echo ""
                            echo "[-] Servidores DNS configurados (/etc/resolv.conf):"
                            cat /etc/resolv.conf | grep nameserver
                            echo ""
                            prompt_input "Ingresa un dominio a resolver (ej: google.com): " dns_target
                            if [[ -n "$dns_target" ]]; then
                                if command -v dig &> /dev/null; then
                                    dig +short "$dns_target"
                                elif command -v nslookup &> /dev/null; then
                                    nslookup "$dns_target"
                                else
                                    getent ahosts "$dns_target"
                                fi
                                log_action "Red: Consulta DNS de $dns_target"
                            fi
                            pause_screen
                            ;;
                        6)
                            echo ""
                            echo "[-] Puertos TCP/UDP en escucha activa:"
                            sudo ss -tulpn | grep LISTEN
                            pause_screen
                            ;;
                        7) break ;;
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
