#!/bin/bash

# Este script desactiva y reactiva la memoria swap para liberar el espacio.
# Requiere permisos de superusuario (sudo).

echo "Iniciando el proceso de limpieza de la memoria swap..."

# Desactiva la memoria swap. Esto mueve los datos de swap de nuevo a la RAM.
echo "Desactivando la memoria swap..."
sudo swapoff -a

# Verifica si el comando anterior fue exitoso.
if [ $? -eq 0 ]; then
    echo "Memoria swap desactivada correctamente."
else
    echo "Error: No se pudo desactivar la memoria swap. Asegúrate de tener permisos de sudo."
    exit 1
fi

# Reactiva la memoria swap. Esto limpia el espacio en el disco.
echo "Reactivando la memoria swap..."
sudo swapon -a

# Verifica si el comando fue exitoso.
if [ $? -eq 0 ]; then
    echo "Memoria swap reactivada correctamente. El uso debería ser 0%."
    echo "Proceso completado."
else
    echo "Error: No se pudo reactivar la memoria swap."
    exit 1
fi

exit 0

