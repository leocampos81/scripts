#!/usr/bin/env zsh

# --- Utilidades de clima ---
util_weather_full() {
    local city
    prompt_input "Ciudad (Enter para autodetectar): " city
    msg_info "Consultando wttr.in..."
    ccurl "wttr.in/${city// /+}?lang=es&m"
    log_action "Utilidades: clima completo (${city:-auto})"
}
util_weather_compact() { msg_info "Consultando clima compacto..."; ccurl "wttr.in/?format=3&m"; log_action "Utilidades: clima compacto"; }
util_moon()            { msg_info "Consultando fase lunar...";     ccurl "wttr.in/moon";         log_action "Utilidades: fase lunar"; }

util_sun() {
    need jq || return 0
    local lat lng
    prompt_input "Latitud [Default: -33.45 (Santiago)]: " lat
    prompt_input "Longitud [Default: -70.66 (Santiago)]: " lng
    lat="${lat:--33.45}"; lng="${lng:--70.66}"
    msg_info "Amanecer/atardecer (UTC) para ($lat, $lng):"
    ccurl --get --data-urlencode "lat=$lat" --data-urlencode "lng=$lng" --data "formatted=0" \
        "https://api.sunrise-sunset.org/json" | jq '.results'
    log_action "Utilidades: sunrise/sunset ($lat,$lng)"
}

# --- Generación local ---
util_password() {
    local len sym set
    prompt_input "Largo de la contraseña [Default: 20]: " len
    valid_num "$len" && (( len >= 8 && len <= 128 )) || len=20
    set='A-Za-z0-9'
    confirm "¿Incluir símbolos?" && set='A-Za-z0-9!@#%^*_+=-'
    msg_info "Contraseña aleatoria ($len caracteres):"
    LC_ALL=C tr -dc "$set" < /dev/urandom 2>/dev/null | head -c "$len"
    print ""
    log_action "Utilidades: contraseña local generada"
}

util_uuid() {
    msg_info "UUID v4 generado localmente:"
    if [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
    elif command -v uuidgen &>/dev/null; then uuidgen | tr '[:upper:]' '[:lower:]'
    else openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
    fi
    log_action "Utilidades: UUID local"
}

util_qr() {
    local txt
    prompt_input "Texto o URL para el QR: " txt
    [[ -z "$txt" ]] && return 0
    if command -v qrencode &>/dev/null; then
        qrencode -t ansiutf8 -- "$txt"
    elif command -v mkqr &>/dev/null; then
        mkqr "$txt"
    elif need qrencode; then
        qrencode -t ansiutf8 -- "$txt"
    else
        msg_warn "Fallback remoto: el texto se enviaría a qrenco.de."
        confirm "¿Continuar?" || return 0
        ccurl "qrenco.de/$(urlencode "$txt")"
    fi
    log_action "Utilidades: QR generado"
}

# --- Consultas y referencia ---
util_dict() {
    local w
    prompt_input "Palabra a consultar (inglés / término tech): " w
    valid_ident "$w" || { msg_err "Palabra no válida."; return 0; }
    msg_info "Definición de '$w':"
    ccurl "dict.org/d:$w" | grep -v '^$' | head -n 40
    log_action "Utilidades: diccionario '$w'"
}

util_cheat() {
    local c
    prompt_input "Comando a consultar (ej: rsync, tar, git): " c
    valid_ident "$c" || { msg_err "Comando no válido."; return 0; }
    msg_info "cheat.sh/$c"
    ccurl "cht.sh/$c"
    log_action "Utilidades: cheat.sh $c"
}

util_wiki() {
    need jq || return 0
    local term
    prompt_input "Término o título en Wikipedia (ej: Linux): " term
    [[ -z "$term" ]] && return 0
    msg_info "Resumen de '$term' en es.wikipedia:"
    ccurl "https://es.wikipedia.org/api/rest_v1/page/summary/$(urlencode "$term")" \
        | jq -r '.extract // .detail // "No encontrado"'
    log_action "Utilidades: wikipedia '$term'"
}

# --- Finanzas ---
util_fx() {
    need jq || return 0
    local base targets
    prompt_input "Moneda base [Default: USD]: " base
    base="${${base:-USD}:u}"
    valid_ident "$base" || { msg_err "Moneda no válida."; return 0; }
    prompt_input "Monedas destino separadas por coma [Default: CLP,USD,EUR,ARS,BRL]: " targets
    targets="${targets:-CLP,USD,EUR,ARS,BRL}"
    msg_info "Tipo de cambio desde $base:"
    ccurl "https://open.er-api.com/v6/latest/$base" | jq --arg l "$targets" \
        '{base: .base_code, actualizado: .time_last_update_utc,
          tasas: ((.rates // {}) as $r | ($l | split(",") | map(ascii_upcase | gsub(" ";""))) | map({key: ., value: $r[.]}) | from_entries)}'
    log_action "Utilidades: tipo de cambio base $base"
}

util_crypto() {
    need jq || return 0
    local ids fiat
    prompt_input "IDs de cripto separados por coma [Default: bitcoin,ethereum]: " ids
    ids="${ids:-bitcoin,ethereum}"
    prompt_input "Moneda fiat (usd, eur, clp...) [Default: usd]: " fiat
    fiat="${fiat:-usd}"
    msg_info "Cotización de $ids en $fiat:"
    ccurl --get --data-urlencode "ids=$ids" --data-urlencode "vs_currencies=$fiat" \
        "https://api.coingecko.com/api/v3/simple/price" | jq .
    log_action "Utilidades: cripto $ids/$fiat"
}

# --- Menú del módulo ---
utils_menu() {
    run_menu "UTILIDADES LOCALES Y CONSULTAS" \
        "#CLIMA Y ASTRONOMÍA" \
        "Clima actual completo (wttr.in)|util_weather_full" \
        "Clima compacto de una línea|util_weather_compact" \
        "Fase lunar actual|util_moon" \
        "Amanecer y atardecer (sunrise-sunset.org)|util_sun" \
        "#GENERACIÓN LOCAL (SIN RED)" \
        "Generar contraseña segura|util_password" \
        "Generar UUID v4|util_uuid" \
        "Generar código QR en terminal|util_qr" \
        "#CONSULTAS Y REFERENCIA" \
        "Diccionario / definición de palabras (dict.org)|util_dict" \
        "Hojas de ayuda rápida de comandos (cht.sh)|util_cheat" \
        "Resumen de Wikipedia|util_wiki" \
        "#FINANZAS" \
        "Tipo de cambio de divisas (open.er-api.com)|util_fx" \
        "Cotización de criptomonedas (coingecko)|util_crypto"
}
