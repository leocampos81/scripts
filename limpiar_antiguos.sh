#!/bin/bash

# --- CONFIGURACIÓN ---
DIAS_ANTIGUEDAD=90
# Definimos el nombre base, pero no creamos el archivo aún
LOG_BASE="/tmp/auditoria_limpieza_$(date +%Y%m%d_%H%M).log"

# Extensiones a EXCLUIR (No comprimir lo ya comprimido)
EXCLUIR_EXT='.*\.\(gz\|zip\|tgz\|tar\|rar\|7z\|bz2\|xz\)$'

# --- FUNCIONES ---
verificar_tar() {
    local ARCHIVO="$1"
    if gzip -t "$ARCHIVO" 2>/dev/null && tar -tf "$ARCHIVO" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

escanear_directorio() {
    echo "Analizando archivos no comprimidos de más de $DIAS_ANTIGUEDAD días..."
    find "$DIR_OBJETIVO" -type f -mtime +$DIAS_ANTIGUEDAD ! -regex "$EXCLUIR_EXT" -printf "%TY-%Tm-%Td  %p\n" > "$LISTA_TEMP"
    CANTIDAD=$(wc -l < "$LISTA_TEMP")
    
    if [ "$CANTIDAD" -gt 0 ]; then
        TAMANO_TOTAL=$(awk '{print $2}' "$LISTA_TEMP" | xargs -d '\n' du -ch | tail -n 1 | awk '{print $1}')
    else
        TAMANO_TOTAL="0B"
    fi
}

# --- FLUJO PRINCIPAL ---
clear
echo "============================================================"
echo "    GESTOR DE ARCHIVOS ANTIGUOS (+${DIAS_ANTIGUEDAD} DÍAS)"
echo "    [MODO PRODUCCIÓN - AUDITORÍA ESTRICTA]"
echo "============================================================"

read -p "Ruta a revisar: " DIR_OBJETIVO
DIR_OBJETIVO="${DIR_OBJETIVO%/}"

if [ ! -d "$DIR_OBJETIVO" ]; then
    echo "Error: El directorio no existe."
    exit 1
fi

LISTA_TEMP=$(mktemp)
escanear_directorio

if [ "$CANTIDAD" -eq 0 ]; then
    echo "No se encontraron archivos candidatos."
    rm "$LISTA_TEMP"
    exit 0
fi

while true; do
    echo ""
    echo "------------------------------------------------------------"
    echo "CARPETA: $DIR_OBJETIVO | ARCHIVOS: $CANTIDAD | TAMAÑO: $TAMANO_TOTAL"
    echo "------------------------------------------------------------"
    echo "1) Comprimir y BORRAR (Generar Log de Auditoría)"
    echo "2) Listar archivos detallados con su FECHA"
    echo "3) Cambiar de directorio / Re-escanear"
    echo "4) Salir"
    read -p "Opción [1-4]: " OPCION

    case $OPCION in
        1)
            NOMBRE_BACKUP="${DIR_OBJETIVO##*/}_limpieza_$(date +%Y%m%d_%H%M).tar.gz"
            R_BACKUP="$(dirname "$DIR_OBJETIVO")/$NOMBRE_BACKUP"
            LOG_ACTUAL="${LOG_BASE}" # El log se define aquí

            echo ""
            echo "Iniciando proceso... (Prioridad mínima para Asterisk)"
            echo "------------------------------------------------------------"

            # 1. Escribir encabezado y LISTADO de auditoría en el log ANTES de borrar nada
            {
                echo "============================================================"
                echo "      REPORTE DE AUDITORÍA DE COMPRESIÓN Y LIMPIEZA"
                echo "============================================================"
                echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "Directorio analizado: $DIR_OBJETIVO"
                echo "Archivos encontrados: $CANTIDAD"
                echo "Tamaño estimado: $TAMANO_TOTAL"
                echo "Archivo de respaldo creado: $R_BACKUP"
                echo "------------------------------------------------------------"
                echo "LISTADO DE ARCHIVOS PROCESADOS (FECHA | RUTA):"
                cat "$LISTA_TEMP"
                echo "------------------------------------------------------------"
            } > "$LOG_ACTUAL"

            # 2. Ejecutar la compresión
            awk '{print $2}' "$LISTA_TEMP" | xargs -d '\n' \
            nice -n 19 ionice -c 3 \
            tar -cvzf "$R_BACKUP" --remove-files

            if [ $? -eq 0 ]; then
                echo "------------------------------------------------------------"
                echo "Compresión finalizada. Verificando integridad..."
                if verificar_tar "$R_BACKUP"; then
                    echo "✓ ÉXITO: Los originales se han borrado."
                    echo "Resultado: OK" >> "$LOG_ACTUAL"
                    echo "Espacio liberado: ~$TAMANO_TOTAL" >> "$LOG_ACTUAL"
                    echo "Log de auditoría disponible en: $LOG_ACTUAL"
                    CANTIDAD=0
                    TAMANO_TOTAL="0B"
                    > "$LISTA_TEMP" 
                else
                    echo "¡ALERTA! El archivo comprimido podría estar corrupto."
                    echo "Resultado: POSIBLE CORRUPCIÓN - Revisar manualmente" >> "$LOG_ACTUAL"
                fi
            else
                echo "Error durante la compresión."
                echo "Resultado: ERROR EN EJECUCIÓN" >> "$LOG_ACTUAL"
            fi
            ;;
        2)
            echo -e "\nFECHA       | RUTA"
            echo "----------- | ----------------------------------------------"
            cat "$LISTA_TEMP" | sort | less -EX
            ;;
        3)
            read -p "Nueva ruta: " DIR_OBJETIVO
            DIR_OBJETIVO="${DIR_OBJETIVO%/}"
            [ -d "$DIR_OBJETIVO" ] && escanear_directorio || echo "Ruta inválida."
            ;;
        4)
            echo "Saliendo del gestor."
            break
            ;;
        *)
            echo "Opción no válida."
            ;;
    esac
done

rm "$LISTA_TEMP"

