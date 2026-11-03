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
                
                # Verificar y configurar identidad de Git si falta
                if [[ -z "$(git config user.name)" ]]; then
                    echo "[!] No se encontró un user.name configurado en este repositorio."
                    echo -n "Introduce tu nombre para Git: "
                    read git_name
                    git config user.name "$git_name"
                fi
                
                if [[ -z "$(git config user.email)" ]]; then
                    echo "[!] No se encontró un user.email configurado en este repositorio."
                    echo -n "Introduce tu correo para Git: "
                    read git_email
                    git config user.email "$git_email"
                fi
                
                # 1. Intentar traer cambios de GitHub
                echo "[-] Ejecutando git pull..."
                git pull
                
                # 2. Verificar si hay cambios locales sin subir
                if [[ -n $(git status --porcelain) ]]; then
                    echo ""
                    echo "[!] Se detectaron cambios locales pendientes de subir:"
                    git status -s
                    echo ""
                    
                    # Preguntar al usuario si desea hacer push
                    read "resp?¿Deseas empaquetar y subir estos cambios a GitHub (git add, commit, push)? (s/n): "
                    if [[ "$resp" == "s" || "$resp" == "S" ]]; then
                        echo -n "Introduce el mensaje para el commit (o presiona Enter para usar uno por defecto): "
                        read commit_msg
                        
                        if [[ -z "$commit_msg" ]]; then
                            commit_msg="Actualización automática desde el menú sysadmin $(date +'%Y-%m-%d %H:%M:%S')"
                        fi
                        
                        echo "[-] Ejecutando git add..."
                        git add .
                        
                        echo "[-] Ejecutando git commit..."
                        git commit -m "$commit_msg"
                        
                        echo "[-] Ejecutando git push..."
                        git push
                        
                        echo "[OK] ¡Cambios subidos exitosamente a GitHub!"
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
