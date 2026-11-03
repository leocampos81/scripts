#!/bin/bash
DB_USER="sisma"
DB_PASS="sismasoluciones802"

echo "🎯 Restauración Inteligente - $(date)"
echo "=================================="

# Detectar y crear DBs
for sql in *.sql; do
  # Extraer nombre DB del archivo (asteriskcdrdb.sql → asteriskcdrdb)
  DB=$(basename "$sql" .sql | sed 's/\.[^.]*$//')
  
  echo "📦 Procesando: $sql → DB: $DB"
  
  # Crear DB si no existe
  mysql -u$DB_USER -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS \`$DB\`;"
  
  # Importar
  mysql -u$DB_USER -p$DB_PASS "$DB" < "$sql" && \
    echo "✅ $DB OK" || echo "❌ $DB ERROR"
done

echo "✅ ¡Finalizado!"
mysql -u$DB_USER -p$DB_PASS -e "SHOW DATABASES;" | grep -v "information_schema"

