#!/bin/bash

# ==============================================================================
# SCRIPT DE RESPALDO LEONARDO 4.0 - ESTRUCTURA DE CARPETAS PRESERVADA
# ==============================================================================

BACKUP_DIR="/media/leonardo/ad5dbfee-621f-4cc7-a280-4f4bf61f2dc5/respaldo_leonardo/"
HOME_DIR="/home/leonardo"  # Sin barra final para consistencia
LOGFILE="/home/leonardo/rsync_backup_$(date +'%Y-%m-%d_%H%M%S').log"
SELECTED_ITEMS=()

# --- FUNCIONES ---

detect_configs() {
    echo "Detectando configuraciones en $HOME_DIR..."
    local common=(".config" ".local/share" ".ssh" ".gnupg" ".mozilla" ".bashrc" ".gitconfig" ".profile")
    CONFIG_FOUND=()
    for c in "${common[@]}"; do
        [ -e "${HOME_DIR}/$c" ] && CONFIG_FOUND+=("$c")
    done
}

select_dirs() {
    echo "=== DIRECTORIOS PRINCIPALES ==="
    local dirs=()
    # Buscamos directorios reales en el home
    while IFS= read -r -d '' dir; do dirs+=("$(basename "$dir")"); done < <(find "$HOME_DIR" -maxdepth 1 -type d ! -name ".*" ! -path "$HOME_DIR" -print0 | sort -z)
    
    local i=1
    for d in "${dirs[@]}"; do
        printf "%3d) %-25s [%s]\n" $i "$d" "$(du -sh "${HOME_DIR}/$d" 2>/dev/null | cut -f1)"
        ((i++))
    done
    read -p "Selecciona carpetas (ej: 20): " sel
    for n in $sel; do 
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -le "${#dirs[@]}" ]; then
            # IMPORTANTE: Guardamos el nombre sin "/" para que rsync cree la carpeta
            SELECTED_ITEMS+=("${dirs[$((n-1))]}") 
        fi
    done
}

select_configs() {
    echo -e "\n=== CONFIGURACIONES ==="
    local i=1
    for c in "${CONFIG_FOUND[@]}"; do
        printf "%3d) %-25s\n" $i "$c"
        ((i++))
    done
    read -p "¿Respaldar todas las configs detectadas? [S/n]: " conf
    if [[ "$conf" =~ ^[Ss]?$ ]]; then
        for c in "${CONFIG_FOUND[@]}"; do
            SELECTED_ITEMS+=("$c")
        done
    fi
}

perform_backup() {
    echo -e "\n======================================"
    echo "    INICIANDO RESPALDO ORDENADO"
    echo "======================================"
    
    START=$(date +%s)
    
    # Nos movemos al padre de leonardo para que rsync pueda recrear "leonardo/carpeta"
    # O nos mantenemos en home y pasamos los nombres directos.
    cd "$HOME_DIR" || exit
    
    echo "Destino: $BACKUP_DIR"
    echo "Copiando elementos seleccionados..."
    echo "--------------------------------------"

    # rsync -a: modo archivo (recursivo y preserva todo)
    # Sin barra al final de los items para que copie la CARPETA, no solo el contenido.
    rsync -avh --progress --delete "${SELECTED_ITEMS[@]}" "$BACKUP_DIR" 2>&1 | tee "$LOGFILE"
    
    RSYNC_EXIT_CODE=${PIPESTATUS[0]}
    END=$(date +%s)
    DIFF=$((END - START))

    echo -e "\n--------------------------------------"
    if [ $RSYNC_EXIT_CODE -eq 0 ]; then
        echo "✓ Completado en $((DIFF / 60))m $((DIFF % 60))s."
        echo "Las carpetas se han creado correctamente en el destino."
    else
        echo "✗ Error. Revisa el log: $LOGFILE"
    fi
}

# --- FLUJO ---
clear
if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: El disco de respaldo no está montado."
    exit 1
fi

detect_configs
select_dirs
select_configs

if [ ${#SELECTED_ITEMS[@]} -eq 0 ]; then
    echo "No seleccionaste nada."
    exit 0
fi

echo -e "\nRESUMEN: Se copiarán ${#SELECTED_ITEMS[@]} elementos a $BACKUP_DIR"
read -p "¿Confirmar? [S/n]: " proc
if [[ "$proc" =~ ^[Ss]?$ ]]; then
    perform_backup
fi

