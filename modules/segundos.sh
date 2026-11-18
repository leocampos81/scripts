#!/bin/bash

# Función para solicitar ingreso interactivo si no hay argumento
if [ -z "$1" ]; then
  read -p "Ingresa la cantidad de segundos (o milisegundos con 'ms'): " input
else
  input=$1
fi

# Preguntar si el input está en milisegundos (si no se especificó 'ms' en el input)
if [[ ! "$input" =~ ms$ ]]; then
  read -p "¿El valor ingresado está en milisegundos? (s/n): " respuesta_ms
  if [[ "$respuesta_ms" =~ ^[sS]$ ]]; then
    # Eliminar cualquier texto no numérico y convertir
    input_numerico=$(echo "$input" | grep -o '^[0-9]\+')
    if [ -n "$input_numerico" ]; then
      total_milisegundos=$input_numerico
      total_segundos=$((total_milisegundos / 1000))
      residuo_milisegundos=$((total_milisegundos % 1000))
      echo "Convirtiendo $total_milisegundos milisegundos a $total_segundos segundos y $residuo_milisegundos milisegundos."
    else
      echo "Error: No se pudo extraer un número válido."
      exit 1
    fi
  else
    # Extraer solo el número si hay texto
    total_segundos=$(echo "$input" | grep -o '^[0-9]\+')
  fi
else
  # Si el input termina en 'ms', extraer el número y convertir
  input_numerico=$(echo "$input" | grep -o '^[0-9]\+')
  if [ -n "$input_numerico" ]; then
    total_milisegundos=$input_numerico
    total_segundos=$((total_milisegundos / 1000))
    residuo_milisegundos=$((total_milisegundos % 1000))
    echo "Convirtiendo $total_milisegundos milisegundos a $total_segundos segundos y $residuo_milisegundos milisegundos."
  else
    echo "Error: No se pudo extraer un número válido."
    exit 1
  fi
fi

# Si total_segundos no está definido (por ejemplo, si se respondió 'n' a la pregunta)
if [ -z "$total_segundos" ]; then
  total_segundos=$input_numerico
fi

# Validar que sea un número entero positivo
if ! [[ "$total_segundos" =~ ^[0-9]+$ ]]; then
  echo "Error: Debes ingresar un número entero positivo."
  exit 1
fi

# Cálculos
dias=$(( total_segundos / 86400 ))
resto=$(( total_segundos % 86400 ))

horas=$(( resto / 3600 ))
resto=$(( resto % 3600 ))

minutos=$(( resto / 60 ))
segundos=$(( resto % 60 ))

# Mostrar resultado
echo "$total_segundos segundos equivalen a: $dias días, $horas horas, $minutos minutos y $segundos segundos."

# Mostrar residuo de milisegundos si existe
if [ -n "$residuo_milisegundos" ] && [ "$residuo_milisegundos" -gt 0 ]; then
  echo "Además, hay $residuo_milisegundos milisegundos que no alcanzan a formar un segundo completo."
fi
