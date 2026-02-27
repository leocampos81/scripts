#!/bin/bash
# ========================================================
# Script de Backup PBX INTERACTIVO - Leonardo Campos
# ========================================================

DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/var/backups/pbx_${DATE}_manual"
LOG="/var/log/backup_pbx_manual.log"
KEEP_DAYS=30

echo "=== [$(date)] INICIO BACKUP PBX INTERACTIVO ===" | tee -a "$LOG"

# ----------------- 0) TAMAÑO PREVIO ------------------------------
echo "-> Calculando tamaños actuales para que decidas..."

DIRS_LIST=(
  /etc
  /srv
  /var/lib/asterisk
  /var/www
  /usr/local/asternic
  /usr/local/ioncube
  /usr/local/sisma
  /var/spool/cron
)

RECORDINGS_DIR=/var/spool/asterisk

echo -e "\n► TAMAÑO DE DIRECTORIOS:"
for dir in "${DIRS_LIST[@]}"; do
  if [ -d "$dir" ]; then
    du -sh "$dir"
  else
    echo "   (NO EXISTE) $dir"
  fi
done

echo -e "\n► TAMAÑO DE GRABACIONES:"
if [ -d "$RECORDINGS_DIR" ]; then
  du -sh "$RECORDINGS_DIR"
else
  echo "   (NO EXISTE) $RECORDINGS_DIR"
fi
echo ""

# ----------------- PREGUNTAS INTERACTIVAS -----------------
read -p "¿Deseas respaldar los DIRECTORIOS? (s/n): " RESP_DIRS
read -p "¿Deseas respaldar las GRABACIONES? (s/n): " RESP_GRAB

if [[ ! "$RESP_DIRS" =~ ^[sS]$ ]] && [[ ! "$RESP_GRAB" =~ ^[sS]$ ]]; then
  echo "⚠️ No seleccionaste nada. Cancelando el respaldo..." | tee -a "$LOG"
  echo "=== [$(date)] FIN (CANCELADO) ===" | tee -a "$LOG"
  exit 0
fi

mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR" || exit 1

# Estados por defecto
DIRS_TAR="OMITIDO"
GRAB_TAR="OMITIDO"
DIRS_RC=0
GRAB_RC=0

# ----------------- 1) DIRECTORIOS -----------------
if [[ "$RESP_DIRS" =~ ^[sS]$ ]]; then
  echo "-> Paso 1: Respaldando DIRECTORIOS..." | tee -a "$LOG"
  tar czf directorios.tar.gz "${DIRS_LIST[@]}" 2>>"$LOG"
  DIRS_RC=$?
  DIRS_TAR=$(tar -tf directorios.tar.gz >/dev/null 2>&1 && echo "OK" || echo "CORRUPTO")
else
  echo "-> Paso 1: Omitiendo DIRECTORIOS..." | tee -a "$LOG"
fi

# ----------------- 2) GRABACIONES -----------------
if [[ "$RESP_GRAB" =~ ^[sS]$ ]]; then
  echo "-> Paso 2: Respaldando GRABACIONES..." | tee -a "$LOG"
  tar czf grabaciones.tar.gz "$RECORDINGS_DIR" 2>>"$LOG"
  GRAB_RC=$?
  GRAB_TAR=$(tar -tf grabaciones.tar.gz >/dev/null 2>&1 && echo "OK" || echo "CORRUPTO")
else
  echo "-> Paso 2: Omitiendo GRABACIONES..." | tee -a "$LOG"
fi

# ----------------- 3) LIMPIEZA -----------------
echo ""
read -p "¿Deseas eliminar los backups MANUALES con más de $KEEP_DAYS días? (s/n): " RESP_CLEAN
if [[ "$RESP_CLEAN" =~ ^[sS]$ ]]; then
  echo "-> Paso 3: Limpiando backups manuales antiguos..." | tee -a "$LOG"
  find /var/backups -maxdepth 1 -type d -name "pbx_*_manual" -mtime +$KEEP_DAYS -print -exec rm -rf {} \; 2>>"$LOG"
else
  echo "-> Paso 3: Omitiendo limpieza." | tee -a "$LOG"
fi

# ----------------- RESUMEN FINAL -----------------
echo "" | tee -a "$LOG"
echo "=== RESUMEN FINAL ($DATE) ===" | tee -a "$LOG"
echo "   Directorio: $BACKUP_DIR" | tee -a "$LOG"

if [[ "$RESP_DIRS" =~ ^[sS]$ ]]; then
  echo "   Directorios.tar.gz: $(du -sh directorios.tar.gz 2>/dev/null || echo '0B') | Integridad → $DIRS_TAR" | tee -a "$LOG"
  echo "   Ruta: $BACKUP_DIR/directorios.tar.gz" | tee -a "$LOG"
fi

if [[ "$RESP_GRAB" =~ ^[sS]$ ]]; then
  echo "   Grabaciones.tar.gz: $(du -sh grabaciones.tar.gz 2>/dev/null || echo '0B') | Integridad → $GRAB_TAR" | tee -a "$LOG"
  echo "   Ruta: $BACKUP_DIR/grabaciones.tar.gz" | tee -a "$LOG"
fi

# Estado global (solo falla si lo seleccionado falló)
EXIT_CODE=0
if [[ "$RESP_DIRS" =~ ^[sS]$ ]]; then
  [[ $DIRS_RC -ne 0 || "$DIRS_TAR" != "OK" ]] && EXIT_CODE=1
fi
if [[ "$RESP_GRAB" =~ ^[sS]$ ]]; then
  [[ $GRAB_RC -ne 0 || "$GRAB_TAR" != "OK" ]] && EXIT_CODE=1
fi

[[ $EXIT_CODE -eq 0 ]] && echo "   🎉 BACKUP MANUAL COMPLETO Y VÁLIDO ✅" | tee -a "$LOG" || echo "   ⚠️  BACKUP MANUAL PARCIAL/CORRUPTO ❌" | tee -a "$LOG"
echo "=== [$(date)] FIN ===" | tee -a "$LOG"

exit $EXIT_CODE
