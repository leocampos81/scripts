#!/bin/bash

# --- Función para Comprimir ---
comprimir() {
    clear
    echo "=========================================="
    echo "           COMPRIMIR ARCHIVO/DIRECTORIO   "
    echo "=========================================="
    
    local ORIGEN
    while true; do
        read -r -p "Ruta a comprimir (o 'q' para volver): " ORIGEN
        ORIGEN="${ORIGEN%/}" # Quitar barra final
        
        if [[ "$ORIGEN" == "q" || -z "$ORIGEN" ]]; then
            return 0
        fi
        if [ -e "$ORIGEN" ]; then
            break
        else
            echo "Error: No existe el archivo o directorio '$ORIGEN'."
        fi
    done

    local ARCHIVO
    while true; do
        read -r -p "Nombre del archivo de salida (ej: backup.tar.gz), o 'q' para cancelar: " ARCHIVO
        if [[ "$ARCHIVO" == "q" || -z "$ARCHIVO" ]]; then
            return 0
        fi
        
        if [[ "$ARCHIVO" != *.tar.gz ]]; then
            echo "Error: El nombre debe terminar en .tar.gz"
        else
            break
        fi
    done

    echo ""
    echo "[-] Comprimiendo '$ORIGEN' en '$ARCHIVO' (guardando rutas absolutas)..."
    # Usamos sudo en caso de que el origen requiera permisos
    sudo tar -czvf "$ARCHIVO" --absolute-names "$ORIGEN"
    
    if [ $? -eq 0 ]; then
        echo "[OK] Archivo creado exitosamente: $ARCHIVO"
    else
        echo "[ERROR] Falló la compresión."
    fi
    echo ""
}

# --- Función para Descomprimir ---
descomprimir() {
    clear
    echo "=========================================="
    echo "           DESCOMPRIMIR ARCHIVO           "
    echo "=========================================="
    
    local ARCHIVO
    while true; do
        read -r -p "Nombre del archivo .tar.gz (o 'q' para volver): " ARCHIVO
        if [[ "$ARCHIVO" == "q" || -z "$ARCHIVO" ]]; then
            return 0
        fi
        if [ ! -f "$ARCHIVO" ]; then
            echo "Error: No existe el archivo '$ARCHIVO'."
        else
            break
        fi
    done

    echo ""
    echo "[-] Contenido del archivo (primeras 10 líneas):"
    tar -tzvf "$ARCHIVO" | head -n 10
    echo "..."

    local OPC
    while true; do
        read -r -p "¿Extraer en ruta original (abs) o directorio actual (curr)? [abs/curr/q]: " OPC
        if [[ "$OPC" == "q" || -z "$OPC" ]]; then
            return 0
        fi
        if [[ "$OPC" == "abs" || "$OPC" == "curr" ]]; then
            break
        else
            echo "Opción no válida. Elige 'abs' o 'curr'."
        fi
    done

    echo ""
    if [[ "$OPC" == "abs" ]]; then
        echo "[-] Extrayendo en las rutas absolutas originales (requiere sudo)..."
        sudo tar -xzpvf "$ARCHIVO"
    else
        echo "[-] Extrayendo en el directorio actual (sin las carpetas superiores)..."
        tar -xzvf "$ARCHIVO" --strip-components=1
    fi
    
    if [ $? -eq 0 ]; then
        echo "[OK] Extracción completada."
    else
        echo "[ERROR] Hubo problemas al extraer el archivo."
    fi
    echo ""
}

# --- Bucle Principal ---
while true; do
    clear
    echo "=========================================="
    echo "       COMPRESIÓN / DESCOMPRESIÓN         "
    echo "=========================================="
    echo " c) Comprimir un archivo o carpeta"
    echo " d) Descomprimir un archivo .tar.gz"
    echo " q) Volver al menú anterior"
    echo "=========================================="
    
    read -r -p "Opción [c/d/q]: " OP

    case $OP in
        c|C) comprimir ;;
        d|D) descomprimir ;;
        q|Q) echo "Saliendo..."; break ;;
        *) echo "Opción no válida."; sleep 1 ;;
    esac
    
    # Pausa antes de volver a mostrar el menú interno
    if [[ "$OP" == "c" || "$OP" == "C" || "$OP" == "d" || "$OP" == "D" ]]; then
        echo ""
        read -r -p "Presiona Enter para continuar..."
    fi
done
