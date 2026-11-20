#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: DATA  -  bases de datos: detección, listado y ejecución de SQL con guardarraíles
#  Se carga con 'source' desde prom_claude.sh (no se ejecuta directamente).
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

detect_db_engines() {
    DB_FOUND=0
    local v
    if find_sqlcmd &>/dev/null || proc_running sqlservr; then
        print " [ OK ] Microsoft SQL Server (sqlcmd o proceso detectado)"; DB_FOUND=1
    fi
    if command -v mysql &>/dev/null || proc_running mysqld || proc_running mariadbd; then
        v=$(mysql --version 2>/dev/null | cut -c1-60)
        print -r -- " [ OK ] MySQL/MariaDB ${v:+(cliente: $v)}"; DB_FOUND=1
    fi
    if command -v psql &>/dev/null || proc_running postgres; then
        v=$(psql --version 2>/dev/null)
        print -r -- " [ OK ] PostgreSQL ${v:+(cliente: $v)}"; DB_FOUND=1
    fi
    if command -v mongod &>/dev/null || proc_running mongod; then
        v=$(mongod --version 2>/dev/null | head -n1)
        print -r -- " [ OK ] MongoDB ${v:+($v)}"; DB_FOUND=1
    fi
    if command -v redis-server &>/dev/null || proc_running redis-server; then
        v=$(redis-server --version 2>/dev/null | awk '{print $3}')
        print -r -- " [ OK ] Redis ${v:+($v)}"; DB_FOUND=1
    fi
}

db_detect() {
    msg_info "Buscando motores de base de datos instalados..."
    detect_db_engines
    (( DB_FOUND == 0 )) && print "  (ninguno detectado)"
}

db_show() {   # db_show "<salida de versión>" "<salida de bases>"
    print -r -- "--- VERSIÓN ---"
    print -r -- "$1" | head -n 1
    print ""
    print -r -- "--- BASES DE DATOS ---"
    print -r -- "$2" | sed '/^[[:space:]]*$/d; s/^/  > /'
}

db_mssql() {
    local bin
    if ! bin=$(find_sqlcmd); then
        msg_warn "'sqlcmd' no está instalado."; install_hint sqlcmd; return 0
    fi
    local -a extra=()
    # mssql-tools18 cifra por defecto: con certificado autofirmado exige -C
    "$bin" '-?' 2>&1 | grep -qE 'Version (1[7-9]|[2-9][0-9])' && extra=(-C)

    local host user pass out rc dbs
    prompt_input "Servidor [Default: localhost]: " host;   host="${host:-localhost}"
    prompt_input "Usuario [Default: sa]: " user;           user="${user:-sa}"
    prompt_password "Contraseña: " pass
    [[ -z "$pass" ]] && { msg_err "SQL Server requiere contraseña."; return 0; }
    valid_host "$host" || { msg_err "Servidor no válido."; return 0; }

    msg_info "Consultando versión y bases de datos en $host..."
    out=$(SQLCMDPASSWORD="$pass" "$bin" -S "$host" -U "$user" "${extra[@]}" -l 5 -h -1 -W \
          -Q "SET NOCOUNT ON; SELECT @@VERSION" 2>&1); rc=$?
    if (( rc != 0 )) || [[ "$out" == *"Sqlcmd: Error"* || "$out" == *"Msg "* ]]; then
        msg_err "No se pudo conectar a SQL Server."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        print "        Revisa credenciales, que 'mssql-server' esté activo y el puerto 1433."
        log_action "BBDD: fallo de conexión SQL Server ($host)"
        return 0
    fi
    dbs=$(SQLCMDPASSWORD="$pass" "$bin" -S "$host" -U "$user" "${extra[@]}" -l 5 -h -1 -W \
          -Q "SET NOCOUNT ON; SELECT name FROM sys.databases ORDER BY name" 2>&1)
    db_show "$out" "$dbs"
    log_action "BBDD: consulta SQL Server ($host)"
}

db_mysql() {
    need mysql || return 0
    local user pass out rc dbs
    prompt_input "Usuario [Default: root]: " user; user="${user:-root}"
    prompt_password "Contraseña (vacía = auth por socket con sudo): " pass
    valid_ident "$user" || { msg_err "Usuario no válido."; return 0; }

    local -a my=(mysql -u "$user" -N -B)
    [[ -z "$pass" ]] && my=("${SUDO[@]}" "${my[@]}")

    msg_info "Consultando versión y bases de datos..."
    out=$(MYSQL_PWD="$pass" "${my[@]}" -e "SELECT VERSION();" 2>&1); rc=$?
    if (( rc != 0 )); then
        msg_err "No se pudo conectar a MySQL/MariaDB."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        print "        Revisa credenciales o que el servicio (mysqld/mariadb) esté activo."
        log_action "BBDD: fallo de conexión MySQL/MariaDB"
        return 0
    fi
    dbs=$(MYSQL_PWD="$pass" "${my[@]}" -e "SHOW DATABASES;" 2>&1)
    db_show "$out" "$dbs"
    log_action "BBDD: consulta MySQL/MariaDB"
}

db_pg() {
    need psql || return 0
    local user dbname pass out rc dbs
    prompt_input "Usuario [Default: postgres]: " user;      user="${user:-postgres}"
    prompt_input "Base de datos [Default: postgres]: " dbname; dbname="${dbname:-postgres}"
    prompt_password "Contraseña (vacía = auth local 'peer' como ese usuario): " pass
    valid_ident "$user" && valid_ident "$dbname" || { msg_err "Usuario o base no válidos."; return 0; }

    local -a pg
    if [[ -n "$pass" ]]; then
        pg=(psql -h localhost -U "$user" -d "$dbname" -At)
    elif (( EUID == 0 )); then
        pg=(runuser -u "$user" -- psql -d "$dbname" -At)
    else
        pg=(sudo -u "$user" psql -d "$dbname" -At)
    fi

    msg_info "Consultando versión y bases de datos..."
    out=$(PGPASSWORD="$pass" "${pg[@]}" -c "SELECT version();" 2>&1); rc=$?
    if (( rc != 0 )); then
        msg_err "No se pudo conectar a PostgreSQL."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        print "        Revisa usuario/base, contraseña o que el servicio (postgresql) esté activo."
        log_action "BBDD: fallo de conexión PostgreSQL"
        return 0
    fi
    dbs=$(PGPASSWORD="$pass" "${pg[@]}" -c "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1;" 2>&1)
    db_show "$out" "$dbs"
    log_action "BBDD: consulta PostgreSQL"
}

# --- Ejecución de SQL (archivos y consultas) con guardarraíles ----------------
# Conexión en variables globales SQL_*; la clave se borra al salir de la sesión.
typeset -ga SQL_CMD SQL_EXTRA
SQL_BIN=""; SQL_HOST=""; SQL_USER=""; SQL_PASS=""; SQL_DB=""; SQL_LABEL=""; SQL_TX=0

_sql_q_mssql() {
    local -a dbarg=(); [[ -n "$SQL_DB" ]] && dbarg=(-d "$SQL_DB")
    SQLCMDPASSWORD="$SQL_PASS" "$SQL_BIN" -S "$SQL_HOST" -U "$SQL_USER" "${SQL_EXTRA[@]}" "${dbarg[@]}" \
        -l 5 -b -W -s '|' -Q "SET NOCOUNT ON; $1" 2>&1
}
_sql_f_mssql() {
    local -a dbarg=(); [[ -n "$SQL_DB" ]] && dbarg=(-d "$SQL_DB")
    SQLCMDPASSWORD="$SQL_PASS" "$SQL_BIN" -S "$SQL_HOST" -U "$SQL_USER" "${SQL_EXTRA[@]}" "${dbarg[@]}" \
        -l 5 -b -i "$1" 2>&1
}
_sql_q_mysql() {
    local -a d=(); [[ -n "$SQL_DB" ]] && d=("$SQL_DB")
    MYSQL_PWD="$SQL_PASS" "${SQL_CMD[@]}" -t "${d[@]}" -e "$1" 2>&1
}
_sql_f_mysql() {   # redirección por stdin: sirve aunque el cliente corra vía sudo
    local -a d=(); [[ -n "$SQL_DB" ]] && d=("$SQL_DB")
    MYSQL_PWD="$SQL_PASS" "${SQL_CMD[@]}" "${d[@]}" < "$1" 2>&1
}
_sql_q_pg() {
    PGPASSWORD="$SQL_PASS" "${SQL_CMD[@]}" -v ON_ERROR_STOP=1 -c "$1" 2>&1
}
_sql_f_pg() {      # stdin: el usuario 'postgres' no puede leer archivos de tu /home
    local -a tx=(); (( SQL_TX )) && tx=(-1)
    PGPASSWORD="$SQL_PASS" "${SQL_CMD[@]}" -v ON_ERROR_STOP=1 "${tx[@]}" -f - < "$1" 2>&1
}

# Pide confirmación si el SQL modifica datos/estructura. Retorna 0 = continuar.
sql_guard() {
    local q="$1" typed
    local re_mod='(^|[^[:alnum:]_])(drop|delete|update|truncate|alter|insert|create|grant|revoke|merge|exec|execute|shutdown|xp_cmdshell)([^[:alnum:]_]|$)'
    local re_dml='(^|[^[:alnum:]_])(delete|update)([^[:alnum:]_]|$)'
    local re_whr='(^|[^[:alnum:]_])where([^[:alnum:]_]|$)'
    print -r -- "$q" | grep -qiE "$re_mod" || return 0

    msg_warn "Se detectaron sentencias que MODIFICAN datos o estructura."
    if print -r -- "$q" | grep -qiE "$re_dml" && ! print -r -- "$q" | grep -qiE "$re_whr"; then
        msg_warn "DELETE/UPDATE SIN cláusula WHERE: afectaría TODAS las filas."
        prompt_input "Escribe CONFIRMAR para continuar: " typed
        [[ "$typed" == CONFIRMAR ]]
        return $?
    fi
    confirm "¿Ejecutar de todos modos?"
}

# Menú de la sesión SQL:  sql_loop mssql|mysql|pg
sql_loop() {
    local eng="$1" mode f q n
    while true; do
        print ""
        print " 1) Ejecutar archivo .sql"
        print " 2) Ejecutar consulta rápida"
        print " q) Volver al menú de BBDD   [conectado a: $SQL_LABEL]"
        prompt_input "Selecciona modo [1-2 o q]: " mode || break
        case "$mode" in
            1)
                prompt_input "Ruta del archivo .sql: " f
                [[ -z "$f" ]] && continue
                [[ -f "$f" && -r "$f" ]] || { msg_err "El archivo no existe o no es legible."; continue; }
                n=$(wc -l < "$f" | tr -d ' ')
                sql_guard "$(cat -- "$f")" || { msg_info "Cancelado."; continue; }
                confirm "¿Ejecutar '${f:t}' ($n líneas) en $SQL_LABEL?" || { msg_info "Cancelado."; continue; }
                SQL_TX=0
                if [[ "$eng" == pg ]] && confirm "¿En una sola transacción (rollback si algo falla)?"; then SQL_TX=1; fi
                msg_info "Ejecutando '${f:t}'..."
                "_sql_f_$eng" "$f"
                log_action "BBDD($eng): archivo ${f:t} en $SQL_LABEL (rc=$?)"
                ;;
            2)
                prompt_input "Consulta SQL: " q
                [[ -z "$q" ]] && { msg_warn "Consulta vacía."; continue; }
                sql_guard "$q" || { msg_info "Cancelado."; continue; }
                "_sql_q_$eng" "$q"
                log_action "BBDD($eng): consulta rápida en $SQL_LABEL (rc=$?)"
                ;;
            q|Q|"") break ;;
            *) msg_warn "Modo no válido." ;;
        esac
    done
}

db_mssql_exec() {
    local bin host user pass dbn out rc
    if ! bin=$(find_sqlcmd); then msg_warn "'sqlcmd' no está instalado."; install_hint sqlcmd; return 0; fi
    SQL_EXTRA=()
    "$bin" '-?' 2>&1 | grep -qE 'Version (1[7-9]|[2-9][0-9])' && SQL_EXTRA=(-C)

    prompt_input "Servidor [Default: localhost]: " host;  host="${host:-localhost}"
    prompt_input "Usuario [Default: sa]: " user;          user="${user:-sa}"
    prompt_password "Contraseña: " pass
    prompt_input "Base de datos [Enter = la predeterminada del login]: " dbn
    [[ -z "$pass" ]] && { msg_err "SQL Server requiere contraseña."; return 0; }
    valid_host "$host" || { msg_err "Servidor no válido."; return 0; }
    [[ -n "$dbn" ]] && ! valid_ident "$dbn" && { msg_err "Nombre de base no válido."; return 0; }

    SQL_BIN="$bin"; SQL_HOST="$host"; SQL_USER="$user"; SQL_PASS="$pass"; SQL_DB="$dbn"
    SQL_LABEL="$host${dbn:+/$dbn}"
    out=$(_sql_q_mssql "SELECT 1 AS ok"); rc=$?
    if (( rc != 0 )) || [[ "$out" == *"Sqlcmd: Error"* || "$out" == *"Msg "* ]]; then
        msg_err "No se pudo conectar a SQL Server."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        log_action "BBDD(mssql): fallo de conexión en $SQL_LABEL"
        SQL_PASS=""; return 0
    fi
    msg_ok "Conectado a $SQL_LABEL"
    sql_loop mssql
    SQL_PASS=""
}

db_mysql_exec() {
    need mysql || return 0
    local user pass dbn out rc
    prompt_input "Usuario [Default: root]: " user; user="${user:-root}"
    prompt_password "Contraseña (vacía = auth por socket con sudo): " pass
    prompt_input "Base de datos [Enter = ninguna]: " dbn
    valid_ident "$user" || { msg_err "Usuario no válido."; return 0; }
    [[ -n "$dbn" ]] && ! valid_ident "$dbn" && { msg_err "Nombre de base no válido."; return 0; }

    SQL_CMD=(mysql -u "$user")
    [[ -z "$pass" ]] && SQL_CMD=("${SUDO[@]}" "${SQL_CMD[@]}")
    SQL_PASS="$pass"; SQL_DB="$dbn"; SQL_LABEL="mysql:$user${dbn:+/$dbn}"
    out=$(_sql_q_mysql "SELECT 1 AS ok"); rc=$?
    if (( rc != 0 )); then
        msg_err "No se pudo conectar a MySQL/MariaDB."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        log_action "BBDD(mysql): fallo de conexión ($SQL_LABEL)"
        SQL_PASS=""; return 0
    fi
    msg_ok "Conectado a $SQL_LABEL"
    sql_loop mysql
    SQL_PASS=""
}

db_pg_exec() {
    need psql || return 0
    local user dbname pass out rc
    prompt_input "Usuario [Default: postgres]: " user;        user="${user:-postgres}"
    prompt_input "Base de datos [Default: postgres]: " dbname; dbname="${dbname:-postgres}"
    prompt_password "Contraseña (vacía = auth local 'peer' como ese usuario): " pass
    valid_ident "$user" && valid_ident "$dbname" || { msg_err "Usuario o base no válidos."; return 0; }

    if [[ -n "$pass" ]]; then   SQL_CMD=(psql -h localhost -U "$user" -d "$dbname")
    elif (( EUID == 0 )); then  SQL_CMD=(runuser -u "$user" -- psql -d "$dbname")
    else                        SQL_CMD=(sudo -u "$user" psql -d "$dbname")
    fi
    SQL_PASS="$pass"; SQL_LABEL="pg:$user/$dbname"
    out=$(_sql_q_pg "SELECT 1 AS ok"); rc=$?
    if (( rc != 0 )); then
        msg_err "No se pudo conectar a PostgreSQL."
        print -r -- "$out" | head -n 3 | sed 's/^/        /'
        log_action "BBDD(pg): fallo de conexión ($SQL_LABEL)"
        SQL_PASS=""; return 0
    fi
    msg_ok "Conectado a $SQL_LABEL"
    sql_loop pg
    SQL_PASS=""
}

menu_db() {
    run_menu "GESTIÓN DE BASES DE DATOS (BBDD)" \
        "Detectar motores instalados|db_detect" \
        "#SQL SERVER (MSSQL)" \
        "Listar BBDD|db_mssql" \
        "Ejecutar script .sql / consulta|db_mssql_exec|nopause" \
        "#MYSQL / MARIADB" \
        "Listar BBDD|db_mysql" \
        "Ejecutar script .sql / consulta|db_mysql_exec|nopause" \
        "#POSTGRESQL" \
        "Listar BBDD|db_pg" \
        "Ejecutar script .sql / consulta|db_pg_exec|nopause"
}
