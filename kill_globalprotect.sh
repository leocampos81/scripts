#!/bin/bash
# Script para matar todos los procesos de GlobalProtect

echo "Matando procesos de GlobalProtect..."

# Método 1: Usar pkill (recomendado, más flexible)
pkill -9 -f globalprotect

# Método 2 alternativo: Usar killall (requiere nombre exacto)
# killall -9 globalprotect 2>/dev/null

# Verificar si quedan procesos
REMAINING=$(pgrep -f globalprotect | wc -l)

if [ $REMAINING -eq 0 ]; then
    echo "✓ Todos los procesos de GlobalProtect han sido terminados"
else
    echo "⚠ Aún quedan $REMAINING procesos de GlobalProtect ejecutándose"
    pgrep -af globalprotect
fi
