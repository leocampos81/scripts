#!/usr/bin/env zsh

# ==============================================================================
#  LEONARDO CAMPOS - SYSADMIN TOOLKIT & DASHBOARD
#  Repositorio: git@github.com:leocampos81/scripts.git
# ==============================================================================

# Función para registrar logs de auditoría
log_action() {
    local log_file="$HOME/.local/bin/scripts/sysadmin.log"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$log_file"
}

# Función para detectar el sistema operativo actual
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

        # Encabezado personalizado para Leonardo Campos
        echo "=========================================================="
        echo "   __    ____  _____   ____  _  _  ____    __  ____  _  _ "
        echo "  (  )  (  __)(  _  ) / ___)( \/ )/ ___)  / _\(_  _)( \/ )"
        echo "  / (_/\ ) _)  ) (_ (  \___ \ )  / \___ \ /    \ )(   )  / "
        echo "  \____/(____)(____/  (____/(__/  (____/ \_/\_/(__)  (__/  "
        echo "=========================================================="
        echo "            LEONARDO CAMPOS | SYSADMIN DASHBOARD"
        echo "=========================================================="
        local sistema_actual=$(get_os_info)
        echo "[*] Usuario Activo : $USER@$(hostname)"
        echo "[*] Servidor actual: $sistema_actual"
        echo "=========================================================="
        echo "1) dnsglobe (Buscador y explorador de DNS)"
        echo "2) fzf (Buscador difuso para terminal)"
        echo "3) Monitoreo de recursos (btop, htop o top)"
        echo "4) Diagnóstico de disco y espacio (df, ncdu)"
        echo "5) Diagnóstico rápido de red e interfaces"
        echo "6) Servicios y Contenedores Docker"
        echo "7) Actualizar el sistema y limpiar paquetes"
        echo "8) Actualizar / Sincronizar Repositorio (GitHub)"
        echo "9) Salir (o presiona 'q')"
        echo "=========================================================="
        
        echo -n "LEO-DASHBOARD > Elige una opción [1-9 o q]: "
        read -r opt

        case $opt in
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
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            2)
                echo ""
                echo "[-] Verificando el estado de fzf en ($(get_os_info))..."
                if command -v fzf &> /dev/null; then
                    echo "[OK] fzf ya está instalado y operativo."
                    log_action "Verificación: fzf ya estaba instalado."
                else
                    echo "[!] fzf no encontrado. Detectando gestor..."
                    if command -v apt &> /dev/null; then
                        sudo apt update && sudo apt install -y fzf
                        log_action "Instalación completada: fzf vía apt."
                    elif command -v dnf &> /dev/null; then
                        sudo dnf install -y fzf
                        log_action "Instalación completada: fzf vía dnf."
                    fi
                    echo "[OK] Proceso de fzf finalizado."
                fi
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            3)
                echo ""
                echo "=========================================="
                echo "       MONITORES DE RECURSOS - LEO"
                echo "=========================================="
                echo "1) btop (Monitor moderno y visual)"
                echo "2) htop (Monitor interactivo por procesos)"
                echo "3) top  (Monitor nativo básico)"
                echo "=========================================="
                echo -n "Elige qué monitor deseas abrir [1-3]: "
                read -r monitor_opt

                case $monitor_opt in
                    1)
                        if command -v btop &> /dev/null; then
                            clear
                            btop
                        else
                            echo "[!] btop no está instalado."
                            read "instalar?¿Deseas instalar btop ahora? (s/n): "
                            if [[ "$instalar" == "s" || "$instalar" == "S" ]]; then
                                command -v apt &> /dev/null && sudo apt update && sudo apt install -y btop
                                command -v dnf &> /dev/null && sudo dnf install -y btop
                                log_action "Instalación completada: btop."
                                clear
                                btop
                            fi
                        fi
                        ;;
                    2)
                        if command -v htop &> /dev/null; then
                            clear
                            htop
                        else
                            echo "[!] htop no está instalado."
                            read "instalar?¿Deseas instalar htop ahora? (s/n): "
                            if [[ "$instalar" == "s" || "$instalar" == "S" ]]; then
                                command -v apt &> /dev/null && sudo apt update && sudo apt install -y htop
                                command -v dnf &> /dev/null && sudo dnf install -y htop
                                log_action "Instalación completada: htop."
                                clear
                                htop
                            fi
                        fi
                        ;;
                    3)
                        clear
                        top
                        ;;
                    *)
                        echo "Opción no válida."
                        read -r
                        ;;
                esac
                ;;
            4)
                echo ""
                echo "=========================================="
                echo "     DIAGNÓSTICO DE DISCO Y ESPACIO"
                echo "=========================================="
                echo "[-] Resumen de particiones de almacenamiento:"
                df -h -x tmpfs -x devtmpfs
                echo ""
                
                if command -v ncdu &> /dev/null; then
                    read "run_ncdu?¿Deseas abrir ncdu para explorar carpetas pesadas interactivamente? (s/n): "
                    if [[ "$run_ncdu" == "s" || "$run_ncdu" == "S" ]]; then
                        ncdu /
                    fi
                else
                    echo "[i] Tip: La herramienta 'ncdu' no está instalada."
                    read "inst_ncdu?¿Deseas instalar ncdu ahora? (s/n): "
                    if [[ "$inst_ncdu" == "s" || "$inst_ncdu" == "S" ]]; then
                        command -v apt &> /dev/null && sudo apt update && sudo apt install -y ncdu
                        command -v dnf &> /dev/null && sudo dnf install -y ncdu
                        log_action "Instalación completada: ncdu."
                        ncdu /
                    fi
                fi
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            5)
                echo ""
                echo "=========================================="
                echo "     DIAGNÓSTICO RÁPIDO DE RED"
                echo "=========================================="
                echo "[-] Direcciones IP e interfaces activas:"
                ip -brief color address 2>/dev/null || ip a
                echo ""
                echo "[-] Prueba rápida de conectividad hacia Internet (1.1.1.1):"
                if ping -c 2 1.1.1.1 &> /dev/null; then
                    echo "[OK] Conexión hacia Internet: OPERATIVA"
                else
                    echo "[ERROR] Sin respuesta de ping hacia 1.1.1.1"
                fi
                echo ""
                echo "[-] Resolución DNS de prueba (github.com):"
                if host github.com &> /dev/null || nslookup github.com &> /dev/null; then
                    echo "[OK] Resolución de nombres DNS: OPERATIVA"
                else
                    echo "[ERROR] Falló la resolución DNS de github.com"
                fi
                log_action "Verificación rápida de red ejecutada."
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            6)
                echo ""
                echo "=========================================="
                echo "    GESTIÓN Y ESTADO DE DOCKER LAB"
                echo "=========================================="
                
                # 1. Validar si Docker está instalado
                if ! command -v docker &> /dev/null; then
                    echo "[!] Docker no está instalado en este sistema ($(get_os_info))."
                    read "inst_docker?¿Deseas instalar Docker Engine ahora? (s/n): "
                    if [[ "$inst_docker" == "s" || "$inst_docker" == "S" ]]; then
                        if command -v apt &> /dev/null; then
                            sudo apt update && sudo apt install -y docker.io docker-compose
                            sudo systemctl enable --now docker
                            log_action "Instalación completada: Docker vía apt."
                        elif command -v dnf &> /dev/null; then
                            sudo dnf install -y docker docker-compose
                            sudo systemctl enable --now docker
                            log_action "Instalación completada: Docker vía dnf."
                        fi
                    fi
                    echo -n "Presiona Enter para volver al menú..."
                    read -r
                    continue
                fi

                # 2. Validar si el servicio de Docker está corriendo
                if ! systemctl is-active --quiet docker; then
                    echo "[!] El servicio de Docker está detenido o inactivo."
                    read "start_docker?¿Deseas iniciar el servicio con 'sudo systemctl start docker'? (s/n): "
                    if [[ "$start_docker" == "s" || "$start_docker" == "S" ]]; then
                        sudo systemctl start docker
                        log_action "Servicio Docker iniciado."
                    else
                        echo -n "Presiona Enter para volver al menú..."
                        read -r
                        continue
                    fi
                fi

                # 3. Submenú de Docker
                echo "1) Ver contenedores activos (docker ps)"
                echo "2) Ver TODOS los contenedores (activos e inactivos)"
                echo "3) Ver logs en tiempo real de un contenedor"
                echo "4) Ver imágenes guardadas y uso de disco en Docker"
                echo "=========================================="
                echo -n "Elige una opción de Docker [1-4]: "
                read -r d_opt

                case $d_opt in
                    1)
                        echo ""
                        echo "[-] Contenedores actualmente en ejecución:"
                        local active_cnt=$(docker ps -q | wc -l)
                        if [[ "$active_cnt" -eq 0 ]]; then
                            echo "[i] No hay contenedores activos en este momento."
                        else
                            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                        fi
                        log_action "Consulta de contenedores activos realizada."
                        ;;
                    2)
                        echo ""
                        echo "[-] Listado completo de contenedores:"
                        local total_cnt=$(docker ps -a -q | wc -l)
                        if [[ "$total_cnt" -eq 0 ]]; then
                            echo "[i] No existen contenedores creados en el sistema."
                        else
                            docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
                        fi
                        log_action "Consulta de todos los contenedores realizada."
                        ;;
                    3)
                        echo ""
                        local total_cnt=$(docker ps -a -q | wc -l)
                        if [[ "$total_cnt" -eq 0 ]]; then
                            echo "[i] No hay contenedores disponibles para consultar logs."
                        else
                            local selected_container=""
                            if command -v fzf &> /dev/null; then
                                echo "[-] Selecciona el contenedor utilizando fzf:"
                                selected_container=$(docker ps -a --format "{{.Names}}" | fzf)
                            else
                                echo "[-] Contenedores disponibles:"
                                docker ps -a --format " - {{.Names}}"
                                echo ""
                                echo -n "Escribe el nombre del contenedor: "
                                read -r selected_container
                            fi

                            if [[ -n "$selected_container" ]]; then
                                echo "[-] Mostrando últimas 50 líneas de log para '$selected_container' (Ctrl+C para salir):"
                                sleep 1
                                docker logs -f --tail 50 "$selected_container"
                                log_action "Verificación de logs para contenedor: $selected_container"
                            fi
                        fi
                        ;;
                    4)
                        echo ""
                        echo "[-] Imágenes guardadas localmente:"
                        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
                        echo ""
                        echo "[-] Resumen de espacio consumido por Docker:"
                        docker system df
                        log_action "Consulta de espacio e imágenes Docker realizada."
                        ;;
                    *)
                        echo "Opción de Docker no válida."
                        ;;
                esac

                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            7)
                echo ""
                echo "[-] Mantenimiento integral del sistema en ($(get_os_info))..."
                log_action "Mantenimiento del sistema iniciado."
                
                if command -v apt &> /dev/null; then
                    echo "[-] Ejecutando apt update & dist-upgrade..."
                    sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean
                    echo "[OK] Sistema Debian actualizado."
                    log_action "Mantenimiento completado vía apt."
                elif command -v dnf &> /dev/null; then
                    echo "[-] Ejecutando dnf upgrade..."
                    sudo dnf upgrade -y && sudo dnf autoremove -y
                    echo "[OK] Sistema Rocky Linux actualizado."
                    log_action "Mantenimiento completado vía dnf."
                fi
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            8)
                echo ""
                echo "[-] Verificando repositorio en ~/.local/bin/scripts..."
                cd ~/.local/bin/scripts || exit 1
                
                local current_remote=$(git remote get-url origin 2>/dev/null)
                if [[ "$current_remote" =~ "^https://github.com/" ]]; then
                    git remote set-url origin git@github.com:leocampos81/scripts.git
                fi

                if [[ -z "$(git config user.name)" ]]; then
                    local git_name=""
                    vared -p "Introduce tu nombre para Git: " git_name
                    git config user.name "$git_name"
                fi
                
                if [[ -z "$(git config user.email)" ]]; then
                    local git_email=""
                    vared -p "Introduce tu correo para Git: " git_email
                    git config user.email "$git_email"
                fi
                
                echo "[-] Ejecutando git pull..."
                git pull
                
                if [[ -n $(git status --porcelain) ]]; then
                    echo ""
                    echo "[!] Cambios locales no confirmados:"
                    git status -s
                    echo ""
                    
                    read "resp?¿Deseas empaquetar estos cambios (git add & commit)? (s/n): "
                    if [[ "$resp" == "s" || "$resp" == "S" ]]; then
                        local commit_msg=""
                        vared -p "Mensaje del commit (Enter para valor por defecto): " commit_msg
                        [[ -z "$commit_msg" ]] && commit_msg="Actualización automática desde menú sysadmin $(date +'%Y-%m-%d %H:%M:%S')"
                        
                        git add .
                        git commit -m "$commit_msg"
                        log_action "Git commit ejecutado: $commit_msg"
                    fi
                fi

                git fetch origin > /dev/null 2>&1
                local ahead_count=$(git rev-list --count origin/main..HEAD 2>/dev/null)

                if [[ "$ahead_count" -gt 0 ]]; then
                    echo ""
                    echo "[-] Ejecutando git push ($ahead_count commit(s) pendientes)..."
                    if git push; then
                        echo "[OK] Sincronizado exitosamente con GitHub."
                        log_action "Git push exitoso."
                    else
                        echo "[ERROR] Falló el git push."
                        log_action "Error en git push."
                    fi
                else
                    echo "[OK] El repositorio está al día."
                fi
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            9|[qQ])
                echo "¡Hasta luego, Leonardo! Cerrando dashboard."
                break
                ;;
            *)
                echo ""
                echo "Opción inválida: '$opt'."
                read -r
                ;;
        esac
    done
}
