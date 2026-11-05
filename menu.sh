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
        echo "2) Monitoreo de recursos locales y disco (btop, df, ncdu)"
        echo "3) Servicios y Contenedores Docker (Avanzado)"
        echo "4) Mantenimiento de Sistema y Sincronización Git"
        echo "5) Utilidades Varias (Clima wttr.in, etc.)"
        echo "6) Herramientas de Automatización (Ansible, Terraform)"
        echo "7) Salir (o presiona 'q')"
        echo "=========================================================="
        
        echo -n "LEO-DASHBOARD > Elige una opción [1-7 o q]: "
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
                                echo "[!] dnsglobe no encontrado. Instalando..."
                                curl --proto '=https' --tlsv1.2 -LsSf https://github.com/514-labs/dnsglobe/releases/download/v0.3.0/dnsglobe-installer.sh | sh
                                echo "[OK] Instalación de dnsglobe finalizada."
                                log_action "Instalación completada: dnsglobe vía curl."
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        2)
                            echo ""
                            echo "[-] Verificando el estado de fzf en ($(get_os_info))..."
                            if command -v fzf &> /dev/null; then
                                echo "[OK] fzf ya está instalado y operativo."
                                log_action "Verificación: fzf ya estaba instalado."
                            else
                                echo "[!] fzf no encontrado. Instalando..."
                                if command -v apt &> /dev/null; then
                                    sudo apt update && sudo apt install -y fzf
                                elif command -v dnf &> /dev/null; then
                                    sudo dnf install -y fzf
                                fi
                                log_action "Instalación completada: fzf."
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
                    echo "2) Diagnóstico de disco y espacio (df)"
                    echo "3) Explorador interactivo de carpetas pesadas (ncdu)"
                    echo "4) Volver al menú principal"
                    echo "=========================================="
                    echo -n "Elige una opción [1-4]: "
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
                            echo "[-] Resumen de almacenamiento local:"
                            df -h -x tmpfs -x devtmpfs
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        3)
                            if command -v ncdu &> /dev/null; then
                                ncdu /
                            else
                                echo "[!] ncdu no está instalado."
                            fi
                            read -r "?Presiona Enter para continuar..."
                            ;;
                        4) break ;;
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
	7|[qQ])
                echo "¡Hasta luego, Leonardo! Cerrando dashboard."
                break
                ;;
        esac
    done
}
