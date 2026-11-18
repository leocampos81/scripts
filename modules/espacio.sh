#!/bin/bash

# --- Configuración ---
NUM_FILES_A_MOSTRAR=20
EXTENSION_COMPRIMIDO=".tar.gz"
RUTA_LOG="/tmp"
PREFIJO_LOG="revision_espacio_"

# Extensiones a excluir (ya comprimidas o inmutables)
EXTENSIONES_A_EXCLUIR=("gz" "tgz" "tar.gz" "zip" "rar" "7z" "bz2" "tbz2" "xz" "txz" "iso" "img" "mp4" "mkv" "jpg" "png" "pdf")

LOG_YA_GENERADO=false
ARCHIVO_LOG_ACTUAL=""

# --- Funciones ---
limpiar_y_encabezado() {
    clear
    echo "============================================================"
    echo "  Herramienta Interactiva de Gestión de Archivos Pesados   "
    echo "============================================================"
    echo ""
}

registrar_mensaje() {
    local MENSAJE="$1"
    if ! $LOG_YA_GENERADO; then
        ARCHIVO_LOG_ACTUAL="${RUTA_LOG}/${PREFIJO_LOG}$(date '+%Y%m%d_%H%M%S').log"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Script iniciado. Log: $ARCHIVO_LOG_ACTUAL" | sudo tee -a "$ARCHIVO_LOG_ACTUAL" > /dev/null
        LOG_YA_GENERADO=true
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $MENSAJE" | sudo tee -a "$ARCHIVO_LOG_ACTUAL" > /dev/null
}

validar_targz() {
    local ARCHIVO="$1"
    if gzip -t "$ARCHIVO" 2>/dev/null && tar -tf "$ARCHIVO" >/dev/null 2>&1; then
        return 0 # OK
    else
        return 1 # Fallo
    fi
}

# --- Lógica Principal ---
procesar_directorio() {
    local DIRECTORIO_OBJETIVO

    # 1. Solicitar ruta con opción de salir
    while true; do
        echo ""
        read -r -p "Ruta de la carpeta a revisar (o 'q' para volver al menú): " DIRECTORIO_OBJETIVO
        DIRECTORIO_OBJETIVO="${DIRECTORIO_OBJETIVO%/}" # Quitar barra final

        if [[ "$DIRECTORIO_OBJETIVO" == "q" || -z "$DIRECTORIO_OBJETIVO" ]]; then
            echo "Volviendo al menú..."
            return 1
        fi

        if [ -d "$DIRECTORIO_OBJETIVO" ]; then
            break
        else
            echo "Error: El directorio '$DIRECTORIO_OBJETIVO' no existe."
        fi
    done

    echo "------------------------------------------------------------"
    echo "  Buscando los $NUM_FILES_A_MOSTRAR archivos más pesados en '$DIRECTORIO_OBJETIVO'..."
    echo "------------------------------------------------------------"

    # 2. Buscar archivos
    local EXCLUSION_FIND_PART=""
    for ext in "${EXTENSIONES_A_EXCLUIR[@]}"; do
        EXCLUSION_FIND_PART+=" -not -name \"*.$ext\""
    done

    declare -a LISTA_ARCHIVOS_CRUDA
    mapfile -t LISTA_ARCHIVOS_CRUDA < <(eval sudo find \""$DIRECTORIO_OBJETIVO"\" -type f "$EXCLUSION_FIND_PART" -print0 | \
        xargs -0 du -h --time --time-style=+%d-%m-%Y\ %H:%M 2>/dev/null | \
        sort -rh | head -n "$NUM_FILES_A_MOSTRAR")

    # 3. Validar si hay archivos
    if [ ${#LISTA_ARCHIVOS_CRUDA[@]} -eq 0 ]; then
        echo ""
        echo "No se encontraron archivos pesados en ese directorio (o todos están excluidos)."
        echo "============================================================"
        return 0 # Volver al menú
    fi

    # 4. Mostrar lista
    declare -a ARCHIVOS_PARA_COMPRESION
    INDICE=1
    for info_archivo in "${LISTA_ARCHIVOS_CRUDA[@]}"; do
        RUTA_ARCHIVO=$(echo "$info_archivo" | awk '{path=""; for (i=4; i<=NF; i++) path=path (path=="" ? "" : " ") $i; print path}')
        TAMANO=$(echo "$info_archivo" | awk '{print $1}')
        FECHA_HORA=$(echo "$info_archivo" | awk '{print $2, $3}')
        
        printf "%-3s %-10s %-20s %s\n" "$INDICE." "$TAMANO" "$FECHA_HORA" "$RUTA_ARCHIVO"
        ARCHIVOS_PARA_COMPRESION[INDICE]="$RUTA_ARCHIVO"
        ((INDICE++))
    done
    echo "------------------------------------------------------------"

    # 5. Preguntar si desea comprimir
    echo ""
    read -r -p "¿Deseas comprimir alguno de estos archivos? (s/N): " CONFIRMAR_COMPRIMIR

    if [[ "$CONFIRMAR_COMPRIMIR" =~ ^[Ss]$ ]]; then
        read -r -p "Números de los archivos a comprimir (ej: 1 3 5), o 'q' para cancelar: " NUMEROS_ARCHIVOS_A_COMPRIMIR
        
        if [[ "$NUMEROS_ARCHIVOS_A_COMPRIMIR" == "q" || -z "$NUMEROS_ARCHIVOS_A_COMPRIMIR" ]]; then
            echo "Compresión cancelada."
        else
            for num in $NUMEROS_ARCHIVOS_A_COMPRIMIR; do
                ARCHIVO_A_COMPRIMIR="${ARCHIVOS_PARA_COMPRESION[num]}"
                
                if [ -n "$ARCHIVO_A_COMPRIMIR" ] && [ -f "$ARCHIVO_A_COMPRIMIR" ]; then
                    NOMBRE_ARCHIVO=$(basename "$ARCHIVO_A_COMPRIMIR")
                    NOMBRE_DIRECTORIO=$(dirname "$ARCHIVO_A_COMPRIMIR")
                    ARCHIVO_COMPRIMIDO="${ARCHIVO_A_COMPRIMIR}${EXTENSION_COMPRIMIDO}"

                    TAMANO_ANTES=$(sudo du -h "$ARCHIVO_A_COMPRIMIR" 2>/dev/null | awk '{print $1}')
                    [ -z "$TAMANO_ANTES" ] && TAMANO_ANTES="N/A"

                    echo "Comprimiendo '$NOMBRE_ARCHIVO'..."
                    registrar_mensaje "[INICIO COMPRESION] $ARCHIVO_A_COMPRIMIR"
                    
                    sudo tar -czf "$ARCHIVO_COMPRIMIDO" -C "$NOMBRE_DIRECTORIO" "$NOMBRE_ARCHIVO" --remove-files
                    
                    if [ $? -eq 0 ]; then
                        TAMANO_DESPUES=$(sudo du -h "$ARCHIVO_COMPRIMIDO" 2>/dev/null | awk '{print $1}')
                        [ -z "$TAMANO_DESPUES" ] && TAMANO_DESPUES="N/A"
                        
                        if validar_targz "$ARCHIVO_COMPRIMIDO"; then
                            echo "  -> [OK] Comprimido y validado. ($TAMANO_ANTES -> $TAMANO_DESPUES)"
                            registrar_mensaje "[COMPRIMIDO OK] $ARCHIVO_A_COMPRIMIR ($TAMANO_ANTES -> $TAMANO_DESPUES)"
                        else
                            echo "  -> [ALERTA] El archivo comprimido podría estar corrupto."
                            registrar_mensaje "[ALERTA CORRUPCION] $ARCHIVO_COMPRIMIDO"
                        fi
                    else
                        echo "  -> [ERROR] No se pudo comprimir '$NOMBRE_ARCHIVO'."
                        registrar_mensaje "[ERROR COMPRESION] $ARCHIVO_A_COMPRIMIR"
                    fi
                else
                    echo "  -> [ADVERTENCIA] El número '$num' no es válido o el archivo no existe."
                fi
            done
        fi
    else
        echo "No se seleccionaron archivos para comprimir."
    fi
    
    echo ""
    echo "============================================================"
    echo "  Análisis completado para este directorio.   "
    echo "============================================================"
    return 0
}

# --- Ejecución ---
limpiar_y_encabezado

# Bucle principal: solo vuelve al menú si el usuario lo pide o si presiona 'q'
while true; do
    if ! procesar_directorio; then
        break # Salir si el usuario escribió 'q' en la ruta
    fi
    
    echo ""
    read -r -p "¿Deseas consultar otro directorio? (s/N): " OTRA_CARPETA
    if [[ ! "$OTRA_CARPETA" =~ ^[Ss]$ ]]; then
        break
    fi
    limpiar_y_encabezado
done

# Mostrar log si se generó
if $LOG_YA_GENERADO; then
    echo ""
    echo "Se generó un log de respaldo en: $ARCHIVO_LOG_ACTUAL"
fi
