#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: NETWORK  -  red, diagnóstico avanzado y auditoría con Nmap
#  Se carga con 'source' desde prom_claude.sh (no se ejecuta directamente).
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

act_net_basic() {
    command -v ip &>/dev/null || { msg_err "Falta 'ip' (paquete iproute2)."; return 0; }
    msg_info "Interfaces de red detectadas:"
    ip -brief address | awk '{print "  > " $1 " (" $2 ") " $3}'
    print -r -- "------------------------------------------"
    print " 1) Direcciones IP detalladas (ip a)"
    print " 2) Tabla de ruteo (ip route)"
    print " 3) Puertos en escucha TCP/UDP (ss -tulpn)"
    print " 4) Prueba rápida de conectividad (ping)"
    print " 5) Ficha técnica de una interfaz"
    local choice
    prompt_input "Selecciona opción [1-5]: " choice
    case "$choice" in
        1) ip address ;;
        2) ip route ;;
        3) "${SUDO[@]}" ss -tulpn ;;
        4) local target
           prompt_input "IP o host de prueba: " target
           valid_host "$target" && ping -c 4 "$target" || msg_err "Destino no válido o sin respuesta." ;;
        5) local iface state mac mtu ipv4 ipv6 gw
           prompt_input "Interfaz (ej: eth0, ens18, wlan0): " iface
           if ! valid_ident "$iface" || ! ip link show dev "$iface" &>/dev/null; then
               msg_err "La interfaz '$iface' no existe."; return 0
           fi
           state=$(ip -o link show dev "$iface" | awk '{for(i=1;i<=NF;i++) if($i=="state"){print $(i+1); exit}}')
           mtu=$(ip -o link show dev "$iface" | awk '{for(i=1;i<=NF;i++) if($i=="mtu"){print $(i+1); exit}}')
           mac=$(ip -o link show dev "$iface" | awk '{for(i=1;i<=NF;i++) if($i=="link/ether"){print $(i+1); exit}}')
           ipv4=$(ip -4 -o addr show dev "$iface" | awk '{print $4; exit}')
           ipv6=$(ip -6 -o addr show dev "$iface" scope global | awk '{print $4; exit}')
           gw=$(ip route show default dev "$iface" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')
           print ""
           box_open "FICHA TÉCNICA DE INTERFAZ"
           box_row "Interfaz" "$iface"
           box_row "Estado" "${state:-Desconocido}"
           box_row "MAC" "${mac:-N/A}"
           box_row "MTU" "${mtu:-N/A}"
           box_row "IPv4" "${ipv4:-N/A}"
           box_row "IPv6" "${ipv6:-N/A}"
           box_row "Gateway" "${gw:-N/A}"
           box_close ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    log_action "Nativo: red básica ($choice)"
}

nm_target() {   # nm_target VAR "mensaje"
    local _t
    prompt_input "$2" _t
    [[ -z "$_t" ]] && return 1
    valid_host "$_t" || { msg_err "Objetivo no válido."; return 1; }
    typeset -g "$1=$_t"
}

nm_quick() {
    local t; nm_target t "IP o hostname objetivo: " || return 0
    msg_info "Escaneo rápido en '$t'..."; run_interruptible nmap -T4 "$t"
    log_action "Nmap: escaneo rápido en $t"
}

nm_versions() {
    local t; nm_target t "IP o hostname objetivo: " || return 0
    msg_info "Detección de versiones (-sV) en '$t'..."; run_interruptible nmap -sV -T4 "$t"
    log_action "Nmap: -sV en $t"
}

nm_aggressive() {
    local t; nm_target t "IP o hostname objetivo: " || return 0
    msg_info "Escaneo agresivo (-A) en '$t' (requiere root para detectar SO)..."
    run_interruptible "${SUDO[@]}" nmap -A -T4 "$t"
    log_action "Nmap: -A en $t"
}

nm_discover() {
    local def net
    def=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4; exit}')
    prompt_input "Rango de red [Default: ${def:-192.168.1.0/24}]: " net
    net="${net:-${def:-192.168.1.0/24}}"
    valid_host "$net" || { msg_err "Rango no válido."; return 0; }
    msg_info "Descubriendo hosts activos en '$net'..."; run_interruptible nmap -sn "$net"
    log_action "Nmap: ping scan en $net"
}

menu_nmap() {
    if ! need nmap; then pause_screen; return 0; fi
    if (( NMAP_ACK == 0 )); then
        print ""
        msg_warn "Escanear sistemas ajenos sin autorización puede ser ilegal."
        confirm "¿Confirmas que solo escanearás equipos propios o autorizados?" || return 0
        NMAP_ACK=1
    fi
    run_menu "AUDITORÍA DE RED Y SEGURIDAD (NMAP) - $(nmap --version | head -n 1 | cut -c1-40)" \
        "Escaneo rápido de puertos en IP/Host|nm_quick" \
        "Escaneo completo con detección de versiones (-sV)|nm_versions" \
        "Escaneo agresivo (SO, versiones y scripts -A)|nm_aggressive" \
        "Descubrimiento de hosts activos en la red local|nm_discover"
}

na_http() {
    local u
    prompt_input "URL o IP objetivo (ej: https://google.com): " u
    [[ -z "$u" || "$u" == -* ]] && return 0
    msg_info "Análisis HTTP detallado..."
    print -r -- "------------------------------------------"
    curl -I -L -s --max-time 10 \
        -w "\n[Métricas]\nTiempo total: %{time_total}s\nCódigo HTTP: %{http_code}\nIP remota: %{remote_ip}\n" "$u"
    log_action "RedAv: curl detallado a $u"
}

na_ping() {
    local h c
    prompt_input "IP o dominio destino: " h
    valid_host "$h" || { msg_err "Destino no válido."; return 0; }
    prompt_input "Cantidad de paquetes [Default: 4]: " c
    valid_num "$c" && (( c >= 1 && c <= 100 )) || c=4
    msg_info "Enviando $c paquetes ICMP a '$h'..."
    ping -c "$c" "$h"
    log_action "RedAv: ping a $h ($c)"
}

na_port() {
    local h p
    prompt_input "IP o host remoto: " h
    prompt_input "Puerto a verificar (ej: 22, 80, 443): " p
    valid_host "$h" || { msg_err "Host no válido."; return 0; }
    valid_num "$p" && (( p >= 1 && p <= 65535 )) || { msg_err "Puerto no válido (1-65535)."; return 0; }
    msg_info "Probando $h:$p ..."
    if command -v nc &>/dev/null || need nc; then
        nc -zv -w 3 "$h" "$p"
    elif command -v bash &>/dev/null; then
        # zsh no tiene /dev/tcp: se delega en bash con timeout
        if timeout 4 bash -c 'exec 3<>/dev/tcp/$0/$1' "$h" "$p" 2>/dev/null; then
            msg_ok "Puerto $p en $h ABIERTO y accesible."
        else
            msg_warn "No se pudo conectar a $h:$p (cerrado o filtrado)."
        fi
    else
        msg_err "Ni nc ni bash disponibles."
    fi
    log_action "RedAv: test de puerto $h:$p"
}

na_trace() {
    local h
    prompt_input "IP o dominio para trazado de ruta: " h
    valid_host "$h" || { msg_err "Destino no válido."; return 0; }
    msg_info "Trazando ruta hacia $h..."
    if   command -v traceroute &>/dev/null; then run_interruptible traceroute "$h"
    elif command -v tracepath  &>/dev/null; then run_interruptible tracepath "$h"
    elif need traceroute;                   then run_interruptible traceroute "$h"
    else msg_err "No hay herramienta de trazado disponible."; fi
    log_action "RedAv: traceroute a $h"
}

na_dns() {
    local d t
    prompt_input "Dominio a consultar (ej: google.com): " d
    valid_host "$d" || { msg_err "Dominio no válido."; return 0; }
    if command -v dig &>/dev/null || need dig; then
        msg_info "Registros DNS de $d:"
        for t in A AAAA MX NS TXT; do
            print -r -- "--- $t ---"
            dig +noall +answer "$d" "$t"
        done
    elif command -v nslookup &>/dev/null; then
        nslookup "$d"
    else
        getent ahosts "$d"
    fi
    log_action "RedAv: DNS de $d"
}

na_publicip() {
    need jq || return 0
    msg_info "Obteniendo información de red pública..."
    local j; j=$(ccurl "https://ipinfo.io/json")
    [[ -z "$j" ]] && { msg_err "Sin respuesta de ipinfo.io."; return 0; }
    print ""
    box_open "FICHA TÉCNICA DE RED (IP PÚBLICA)"
    box_row "IP pública" "$(print -r -- "$j" | jq -r '.ip // "N/A"')"
    box_row "Ciudad" "$(print -r -- "$j" | jq -r '.city // "N/A"')"
    box_row "Región" "$(print -r -- "$j" | jq -r '.region // "N/A"')"
    box_row "País" "$(print -r -- "$j" | jq -r '.country // "N/A"')"
    box_row "ISP / Org" "$(print -r -- "$j" | jq -r '.org // "N/A"')"
    box_row "Zona horaria" "$(print -r -- "$j" | jq -r '.timezone // "N/A"')"
    box_close
    log_action "RedAv: ficha IP pública"
}

na_whois() {
    local t
    prompt_input "Dominio o IP para WHOIS: " t
    valid_host "$t" || { msg_err "Destino no válido."; return 0; }
    need whois || return 0
    whois "$t" | head -n 40
    log_action "RedAv: whois $t"
}

na_ssl() {
    command -v openssl &>/dev/null || { msg_err "openssl no está instalado."; return 0; }
    local h out subj issu not_b not_a cn iss days end_ts
    prompt_input "Dominio para inspeccionar el certificado SSL: " h
    valid_host "$h" || { msg_err "Dominio no válido."; return 0; }
    msg_info "Consultando certificado de $h:443..."
    out=$(timeout 10 openssl s_client -servername "$h" -connect "${h}:443" < /dev/null 2>/dev/null \
          | openssl x509 -noout -subject -issuer -dates 2>/dev/null)
    if [[ -z "$out" ]]; then
        msg_warn "No se pudo obtener el certificado (bloqueo de red o dominio inválido)."
        return 0
    fi
    subj=$(print -r -- "$out" | grep '^subject=');   issu=$(print -r -- "$out" | grep '^issuer=')
    not_b=$(print -r -- "$out" | sed -n 's/^notBefore=//p'); not_a=$(print -r -- "$out" | sed -n 's/^notAfter=//p')
    cn=$(print -r -- "$subj" | sed -nE 's/.*CN ?= ?([^,\/]+).*/\1/p')
    iss=$(print -r -- "$issu" | sed -nE 's/.*O ?= ?([^,\/]+).*/\1/p')
    end_ts=$(date -d "$not_a" +%s 2>/dev/null)
    if [[ -n "$end_ts" ]]; then
        days=$(( (end_ts - $(date +%s)) / 86400 ))
        (( days < 15 )) && days="$days  (¡por vencer!)"
    else
        days="N/D"
    fi
    print ""
    box_open "FICHA TÉCNICA DE CERTIFICADO SSL"
    box_row "Dominio" "$h"
    box_row "CN (subject)" "${cn:-${subj#subject=}}"
    box_row "Emisor" "${iss:-${issu#issuer=}}"
    box_row "Válido desde" "$not_b"
    box_row "Válido hasta" "$not_a"
    box_row "Días restantes" "$days"
    box_close
    log_action "RedAv: SSL de $h"
}

na_httpcard() {
    local u metrics code t_dns t_tcp t_tls t_ttfb t_total
    prompt_input "URL o host a verificar (ej: https://google.com): " u
    [[ -z "$u" || "$u" == -* ]] && return 0
    [[ "$u" != http* ]] && u="https://$u"
    msg_info "Verificando estado HTTP..."
    metrics=$(curl -s -o /dev/null -L --max-time 10 \
        -w "%{http_code}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}" "$u")
    IFS='|' read -r code t_dns t_tcp t_tls t_ttfb t_total <<< "$metrics"
    print ""
    box_open "FICHA TÉCNICA HTTP (tiempos acumulados)"
    box_row "URL objetivo" "$u"
    box_row "Código HTTP" "${code:-000}$([[ "${code:-000}" == 000 ]] && print ' (sin respuesta)')"
    box_sep
    box_row "DNS lookup" "$(ms_fmt "$t_dns")"
    box_row "TCP connect" "$(ms_fmt "$t_tcp")"
    awk -v t="${t_tls:-0}" 'BEGIN{exit !(t>0)}' && box_row "TLS handshake" "$(ms_fmt "$t_tls")"
    box_row "TTFB (1er byte)" "$(ms_fmt "$t_ttfb")"
    box_row "Tiempo total" "$(ms_fmt "$t_total")"
    box_close
    log_action "RedAv: ficha HTTP $u -> ${code:-000}"
}

na_shorten() {
    local u
    prompt_input "URL a acortar: " u
    [[ -z "$u" ]] && return 0
    msg_warn "La URL se enviará a tinyurl.com."
    confirm "¿Continuar?" || return 0
    ccurl --get --data-urlencode "url=$u" "https://tinyurl.com/api-create.php"
    print ""
    log_action "RedAv: TinyURL generado"
}

na_speed() {
    msg_info "Descargando 25 MB de Cloudflare para medir velocidad..."
    local r bps secs
    r=$(curl -o /dev/null -s --max-time 20 -w '%{speed_download}|%{time_total}' \
        -H "User-Agent: Mozilla/5.0" "https://speed.cloudflare.com/__down?bytes=25000000")
    bps="${r%%|*}"; secs="${r##*|}"
    awk -v b="${bps:-0}" -v s="${secs:-0}" 'BEGIN{printf "Velocidad media: %.2f Mbps (%.2f MB/s) en %.1f s\n", b*8/1000000, b/1000000, s}'
    log_action "RedAv: speedtest Cloudflare"
}

menu_netadv() {
    run_menu "DIAGNÓSTICO Y PRUEBAS DE RED AVANZADAS" \
        "#CONECTIVIDAD Y RESOLUCIÓN" \
        "Test HTTP/HTTPS detallado (cabeceras y tiempos)|na_http" \
        "Ping personalizable (ICMP)|na_ping" \
        "Verificación de puerto remoto abierto|na_port" \
        "Trazado de ruta (traceroute / tracepath)|na_trace" \
        "Resolución y consulta DNS (A, AAAA, MX, NS, TXT)|na_dns" \
        "#IDENTIDAD Y METADATOS DE RED" \
        "IP pública y detalles (ficha técnica)|na_publicip" \
        "WHOIS de dominio o IP|na_whois" \
        "Certificado SSL de un dominio (ficha técnica)|na_ssl" \
        "#UTILIDADES WEB" \
        "Verificar estado HTTP y tiempos (ficha técnica)|na_httpcard" \
        "Acortar URL (tinyurl)|na_shorten" \
        "Test de velocidad de descarga (Cloudflare)|na_speed"
}

menu_network() {
    run_menu "RED Y CONECTIVIDAD" \
        "#INTERFACES Y RUTAS" \
        "Red básica e interfaces (ip, rutas, puertos en escucha)|act_net_basic" \
        "#DIAGNÓSTICO" \
        "Diagnóstico avanzado: HTTP, ping, puertos, DNS, SSL, WHOIS|menu_netadv|nopause" \
        "#SEGURIDAD" \
        "Auditoría de red (Nmap)|menu_nmap|nopause"
}
