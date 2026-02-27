#!/bin/bash

# Configuración
BASE_DIR="/var/backups/omega/mysqldb"
LOG_FILE="/usr/local/sisma/respaldo/bin/log/compresion.log"

# Crear directorio de log si no existe
mkdir -p "$(dirname "$LOG_FILE")"

echo "$(date '+%H:%M:%S') ###### INICIA COMPRESIÓN DE RESPALDOS #######" >> "$LOG_FILE"

# Entrar al directorio de respaldos
cd "$BASE_DIR" || exit

# Buscar directorios que tengan formato de fecha (YYYY-MM-DD)
# y que no hayan sido comprimidos aún
for dir in */; do
    # Quitar la barra diagonal del nombre
    dir_name="${dir%/}"
    
    # Validar que el nombre sea una fecha (opcional, pero recomendado)
    if [[ "$dir_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        
        echo "$(date '+%H:%M:%S') Comprimiendo: $dir_name..." >> "$LOG_FILE"
        
        # Comprimir la carpeta
        # c: create, z: gzip, f: file
        tar -czf "${dir_name}.tar.gz" "$dir_name"
        
        # Verificar si la compresión fue exitosa antes de borrar
        if [ $? -eq 0 ]; then
            echo "$(date '+%H:%M:%S') Éxito. Borrando carpeta original $dir_name" >> "$LOG_FILE"
            rm -rf "$dir_name"
        else
            echo "$(date '+%H:%M:%S') ERROR al comprimir $dir_name" >> "$LOG_FILE"
        fi
    fi
done

echo "$(date '+%H:%M:%S') ###### PROCESO FINALIZADO #######" >> "$LOG_FILE"