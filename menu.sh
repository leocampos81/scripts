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
                
                # 1. Asegurar uso de SSH en lugar de HTTPS para autenticación sin contraseña
                local current_remote=$(git remote get-url origin 2>/dev/null)
                if [[ "$current_remote" =~ "^https://github.com/" ]]; then
                    echo "[!] Cambiando el remoto de HTTPS a SSH..."
                    git remote set-url origin git@github.com:leocampos81/scripts.git
                fi

                # 2. Verificar y configurar user.name con soporte real de Backspace
                if [[ -z "$(git config user.name)" ]]; then
                    echo "[!] No se encontró un user.name configurado en Git."
                    local git_name=""
                    vared -p "Introduce tu nombre para Git: " git_name
                    git config user.name "$git_name"
                fi
                
                # 3. Verificar y configurar user.email con soporte real de Backspace
                if [[ -z "$(git config user.email)" ]]; then
                    echo "[!] No se encontró un user.email configurado en Git."
                    local git_email=""
                    vared -p "Introduce tu correo para Git: " git_email
                    git config user.email "$git_email"
                fi
                
                # 4. Intentar traer cambios remotos de GitHub
                echo "[-] Ejecutando git pull..."
                git pull
                
                # 5. Verificar si hay cambios locales sin subir
                if [[ -n $(git status --porcelain) ]]; then
                    echo ""
                    echo "[!] Se detectaron cambios locales pendientes de subir:"
                    git status -s
                    echo ""
                    
                    read "resp?¿Deseas empaquetar y subir estos cambios a GitHub (git add, commit, push)? (s/n): "
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
                        
                        echo "[-] Ejecutando git push..."
                        if git push; then
                            echo "[OK] ¡Cambios subidos exitosamente a GitHub!"
                        else
                            echo "[ERROR] Falló el git push. Revisa tu conexión o tus llaves SSH en ~/.ssh/"
                        fi
                    else
                        echo "[i] Omitiendo el envío de cambios locales."
                    fi
                else
                    echo "[OK] El árbol de trabajo local está limpio. No hay cambios pendientes por subir."
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
