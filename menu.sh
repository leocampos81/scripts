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
        echo "3) Servicios y Contenedores Docker"
        echo "4) Mantenimiento de Sistema y Sincronización Git"
        echo "5) Utilidades Varias (Clima wttr.in, etc.)"
        echo "6) Salir (o presiona 'q')"
        echo "=========================================================="
        
        echo -n "LEO-DASHBOARD > Elige una opción [1-6 o q]: "
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
                echo ""
                echo "=========================================="
                echo "      GESTIÓN Y ESTADO DE DOCKER LAB"
                echo "=========================================="
                if ! command -v docker &> /dev/null; then
                    echo "[!] Docker no está instalado."
                else
                    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                fi
                read -r "?Presiona Enter para volver..."
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
            6|[qQ])
                echo "¡Hasta luego, Leonardo! Cerrando dashboard."
                break
                ;;
        esac
    done
}
