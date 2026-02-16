#!/bin/bash

# Función para validar el formato de hora HH:MM:SS
validar_hora() {
    # El patrón regex para HH:MM:SS
    # ^: inicio de la cadena
    # ([01]?[0-9]|2[0-3]): horas (00-23), opcionalmente con un cero inicial
    # : : separador de minutos
    # ([0-5]?[0-9]): minutos (00-59), opcionalmente con un cero inicial
    # : : separador de segundos
    # ([0-5]?[0-9]): segundos (00-59), opcionalmente con un cero inicial
    # $: fin de la cadena
    local regex="^([01]?[0-9]|2[0-3]):([0-5]?[0-9]):([0-5]?[0-9])$"
    if [[ $1 =~ $regex ]]; then
        return 0 # Hora válida
    else
        return 1 # Hora no válida
    fi
}

# Solicitar al usuario que ingrese la hora inicial y validar
while true; do
    read -p "Ingrese la hora inicial (HH:MM:SS): " HORA_INICIO_STR
    if validar_hora "$HORA_INICIO_STR"; then
        break
    else
        echo "Formato de hora inválido. Por favor, use el formato HH:MM:SS."
    fi
done

# Solicitar al usuario que ingrese la hora final y validar
while true; do
    read -p "Ingrese la hora final (HH:MM:SS): " HORA_FIN_STR
    if validar_hora "$HORA_FIN_STR"; then
        break
    else
        echo "Formato de hora inválido. Por favor, use el formato HH:MM:SS."
    fi
done

# Convertir las horas a segundos Unix
SEGUNDOS_INICIO=$(date -d "1970-01-01 $HORA_INICIO_STR" +%s)
SEGUNDOS_FIN=$(date -d "1970-01-01 $HORA_FIN_STR" +%s)

# Calcular la diferencia en segundos
DIFERENCIA_SEGUNDOS=$((SEGUNDOS_FIN - SEGUNDOS_INICIO))

# Si la diferencia es negativa, asume que es el día siguiente y ajusta
if [ "$DIFERENCIA_SEGUNDOS" -lt 0 ]; then
    DIFERENCIA_SEGUNDOS=$((DIFERENCIA_SEGUNDOS + 86400)) # 86400 segundos en un día
fi

# Convertir la diferencia de segundos de vuelta a formato de hora:minuto:segundo
RESULTADO=$(date -u -d @"$DIFERENCIA_SEGUNDOS" +"%H:%M:%S")

# Mostrar el resultado
echo ""
echo "--- Resultado ---"
echo "Hora Inicial: $HORA_INICIO_STR"
echo "Hora Final:   $HORA_FIN_STR"
echo "La diferencia es: $RESULTADO"
echo "-----------------"
