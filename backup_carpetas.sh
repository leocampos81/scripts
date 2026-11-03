#!/bin/bash

# =============================================================================
# Script de Backup PBX - Leonardo Campos (interactivo por carpeta)
# =============================================================================

DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/var/backups/pbx_$DATE"
LOG="/var/log/backup_pbx.log"
KEEP_DAYS=30

echo "=== [$(date)] INICIO BACKUP PBX ===" | tee -a "$LOG"

mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR" || exit 1

# ----------------- LISTAS -----------------

CONFIGS_LIST=(
/etc
/srv
/var/lib/asterisk
/var/www
/usr/local/asternic
/usr/local/ioncube
/usr/local/sisma
/var/spool/cron
)

RECORDINGS_DIR="/var/spool/asterisk"

# ----------------- 0) TAMAÑO PREVIO -----------------

echo "-> Paso 0: TAMAÑOS DE CARPETAS A RESPALDAR:" | tee -a "$LOG"
echo "" | tee -a "$LOG"

echo "► CONFIGURACIONES:" | tee -a "$LOG"
for dir in "${CONFIGS_LIST[@]}"; do
  if [ -d "$dir" ]; then
    du -sh "$dir" | tee -a "$LOG"
  else
    echo " (NO EXISTE) $dir" | tee -a "$LOG"
  fi
done

echo "" | tee -a "$LOG"
echo "► GRABACIONES:" | tee -a "$LOG"
if [ -d "$RECORDINGS_DIR" ]; then
  du -sh "$RECORDINGS_DIR" | tee -a "$LOG"
else
  echo " (NO EXISTE) $RECORDINGS_DIR" | tee -a "$LOG"
fi
echo "" | tee -a "$LOG"

# ----------------- MENÚ DE CONFIGS -----------------

echo "-> Seleccionar carpetas de CONFIGURACIONES a respaldar:"
i=1
for dir in "${CONFIGS_LIST[@]}"; do
  echo "  $i) $dir"
  ((i++))
done
echo ""
read -p "Ingrese números separados por espacio (ej: 1 3 5, o vacío para ninguna): " SELECCION

SELECTED_DIRS=()
if [ -n "$SELECCION" ]; then
  for idx in $SELECCION; do
    # Ajuste índice (1-based a 0-based)
    real_idx=$((idx-1))
    if [ $real_idx -ge 0 ] && [ $real_idx -lt ${#CONFIGS_LIST[@]} ]; then
      dir="${CONFIGS_LIST[$real_idx]}"
      if [ -d "$dir" ]; then
        SELECTED_DIRS+=("$dir")
      else
        echo "(!) Ignorando $dir (no existe)" | tee -a "$LOG"
      fi
    else
      echo "(!) Opción inválida: $idx" | tee -a "$LOG"
    fi
  done
fi

# ----------------- 1) RESPALDO CONFIGS (SEPARADO) -----------------

echo "-> Paso 1/3: Respaldando CONFIGURACIONES SELECCIONADAS..." | tee -a "$LOG"

CONFIGS_RC=0

if [ ${#SELECTED_DIRS[@]} -eq 0 ]; then
  echo "No se seleccionó ninguna carpeta de configuraciones. Saltando este paso." | tee -a "$LOG"
else
  for dir in "${SELECTED_DIRS[@]}"; do
    base_name=$(echo "$dir" | sed 's#^/##; s#/#_#g')
    tar_name="config_${base_name}.tar.gz"
    echo "  -> Comprimiendo $dir -> $tar_name" | tee -a "$LOG"
    tar czf "$tar_name" "$dir" 2>>"$LOG"
    rc=$?
    [ $rc -ne 0 ] && CONFIGS_RC=$rc
  done
fi

# ----------------- 2) GRABACIONES (PREGUNTA) -----------------

echo "-> Paso 2/3: Respaldando GRABACIONES..." | tee -a "$LOG"

GRAB_RC=0
GRAB_TAR_STATE="NO_BACKUP"

if [ -d "$RECORDINGS_DIR" ]; then
  read -p "¿Desea respaldar las grabaciones en $RECORDINGS_DIR? (s/n): " RESP_GRAB

  case "$RESP_GRAB" in
    s|S|y|Y)
      GRAB_TAR="grabaciones.tar.gz"
      echo "  -> Comprimiendo $RECORDINGS_DIR -> $GRAB_TAR" | tee -a "$LOG"
      tar czf "$GRAB_TAR" "$RECORDINGS_DIR" 2>>"$LOG"
      GRAB_RC=$?
      if [ $GRAB_RC -eq 0 ]; then
        GRAB_TAR_STATE=$(tar -tf "$GRAB_TAR" >/dev/null 2>&1 && echo "OK" || echo "CORRUPTO")
      else
        GRAB_TAR_STATE="ERROR_TAR"
      fi
      ;;
    *)
      echo "  -> No se respaldarán grabaciones." | tee -a "$LOG"
      ;;
  esac
else
  echo "  -> Carpeta de grabaciones no existe. Saltando." | tee -a "$LOG"
fi

# ----------------- 3) LIMPIEZA -----------------

echo "-> Paso 3/3: Limpiando backups antiguos..." | tee -a "$LOG"
find /var/backups -maxdepth 1 -type d -name "pbx_*" -mtime +$KEEP_DAYS -print -exec rm -rf {} \; 2>>"$LOG"

# ----------------- 4) VALIDACIÓN CONFIGS -----------------

echo "-> VALIDANDO INTEGRIDAD DE CONFIGS..." | tee -a "$LOG"

for f in config_*.tar.gz; do
  [ ! -e "$f" ] && continue
  state=$(tar -tf "$f" >/dev/null 2>&1 && echo "OK" || echo "CORRUPTO")
  echo "  $f -> $state" | tee -a "$LOG"
done

# ----------------- RESUMEN FINAL -----------------

echo "" | tee -a "$LOG"
echo "=== RESUMEN FINAL ($DATE) ===" | tee -a "$LOG"

for f in config_*.tar.gz; do
  [ ! -e "$f" ] && continue
  echo " $(du -sh "$f" 2>/dev/null || echo '0B')" | tee -a "$LOG"
done

if [ -f "$GRAB_TAR" ]; then
  echo " $GRAB_TAR: $(du -sh "$GRAB_TAR" 2>/dev/null || echo '0B') (estado: $GRAB_TAR_STATE)" | tee -a "$LOG"
else
  echo " Grabaciones: NO RESPALDADAS ($GRAB_TAR_STATE)" | tee -a "$LOG"
fi

echo "=== [$(date)] FIN ===" | tee -a "$LOG"
