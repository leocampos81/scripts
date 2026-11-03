#!/usr/bin/env zsh

menu() {
    echo "=========================================="
    echo "    MENÚ DE HERRAMIENTAS - SYSADMIN"
    echo "=========================================="
    PS3="Elige una opción (o presiona Ctrl+C para salir): "
    
    typeset -a options
    options=("dnsglobe" "Actualizar / Sincronizar Repositorio" "Salir")
    
    select opt in "${options[@]}"; do
        case $opt in
            "dnsglobe")
                echo "[-] Verificando el estado de dnsglobe..."
                if command -v dnsglobe &> /dev/null; then
                    echo "[OK] dnsglobe ya está instalado y operativo en el sistema."
                else
                    echo "[!] dnsglobe no encontrado. Procediendo a la instalación..."
                    curl --proto '=https' --tlsv1.2 -LsSf https://github.com/514-labs/dnsglobe/releases/download/v0.3.0/dnsglobe-installer.sh | sh
                    echo "[OK] Instalación de dnsglobe finalizada."
                fi
                break
                ;;
            "Actualizar / Sincronizar Repositorio")
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
                
                # 4. Si hay archivos modificados/nuevos sin commit, hacer el commit
                if [[ -n $(git status --porcelain) ]]; then
                    echo ""
                    echo "[!] Se detectaron cambios locales no confirmados:"
                    git status -s
                    echo ""
                    
                    read "resp?¿Deseas empaquetar estos cambios (git add & commit)? (s/n): "
                    if [[ "$resp" == "s" || "$resp" == "S" ]]; then
                        local commit_msg=""
                        vared -p "Introduce el mensaje para el commit (o presiona Enter para mensaje por defecto): " commit_msg
                        
                        if [[ -z "$commit_msg" ]]; then
                            commit_msg="Actualización automática desde el menú sysadmin $(date +'%Y-%m-%d %H:%M:%S')"
                        fi
                        
                        echo "[-] Ejecutando git add..."
                        git add .
                        
                        echo "[-] Ejecutando git commit..."
                        git commit -m "$commit_msg"
                    fi
                fi

                # 5. Comprobar si la rama local está por delante de origin/main (commits pendientes por push)
                git fetch origin > /dev/null 2>&1
                local ahead_count=$(git rev-list --count origin/main..HEAD 2>/dev/null)

                if [[ "$ahead_count" -gt 0 ]]; then
                    echo ""
                    echo "[!] Tienes $ahead_count commit(s) local(es) listo(s) para subir a GitHub."
                    echo "[-] Ejecutando git push..."
                    if git push; then
                        echo "[OK] ¡Sincronización completada exitosamente con GitHub!"
                    else
                        echo "[ERROR] Falló el git push. Revisa tu conexión o tus llaves SSH."
                    fi
                else
                    echo "[OK] El repositorio está 100% al día con GitHub (no hay commits pendientes de subir)."
                fi
                break
                ;;
            "Salir")
                echo "Saliendo del menú."
                break
                ;;
            *) 
                echo "Opción inválida: $REPLY. Por favor, selecciona un número válido." 
                ;;
        esac
    done
}
