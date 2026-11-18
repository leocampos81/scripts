#!/bin/bash

# Nombre del archivo de log
LOG_FILE="/home/leonardo/logs_ssh/apt_updates.log"

# Función para limpiar el output, aunque apt-get no la requiere tanto
clean_apt_output() {
    # apt-get no tiene la advertencia, pero mantenemos esta función si se quiere filtrar algo más.
    # Por ahora, la vaciamos para que no afecte el flujo de apt-get.
    cat
}

# Añadir marca de tiempo al log
echo -e "\n=== Actualización iniciada: $(date) ===" | sudo tee -a "$LOG_FILE" > /dev/null

# Ejecutar actualizaciones
if sudo apt-get update -qq 2> /dev/null | sudo tee -a "$LOG_FILE" > /dev/null && \
    sudo apt-get upgrade -y 2> /dev/null | sudo tee -a "$LOG_FILE" > /dev/null; then

    # Limpiar dependencias innecesarias
    echo -e "\n=== Limpieza de dependencias iniciada ===" | sudo tee -a "$LOG_FILE" > /dev/null
    sudo apt-get autoremove -y 2> /dev/null | sudo tee -a "$LOG_FILE" > /dev/null

    # Cambiar propietario del log (es importante si se ejecutó con sudo)
    sudo chown leonardo:leonardo "$LOG_FILE"

    # Obtener paquetes actualizables de una forma estable
    # Usamos apt-get en modo de simulación y filtramos los paquetes a instalar (Inst).
    upgradable=$(sudo apt-get --simulate upgrade 2>/dev/null | grep '^Inst' | awk '{print $2}')
    
    # Obtener paquetes a eliminar, también de forma estable
    removed=$(sudo apt-get --simulate autoremove 2>/dev/null | grep '^Remv' | awk '{print $2}')

    echo "✅ Repositorios actualizados y dependencias limpiadas"

    if [ -n "$upgradable" ]; then
        echo "Paquetes actualizados:"
        echo "$upgradable"
    else
        echo "No hay paquetes para actualizar"
    fi

    if [ -n "$removed" ]; then
        echo -e "\nPaquetes eliminados (dependencias innecesarias):"
        echo "$removed"
    else
        echo -e "\nNo se eliminaron dependencias innecesarias"
    fi

else
    echo "❌ Fallo al actualizar repositorios (ver $LOG_FILE)" >&2
    exit 1
fi

echo -e "\nSe ha generado log completo en: $LOG_FILE"
