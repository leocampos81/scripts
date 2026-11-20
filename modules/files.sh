#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: FILES  -  archivos, texto, espacio en disco y compresión
#  Se carga con 'source' desde prom_claude.sh (no se ejecuta directamente).
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

act_edit() {
    local -a editors=()
    local e choice target n=1
    for e in nvim vim nano vi; do command -v "$e" &>/dev/null && editors+=("$e"); done
    if (( ${#editors} == 0 )); then msg_err "No hay editores instalados (nvim/vim/nano/vi)."; return 0; fi
    for e in "${editors[@]}"; do print " $n) $e"; n=$(( n + 1 )); done
    prompt_input "Selecciona el editor [1-${#editors}]: " choice
    [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#editors} )) || choice=1
    e="${editors[$choice]}"

    prompt_input "Ruta del archivo a editar: " target
    [[ -z "$target" ]] && return 0
    if [[ -e "$target" && ! -w "$target" ]] || [[ ! -e "$target" && ! -w "${target:h}" ]]; then
        if confirm "Sin permiso de escritura en '$target'. ¿Abrir con sudo?"; then
            "${SUDO[@]}" "$e" "$target"
            log_action "Editor: (sudo) abierto $target"
            return 0
        fi
    fi
    "$e" "$target"
    log_action "Editor: abierto $target"
}

act_grep() {
    local lf pattern
    prompt_input "Ruta del archivo (ej: /var/log/syslog): " lf
    [[ -z "$lf" ]] && return 0
    if [[ ! -f "$lf" ]]; then msg_err "El archivo '$lf' no existe."; return 0; fi
    prompt_input "Patrón (regex extendida, ej: ERROR|FAIL): " pattern
    [[ -z "$pattern" ]] && return 0
    local -a cmd=(grep -inE -- "$pattern" "$lf")
    [[ ! -r "$lf" ]] && cmd=("${SUDO[@]}" "${cmd[@]}")
    msg_info "Primeras 50 coincidencias en '$lf':"
    "${cmd[@]}" | head -n 50
    log_action "Grep: '$pattern' en $lf"
}

act_fileinfo() {
    local f
    prompt_input "Ruta del archivo a analizar: " f
    [[ -z "$f" ]] && return 0
    if [[ ! -f "$f" ]]; then msg_err "El archivo no existe."; return 0; fi

    local ftype fsize fperm fowner fmod facc fcre fchg hash
    ftype=$(file -b "$f" 2>/dev/null); ftype="${ftype:-N/D}"
    fsize=$(stat -c %s "$f" 2>/dev/null)
    fperm=$(stat -c "%A (%a)" "$f" 2>/dev/null)
    fowner=$(stat -c "%U:%G" "$f" 2>/dev/null)
    fmod=$(stat -c %y "$f" 2>/dev/null)
    facc=$(stat -c %x "$f" 2>/dev/null)
    fchg=$(stat -c %z "$f" 2>/dev/null)
    fcre=$(stat -c %w "$f" 2>/dev/null)
    [[ -z "$fcre" || "$fcre" == "-" ]] && fcre="No disponible (FS)"
    hash=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')

    # wc imprime SIEMPRE: líneas, palabras, caracteres, bytes (se piden por separado)
    local n_lines n_words n_chars n_bytes
    n_lines=$(( $(wc -l < "$f") )); n_words=$(( $(wc -w < "$f") ))
    n_chars=$(( $(wc -m < "$f") )); n_bytes=$(( $(wc -c < "$f") ))

    local awk_out max_len empty avg
    awk_out=$(awk '{ l=length($0); if (l>max) max=l; if (l==0) empty++ } END { print max+0, empty+0 }' "$f")
    max_len="${awk_out%% *}"; empty="${awk_out##* }"
    avg=$(awk -v w="$n_words" -v l="$n_lines" 'BEGIN{ if (l>0) printf "%.2f", w/l; else print "0.00" }')

    print ""
    box_open "ANÁLISIS TÉCNICO DE ARCHIVO"
    box_text "IDENTIDAD"
    box_sep
    box_row "Tipo" "$ftype"
    box_row "Tamaño" "$(human_bytes $fsize) ($fsize bytes)"
    box_row "Permisos" "$fperm"
    box_row "Propietario" "$fowner"
    box_sep
    box_text "FECHAS"
    box_sep
    box_row "Modificado" "$fmod"
    box_row "Accedido" "$facc"
    box_row "Cambio (ctime)" "$fchg"
    box_row "Creado" "$fcre"
    box_sep
    box_text "CONTENIDO"
    box_sep
    box_row "Líneas" "$n_lines"
    box_row "Palabras" "$n_words"
    box_row "Caracteres" "$n_chars"
    box_row "Bytes" "$n_bytes"
    box_row "Línea + larga" "$max_len caracteres"
    box_row "Líneas vacías" "$empty"
    box_row "Palabras/línea" "$avg"
    box_close
    print -r -- " SHA256: ${hash:-N/D}"
    log_action "Info: análisis técnico de $f"
}

act_diff() {
    local f1 f2
    prompt_input "Ruta del Archivo 1: " f1
    prompt_input "Ruta del Archivo 2: " f2
    if [[ -f "$f1" && -f "$f2" ]]; then
        msg_info "Diferencias (diff -u):"
        diff -u -- "$f1" "$f2" || true
        log_action "Diff: $f1 vs $f2"
    else
        msg_err "Uno o ambos archivos no existen."
    fi
}

act_rsync() {
    need rsync || return 0
    local src dst
    prompt_input "Directorio o archivo origen: " src
    prompt_input "Destino (user@host:/ruta o /ruta): " dst
    [[ -z "$src" || -z "$dst" ]] && return 0
    msg_info "Simulación previa (rsync -avhn):"
    rsync -avhn -- "$src" "$dst" || { msg_err "La simulación falló."; return 0; }
    confirm "¿Ejecutar la sincronización real?" || return 0
    rsync -avh --progress -- "$src" "$dst"
    log_action "Rsync: $src -> $dst"
}

# ==============================================================================
#  ESPACIO: archivos más pesados y compresión segura   (reemplaza a espacio.sh)
#  Mejoras: sin 'eval' (arrays), comprime -> VALIDA -> recién entonces borra el
#  original (opcional), y omite archivos abiertos por procesos (logs, BD, VMs).
# ==============================================================================
# ¿Algún proceso tiene abierto el archivo?  (fuser no admite '--': no usarlo)
file_in_use() {
    if command -v fuser &>/dev/null; then
        "${SUDO[@]}" fuser -s "$1" 2>/dev/null
    elif command -v lsof &>/dev/null; then
        [[ -n "$("${SUDO[@]}" lsof -t "$1" 2>/dev/null)" ]]
    else
        return 1
    fi
}

# Comprime un archivo a <archivo>.tar.gz. $2 = 1 para borrar el original tras validar.
espacio_compress() {
    local src="$1" del="$2" base="${1:t}" dirn="${1:h}" arc="${1}.tar.gz" before after pct
    if [[ ! -f "$src" ]]; then msg_warn "No existe: $src"; return 1; fi

    if file_in_use "$src"; then
        msg_warn "'$base' está en uso por un proceso (log, base de datos, VM...)."
        msg_info "Comprimir un archivo que se está escribiendo da un resultado inconsistente."
        confirm "¿Comprimir igualmente? (el original NO se borrará)" || { msg_info "Omitido."; return 1; }
        del=0
    fi
    if [[ -e "$arc" ]]; then msg_warn "Ya existe '$arc': se omite."; return 1; fi

    before=$("${SUDO[@]}" stat -c %s -- "$src" 2>/dev/null)
    msg_info "Comprimiendo '$base'..."
    if ! "${SUDO[@]}" tar -czf "$arc" -C "$dirn" -- "$base"; then
        "${SUDO[@]}" rm -f -- "$arc"
        msg_err "Falló la compresión de '$base'. El original no se tocó."
        log_action "Espacio: ERROR comprimiendo $src"
        return 1
    fi
    if ! { "${SUDO[@]}" gzip -t -- "$arc" && "${SUDO[@]}" tar -tzf "$arc" &>/dev/null; }; then
        "${SUDO[@]}" rm -f -- "$arc"
        msg_err "El .tar.gz no valida: se descartó y el ORIGINAL se conserva."
        log_action "Espacio: archivo corrupto descartado para $src"
        return 1
    fi
    after=$("${SUDO[@]}" stat -c %s -- "$arc" 2>/dev/null)
    pct=0; (( before > 0 )) && pct=$(( (before - after) * 100 / before ))
    if (( del )); then
        "${SUDO[@]}" rm -f -- "$src"
        msg_ok "Comprimido, validado y original eliminado: $(human_bytes $before) -> $(human_bytes $after) (-${pct}%)"
    else
        msg_ok "Comprimido y validado (original conservado): $(human_bytes $before) -> $(human_bytes $after) (-${pct}%)"
    fi
    log_action "Espacio: $src -> $arc ($(human_bytes $before) -> $(human_bytes $after), borrado=$del)"
    return 0
}

act_espacio() {
    local dir nmax ext f size dt fpth num del=0 i=1
    prompt_input "Carpeta a revisar: " dir
    dir="${dir%/}"
    [[ -z "$dir" ]] && return 0
    [[ "$dir" == -* ]] && { msg_err "Ruta no válida."; return 0; }
    [[ -d "$dir" ]] || { msg_err "El directorio '$dir' no existe."; return 0; }
    prompt_input "Cantidad de archivos a listar [Default: 20]: " nmax
    valid_num "$nmax" && (( nmax >= 1 && nmax <= 200 )) || nmax=20

    local -a excl=() rows paths=()
    for ext in gz tgz zip rar 7z bz2 tbz2 xz txz zst iso img mp4 mkv jpg png pdf; do
        excl+=( -not -name "*.$ext" )
    done
    if ! command -v fuser &>/dev/null && ! command -v lsof &>/dev/null; then
        msg_warn "Ni 'fuser' (psmisc) ni 'lsof' están instalados: no podré detectar archivos en uso."
    fi

    msg_info "Los $nmax archivos más pesados en '$dir' (mismo filesystem, sin formatos ya comprimidos)..."
    rows=( ${(f)"$("${SUDO[@]}" find "$dir" -xdev -type f "${excl[@]}" \
                  -printf '%s\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null | sort -rn | head -n "$nmax")"} )
    if (( ${#rows} == 0 )); then msg_info "No se encontraron archivos (o todos están excluidos)."; return 0; fi

    print ""
    for f in "${rows[@]}"; do
        size="${f%%$'\t'*}"; f="${f#*$'\t'}"; dt="${f%%$'\t'*}"; fpth="${f#*$'\t'}"
        printf " %3d) %10s  %s  %s\n" "$i" "$(human_bytes $size)" "$dt" "$fpth"
        paths+=("$fpth"); i=$(( i + 1 ))
    done
    print ""
    confirm "¿Deseas comprimir alguno de estos archivos?" || return 0
    prompt_input "Números a comprimir (ej: 1 3 5, Enter = cancelar): " num
    [[ -z "$num" ]] && { msg_info "Cancelado."; return 0; }
    confirm "Tras comprimir y VALIDAR cada archivo, ¿borrar el original?" && del=1

    local n
    for n in ${=num}; do
        if [[ "$n" == <-> ]] && (( n >= 1 && n <= ${#paths} )); then
            espacio_compress "${paths[$n]}" "$del"
        else
            msg_warn "Número no válido: $n"
        fi
    done
}

# ==============================================================================
#  TAR: comprimir / descomprimir   (reemplaza a comprimir.sh)
# ==============================================================================
act_tar_create() {
    local src out def mode rc
    prompt_input "Ruta a comprimir (archivo o carpeta): " src
    src="${src%/}"
    [[ -z "$src" ]] && return 0
    [[ -e "$src" ]] || { msg_err "No existe '$src'."; return 0; }
    def="${src:t}_$(date +%Y%m%d).tar.gz"
    prompt_input "Archivo de salida [Default: $def]: " out
    out="${out:-$def}"
    [[ "$out" == *.tar.gz || "$out" == *.tgz ]] || { msg_err "El nombre debe terminar en .tar.gz o .tgz"; return 0; }
    if [[ -e "$out" ]]; then confirm "'$out' ya existe. ¿Sobrescribir?" || return 0; fi
    print " 1) Rutas relativas (recomendado: se restaura donde quieras)"
    print " 2) Rutas absolutas (se restaura en el mismo lugar original)"
    prompt_input "Elige [1-2, Default 1]: " mode

    local -a cmd
    if [[ "$mode" == 2 ]]; then cmd=(tar -czPf "$out" -- "$src")
    else                        cmd=(tar -czf "$out" -C "${src:h}" -- "${src:t}"); fi

    msg_info "Comprimiendo '$src' en '$out'..."
    "${cmd[@]}"; rc=$?
    if (( rc != 0 && EUID != 0 )); then
        msg_warn "Hubo errores de permisos."
        if confirm "¿Reintentar con sudo?"; then
            "${SUDO[@]}" "${cmd[@]}"; rc=$?
            "${SUDO[@]}" chown "$(id -un)" "$out" 2>/dev/null     # el .tar.gz queda a tu nombre
        fi
    fi
    if (( rc == 0 )) && tar -tzf "$out" &>/dev/null; then
        msg_ok "Archivo creado y verificado: $out ($(human_bytes $(stat -c %s "$out")))"
        log_action "Tar: creado $out desde $src"
    else
        msg_err "Falló la compresión (código $rc)."
    fi
}

act_tar_extract() {
    local f dest mode typed
    prompt_input "Archivo .tar.gz a descomprimir: " f
    [[ -z "$f" ]] && return 0
    [[ -f "$f" ]] || { msg_err "No existe '$f'."; return 0; }
    tar -tzf "$f" &>/dev/null || { msg_err "'$f' no es un .tar.gz válido."; return 0; }

    msg_info "Contenido (primeras 15 entradas):"
    tar -tzvf "$f" | head -n 15
    local risky=0
    tar -tzf "$f" | grep -qE '^/|(^|/)\.\./' && risky=1
    (( risky )) && msg_warn "El archivo contiene rutas absolutas o con '..': podría escribir fuera del destino."

    print " 1) Extraer en una carpeta destino (recomendado)"
    print " 2) Restaurar en las rutas absolutas originales (requiere sudo)"
    prompt_input "Elige [1-2, Default 1]: " mode
    if [[ "$mode" == 2 ]]; then
        msg_warn "Se SOBRESCRIBIRÁN archivos del sistema en las rutas originales."
        tar -tzf "$f" | head -n 8 | sed 's/^/     /'
        prompt_input "Escribe CONFIRMAR para continuar: " typed
        [[ "$typed" == CONFIRMAR ]] || { msg_info "Cancelado."; return 0; }
        "${SUDO[@]}" tar -xzpPf "$f" && msg_ok "Restauración completada." || msg_err "Hubo problemas al restaurar."
        log_action "Tar: restauración ABS de $f"
        return 0
    fi
    prompt_input "Carpeta destino [Default: ./]: " dest
    dest="${dest:-.}"
    if [[ ! -d "$dest" ]]; then
        confirm "La carpeta '$dest' no existe. ¿Crearla?" || return 0
        mkdir -p -- "$dest" || { msg_err "No se pudo crear '$dest'."; return 0; }
    fi
    (( risky )) && { confirm "¿Extraer de todos modos?" || return 0; }
    if tar -xzf "$f" -C "$dest" --no-same-owner; then
        msg_ok "Extracción completada en '$dest'."
        log_action "Tar: extraído $f en $dest"
    else
        msg_err "Hubo problemas al extraer el archivo."
    fi
}

# ==============================================================================
#  MENÚ DE ARCHIVOS
# ==============================================================================
menu_files() {
    run_menu "ARCHIVOS Y TEXTO" \
        "#TRABAJAR CON ARCHIVOS" \
        "Editar archivos (nvim / vim / nano / vi)|act_edit" \
        "Búsqueda y filtrado de texto (grep -E)|act_grep" \
        "Análisis técnico de archivo (stat, file, wc, sha256)|act_fileinfo" \
        "Comparación de archivos (diff)|act_diff" \
        "Resguardo rápido (rsync con simulación previa)|act_rsync" \
        "#ESPACIO Y COMPRESIÓN" \
        "Archivos más pesados y compresión segura|act_espacio" \
        "Comprimir archivo o carpeta (.tar.gz)|act_tar_create" \
        "Descomprimir .tar.gz (con revisión de rutas)|act_tar_extract"
}
