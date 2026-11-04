#!/usr/bin/env zsh

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
        # Limpiar pantalla al inicio de cada ciclo
        clear

        echo "=========================================="
        echo "    MENÚ DE HERRAMIENTAS - SYSADMIN"
        echo "=========================================="
        local sistema_actual=$(get_os_info)
        echo "[*] Servidor actual: $sistema_actual"
        echo "=========================================="
        echo "1) dnsglobe (Buscador y explorador de DNS e infraestructura)"
        echo "2) fzf (Buscador difuso interactivo para la terminal)"
        echo "3) Actualizar el sistema y limpiar paquetes huérfanos"
        echo "4) Actualizar / Sincronizar Repositorio"
        echo "5) Salir (o presiona 'q')"
        echo "=========================================="
        
        echo -n "Elige una opción [1-5 o q]: "
        read -r opt

        case $opt in
            1)
                echo ""
                echo "[-] Verificando el estado de dnsglobe..."
                if command -v dnsglobe &> /dev/null; then
                    echo "[OK] dnsglobe ya está instalado y operativo en el sistema."
                    log_action "Verificación: dnsglobe ya estaba instalado."
                else
                    echo "[!] dnsglobe no encontrado. Procediendo a la instalación..."
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
                    echo "[OK] fzf ya está instalado y operativo en el sistema."
                    log_action "Verificación: fzf ya estaba instalado."
                else
                    echo "[!] fzf no encontrado. Detectando gestor de paquetes..."
                    
                    if command -v apt &> /dev/null; then
                        echo "[-] Gestor detectado: apt (Debian/Ubuntu). Instalando..."
                        sudo apt update && sudo apt install -y fzf
                        log_action "Instalación completada: fzf vía apt."
                    elif command -v dnf &> /dev/null; then
                        echo "[-] Gestor detectado: dnf (Rocky Linux/Fedora). Instalando..."
                        sudo dnf install -y fzf
                        log_action "Instalación completada: fzf vía dnf."
                    else
                        echo "[ERROR] No se encontró un gestor de paquetes compatible (apt o dnf)."
                        log_action "Error: No se pudo instalar fzf, gestor desconocido."
                    fi
                    echo "[OK] Proceso de fzf finalizado."
                fi
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            3)
                echo ""
                echo "[-] Iniciando mantenimiento integral del sistema en ($(get_os_info))..."
                log_action "Mantenimiento del sistema iniciado."
                
                if command -v apt &> /dev/null; then
                    echo "[-] Actualizando índices de paquetes (apt update)..."
                    sudo apt update
                    echo "[-] Actualizando paquetes instalados (apt dist-upgrade)..."
                    sudo apt dist-upgrade -y
                    echo "[-] Eliminando paquetes huérfanos e innecesarios (apt autoremove)..."
                    sudo apt autoremove -y
                    echo "[-] Limpiando caché de paquetes descargados (apt autoclean)..."
                    sudo apt autoclean
                    echo "[OK] Sistema Debian/Ubuntu actualizado y depurado correctamente."
                    log_action "Mantenimiento completado con éxito vía apt."
                elif command -v dnf &> /dev/null; then
                    echo "[-] Actualizando paquetes del sistema (dnf upgrade)..."
                    sudo dnf upgrade -y
                    echo "[-] Eliminando paquetes huérfanos (dnf autoremove)..."
                    sudo dnf autoremove -y
                    echo "[OK] Sistema Rocky/Fedora actualizado y depurado correctamente."
                    log_action "Mantenimiento completado con éxito vía dnf."
                else
                    echo "[ERROR] No se reconoció gestor de paquetes para el mantenimiento."
                    log_action "Error en mantenimiento: gestor no compatible."
                fi
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            4)
                echo ""
                echo "[-] Verificando el estado del repositorio en ~/.local/bin/scripts..."
                cd ~/.local/bin/scripts || exit 1
                
                # 1. Asegurar uso de SSH
                local current_remote=$(git remote get-url origin 2>/dev/null)
                if [[ "$current_remote" =~ "^https://github.com/" ]]; then
                    echo "[!] Cambiando el remoto de HTTPS a SSH..."
                    git remote set-url origin git@github.com:leocampos81/scripts.git
                fi

                # 2. Configurar usuario/correo si no existen
                if [[ -z "$(git config user.name)" ]]; then
                    echo "[!] No se encontró un user.name configurado en Git."
                    local git_name=""
                    vared -p "Introduce tu nombre para Git: " git_name
                    git config user.name "$git_name"
                fi
                
                if [[ -z "$(git config user.email)" ]]; then
                    echo "[!] No se encontró un user.email configurado en Git."
                    local git_email=""
                    vared -p "Introduce tu correo para Git: " git_email
                    git config user.email "$git_email"
                fi
                
                # 3. Traer cambios de GitHub (git pull)
                echo "[-] Ejecutando git pull..."
                git pull
                
                # 4. Manejo de cambios locales no confirmados
                if [[ -n $(git status --porcelain) ]]; then
                    echo ""
                    echo "[!] Se detectaron cambios locales no confirmados:"
                    git status -s
                    echo ""
                    
                    read "resp?¿Deseas empaquetar estos cambios (git add & commit)? (s/n): "
                    if [[ "$resp" == "s" || "$resp" == "S" ]]; then
                        local commit_msg=""
                        vared -p "Introduce el mensaje para el commit (o presiona Enter): " commit_msg
                        
                        if [[ -z "$commit_msg" ]]; then
                            commit_msg="Actualización automática desde el menú sysadmin $(date +'%Y-%m-%d %H:%M:%S')"
                        fi
                        
                        echo "[-] Ejecutando git add..."
                        git add .
                        
                        echo "[-] Ejecutando git commit..."
                        git commit -m "$commit_msg"
                        log_action "Git commit ejecutado con mensaje: $commit_msg"
                    fi
                fi

                # 5. Enviar commits pendientes a GitHub mediante git push
                git fetch origin > /dev/null 2>&1
                local ahead_count=$(git rev-list --count origin/main..HEAD 2>/dev/null)

                if [[ "$ahead_count" -gt 0 ]]; then
                    echo ""
                    echo "[!] Tienes $ahead_count commit(s) local(es) listo(s) para subir a GitHub."
                    echo "[-] Ejecutando git push..."
                    if git push; then
                        echo "[OK] ¡Sincronización completada exitosamente con GitHub!"
                        log_action "Git push exitoso a GitHub."
                    else
                        echo "[ERROR] Falló el git push. Revisa tu conexión o tus llaves SSH."
                        log_action "Error en git push."
                    fi
                else
                    echo "[OK] El repositorio está 100% al día con GitHub."
                fi
                echo ""
                echo -n "Presiona Enter para volver al menú..."
                read -r
                ;;
            5|[qQ])
                echo "Saliendo del menú."
                break
                ;;
            *)
                echo ""
                echo "Opción inválida: '$opt'. Presiona Enter e intenta nuevamente."
                read -r
                ;;
        esac
    done
}
