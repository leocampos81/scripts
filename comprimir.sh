#!/bin/bash

# Script para comprimir y luego descomprimir manteniendo rutas originales

function comprimir() {
    read -p "Ingresa la ruta del archivo o directorio a comprimir: " ORIGEN
    if [ ! -e "$ORIGEN" ]; then
        echo "No existe el archivo o directorio: $ORIGEN"
        exit 1
    fi

    read -p "Nombre para el archivo comprimido (ejemplo: backup.tar.gz): " ARCHIVO
    
    # Validar que termine en .tar.gz
    if [[ "$ARCHIVO" != *.tar.gz ]]; then
        echo "El nombre debe terminar en .tar.gz"
        exit 1
    fi

    echo "Comprimiendo '$ORIGEN' en archivo $ARCHIVO guardando rutas absolutas..."
    # Comprimir con ruta absoluta
    tar -czvf "$ARCHIVO" --absolute-names "$ORIGEN"
    echo "Archivo creado: $ARCHIVO"
}

function descomprimir() {
    read -p "Ingresa el nombre del archivo tar.gz a descomprimir: " ARCHIVO
    if [ ! -f "$ARCHIVO" ]; then
        echo "No existe el archivo: $ARCHIVO"
        exit 1
    fi

    # Mostrar contenido para confirmar rutas
    echo "Contenido del archivo:"
    tar -tzvf "$ARCHIVO"

    # Preguntar dónde extraer
    read -p "¿Extraer en la ruta original (abs) o en el directorio actual (curr)? [abs/curr]: " OPC

    if [[ "$OPC" == "abs" ]]; then
        echo "Extrayendo en las rutas absolutas originales..."
        sudo tar -xzpvf "$ARCHIVO"
    else
        echo "Extrayendo en el directorio actual con rutas relativas..."
        tar -xzvf "$ARCHIVO" --strip-components=1
    fi
}

while true; do
    echo "Seleccione acción:"
    echo "  c - Comprimir"
    echo "  d - Descomprimir"
    echo "  q - Salir"
    read -p "Opción: " OP

    case $OP in
        c) comprimir ;;
        d) descomprimir ;;
        q) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción no válida" ;;
    esac
    echo ""
done

