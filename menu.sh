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
        echo "=========================================================="
        echo "1) Herramientas de sistema externas (dnsglobe, fzf, etc.)"
        echo "2) Monitoreo de recursos locales y disco (btop, df, duf, ncdu)"
        echo "3) Servicios y Contenedores Docker (Avanzado)"
        echo "4) Mantenimiento de Sistema y Sincronización Git"
        echo "5) Utilidades Varias (Clima wttr.in, etc.)"
        echo "6) Herramientas de Automatización (Ansible, Terraform)"
        echo "7) Diagnóstico y Pruebas de Red (IP, Ping, Traceroute, Curl)"
        echo "8) Auditoría de Red y Seguridad (Nmap)"
        echo "9) Salir (o presiona 'q')"
        echo "=========================================================="
        
        echo -n "LEO-DASHBOARD > Elige una opción [1-9 o q]: "
        read -r opt

        case $opt in
            1)
                while true; do
                    clear
                    echo "=========================================="
                    echo "   HERRAMIENTAS DE SISTEMA EXTERNAS"
                    echo "=========================================="
                    echo "1) dnsglobe (Buscador y explorador de DNS)"
                    echo "2) fzf (Buscador difuso para terminal)"
                    echo "3) Volver al menú principal"
                    echo "=========================================="
                    echo -n "Elige una opción [1-3]: "
                    read -r sub_opt
                    case $sub_opt in
                        1)
                            echo ""
                            echo "[-] Verificando el estado de dnsglobe..."
                            if command -v dnsglobe &> /dev/null; then
                                echo "[OK] dnsglobe ya está instalado y operativo."
                                log_action "Verificación: dnsglobe ya estaba instalado."
                            else
                                echo "[!] dnsglobe no encontrado."
                                read -r "inst_dns?¿Deseas instalar dnsglobe ahora vía Cargo/Script? (s/n): "
                                if [[ "$inst_dns" == "s" || "$inst_dns" == "S" ]]; then
                                    curl --proto '=https' --tlsv1.2 -LsSf https://github.com/514-labs/dnsglobe/releases/download/v0.3.0/dnsglobe-installer.sh | sh
                                    echo "[OK] Instalación de dnsglobe finalizada."
                                    log_action "Instalación completada: dnsglobe vía curl."
                                fi
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        2)
                            echo ""
                            echo "[-] Verificando el estado de fzf..."
                            if command -v fzf &> /dev/null; then
                                echo "[OK] fzf ya está instalado y operativo."
                                log_action "Verificación: fzf ya estaba instalado."
                            else
                                echo "[!] fzf no encontrado."
                                read -r "inst_fzf?¿Deseas instalar fzf ahora? (s/n): "
                                if [[ "$inst_fzf" == "s" || "$inst_fzf" == "S" ]]; then
                                    if command -v apt &> /dev/null; then
                                        sudo apt update && sudo apt install -y fzf
                                    elif command -v dnf &> /dev/null; then
                                        sudo dnf install -y fzf
                                    fi
                                    log_action "Instalación completada: fzf."
                                fi
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        3) break ;;
                    esac
                done
                ;;
            2)
                while true; do
                    clear
                    echo "=========================================="
                    echo "   MONITOREO DE RECURSOS LOCALES Y DISCO"
                    echo "=========================================="
                    echo "1) Monitores de procesos (btop / htop / top)"
                    echo "2) Diagnóstico de disco tradicional (df -h)"
                    echo "3) Visualizador visual de almacenamiento (duf)"
                    echo "4) Explorador interactivo de carpetas pesadas (ncdu)"
                    echo "5) Volver al menú principal"
                    echo "=========================================="
                    echo -n "Elige una opción [1-5]: "
                    read -r sub_opt
                    case $sub_opt in
                        1)
                            echo ""
                            echo "1) btop (Monitor moderno)"
                            echo "2) htop (Monitor por procesos)"
                            echo "3) top (Monitor básico nativo)"
                            echo -n "Selecciona monitor [1-3]: "
                            read -r m_opt
                            case $m_opt in
                                1) command -v btop &> /dev/null && btop || echo "[!] btop no instalado." ;;
                                2) command -v htop &> /dev/null && htop || echo "[!] htop no instalado." ;;
                                3) top ;;
                            esac
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        2)
                            echo ""
                            echo "[-] Resumen de almacenamiento local (df):"
                            df -h -x tmpfs -x devtmpfs
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        3)
                            echo ""
                            if command -v duf &> /dev/null; then
                                duf
                            else
                                echo "[!] duf no está instalado."
                                read -r "inst_duf?¿Deseas instalar duf ahora? (s/n): "
                                if [[ "$inst_duf" == "s" || "$inst_duf" == "S" ]]; then
                                    if command -v apt &> /dev/null; then
                                        sudo apt update && sudo apt install -y duf
                                    elif command -v dnf &> /dev/null; then
                                        sudo dnf install -y duf
                                    fi
                                    log_action "Instalación completada: duf."
                                fi
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        4)
                            if command -v ncdu &> /dev/null; then
                                ncdu /
                            else
                                echo "[!] ncdu no está instalado."
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        5) break ;;
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
                        read -r "?Presiona Enter para volver..."
                        break
                    fi

                    if ! systemctl is-active --quiet docker 2>/dev/null; then
                        echo "[!] El servicio Docker no está activo en systemd."
                        read -r "?Presiona Enter para volver..."
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
                    echo -n "Elige una opción [1-9]: "
                    read -r d_opt

                    case $d_opt in
                        1)
                            echo ""
                            echo "[-] Contenedores en ejecución:"
                            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        2)
                            echo ""
                            echo "[-] Listado completo de contenedores:"
                            docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        3)
                            echo ""
                            echo "[-] Monitoreo en vivo de consumo de CPU/RAM/RED (Ctrl+C para salir):"
                            sleep 1
                            docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        4)
                            echo ""
                            local target_cnt=""
                            if command -v fzf &> /dev/null; then
                                target_cnt=$(docker ps -a --format "{{.Names}}" | fzf --prompt="Selecciona contenedor para ver logs > ")
                            else
                                echo -n "Nombre del contenedor: "
                                read -r target_cnt
                            fi

                            if [[ -n "$target_cnt" ]]; then
                                echo ""
                                echo "[-] Mostrando últimas 50 líneas de log para '$target_cnt' (Ctrl+C para salir):"
                                sleep 1
                                docker logs -f --tail 50 "$target_cnt"
                                log_action "Docker: Consulta de logs en $target_cnt."
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        5)
                            echo ""
                            local action_cnt=""
                            if command -v fzf &> /dev/null; then
                                action_cnt=$(docker ps -a --format "{{.Names}}" | fzf --prompt="Selecciona contenedor a gestionar > ")
                            else
                                echo -n "Nombre del contenedor: "
                                read -r action_cnt
                            fi

                            if [[ -n "$action_cnt" ]]; then
                                echo ""
                                echo "Gestión para '$action_cnt':"
                                echo "1) Reiniciar (restart)"
                                echo "2) Detener (stop)"
                                echo "3) Iniciar (start)"
                                echo -n "Selecciona acción [1-3]: "
                                read -r act_choice
                                case $act_choice in
                                    1) sudo docker restart "$action_cnt" && log_action "Docker: Restart $action_cnt" ;;
                                    2) sudo docker stop "$action_cnt" && log_action "Docker: Stop $action_cnt" ;;
                                    3) sudo docker start "$action_cnt" && log_action "Docker: Start $action_cnt" ;;
                                esac
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        6)
                            echo ""
                            local inspect_cnt=""
                            if command -v fzf &> /dev/null; then
                                inspect_cnt=$(docker ps -a --format "{{.Names}}" | fzf --prompt="Selecciona contenedor a inspeccionar > ")
                            else
                                echo -n "Nombre del contenedor: "
                                read -r inspect_cnt
                            fi

                            if [[ -n "$inspect_cnt" ]]; then
                                echo ""
                                echo "[-] IP y Redes asignadas a '$inspect_cnt':"
                                docker inspect --format '{{range .NetworkSettings.Networks}}IP: {{.IPAddress}} | Gateway: {{.Gateway}} {{end}}' "$inspect_cnt"
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        7)
                            echo ""
                            echo "[-] Imágenes locales:"
                            docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
                            echo ""
                            echo "[-] Uso global de recursos de Docker:"
                            docker system df
                            log_action "Docker: Consulta de espacio e imágenes."
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        8)
                            echo ""
                            echo "[!] Limpieza de elementos en desuso en Docker..."
                            read -r "confirm_prune?¿Deseas ejecutar 'docker system prune -f'? (s/n): "
                            if [[ "$confirm_prune" == "s" || "$confirm_prune" == "S" ]]; then
                                sudo docker system prune -f
                                log_action "Docker: Executed docker system prune."
                            fi
                            read -r "?Presiona Enter para continuar..."
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
                    echo -n "Elige una opción [1-3]: "
                    read -r sub_opt
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
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        2)
                            cd ~/.local/bin/scripts || exit 1
                            git pull
                            read -r "?Presiona Enter para continuar..."
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
                    echo -n "Elige una opción [1-2]: "
                    read -r sub_opt
                    case $sub_opt in
                        1)
                            echo ""
                            echo "[-] Consultando wttr.in..."
                            curl -s "wttr.in?lang=es"
                            read -r "?Presiona Enter para continuar..."
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
                    echo -n "Elige una opción [1-3]: "
                    read -r auto_opt

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
                                read -r "inst_ansible?¿Deseas instalar Ansible ahora? (s/n): "
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
                            echo ""
                            read -r "?Presiona Enter para continuar..."
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
                                read -r "inst_tf?¿Deseas instalar Terraform (HashiCorp Repo) ahora? (s/n): "
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
                            echo ""
                            read -r "?Presiona Enter para continuar..."
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
                    echo "5) Puertos locales escuchando en el sistema (ss -tulpn)"
                    echo "6) Volver al menú principal"
                    echo "=========================================="
                    echo -n "Elige una opción [1-6]: "
                    read -r net_opt

                    case $net_opt in
                        1)
                            echo ""
                            echo "[-] Interfaces de red y direcciones IP:"
                            ip -brief address
                            echo ""
                            echo "[-] Tabla de ruteo por defecto:"
                            ip route
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        2)
                            echo ""
                            echo -n "Ingresa la IP o Dominio a probar (ej: 8.8.8.8 o google.com): "
                            read -r ping_target
                            if [[ -n "$ping_target" ]]; then
                                echo "[-] Enviando 4 paquetes ICMP a '$ping_target'..."
                                ping -c 4 "$ping_target"
                                log_action "Red: Ping ejecutado hacia $ping_target"
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        3)
                            echo ""
                            echo -n "Ingresa la IP o Dominio a trazar: "
                            read -r trace_target
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
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        4)
                            echo ""
                            echo -n "Ingresa la URL objetivo (ej: https://google.com): "
                            read -r curl_target
                            if [[ -n "$curl_target" ]]; then
                                echo "[-] Obteniendo cabeceras HTTP y código de respuesta..."
                                curl -I -L -s "$curl_target" | head -n 20
                                log_action "Red: Curl cabeceras en $curl_target"
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        5)
                            echo ""
                            echo "[-] Puertos TCP/UDP en escucha activa:"
                            sudo ss -tulpn | grep LISTEN
                            read -r "?Presiona Enter para continuar..."
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
                        read -r "inst_nmap?¿Deseas instalar nmap ahora? (s/n): "
                        if [[ "$inst_nmap" == "s" || "$inst_nmap" == "S" ]]; then
                            echo "[-] Instalando nmap..."
                            if command -v apt &> /dev/null; then
                                sudo apt update && sudo apt install -y nmap
                            elif command -v dnf &> /dev/null; then
                                sudo dnf install -y nmap
                            fi
                            log_action "Instalación completada: nmap."
                        else
                            read -r "?Presiona Enter para volver..."
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
                    echo -n "Elige una opción [1-5]: "
                    read -r nmap_opt

                    case $nmap_opt in
                        1)
                            echo ""
                            echo -n "Ingresa la IP o hostname objetivo: "
                            read -r target_ip
                            if [[ -n "$target_ip" ]]; then
                                echo "[-] Ejecutando escaneo rápido en '$target_ip'..."
                                nmap -T4 "$target_ip"
                                log_action "Nmap: Escaneo rápido en $target_ip"
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        2)
                            echo ""
                            echo -n "Ingresa la IP o hostname objetivo: "
                            read -r target_ip
                            if [[ -n "$target_ip" ]]; then
                                echo "[-] Ejecutando detección de versiones (-sV) en '$target_ip'..."
                                sudo nmap -sV -T4 "$target_ip"
                                log_action "Nmap: Escaneo de versiones en $target_ip"
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        3)
                            echo ""
                            echo -n "Ingresa la IP o hostname objetivo: "
                            read -r target_ip
                            if [[ -n "$target_ip" ]]; then
                                echo "[-] Ejecutando escaneo agresivo (-A) en '$target_ip'..."
                                sudo nmap -A -T4 "$target_ip"
                                log_action "Nmap: Escaneo agresivo en $target_ip"
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        4)
                            echo ""
                            echo -n "Ingresa el rango de red (ej: 192.168.1.0/24): "
                            read -r target_net
                            if [[ -n "$target_net" ]]; then
                                echo "[-] Descubriendo hosts activos en '$target_net'..."
                                nmap -sn "$target_net"
                                log_action "Nmap: Ping scan en red $target_net"
                            fi
                            read -r "?Presiona Enter para continuar..."
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
