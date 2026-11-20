#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: BANNER  (reemplaza al antiguo banner.sh en bash)
#  Cambios: nativo en zsh (se hace 'source', no se ejecuta como proceso), la
#  información online (clima / IP pública) se CACHEA 10 minutos en vez de
#  consultarse en cada redibujo del menú, y se puede desactivar con
#  PROM_BANNER_ONLINE=0 (no se envía tu IP a terceros).
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

BANNER_CACHE="$STATE_DIR/banner.cache"
BANNER_TTL_MIN=10
BANNER_WEATHER=""
BANNER_PUBIP=""

banner_online_refresh() {
    local w ip
    w=$(curl -s -m 2 "https://wttr.in?format=%c+%C+%t,+%p+%w" 2>/dev/null)
    ip=$(curl -s -m 2 "https://ipinfo.io/ip" 2>/dev/null)
    mkdir -p "$STATE_DIR" 2>/dev/null
    ( umask 077; print -r -- "${w:-N/D}"$'\n'"${ip:-N/D}" > "$BANNER_CACHE" )
}

# Rellena BANNER_WEATHER / BANNER_PUBIP desde caché (refresca si venció)
banner_online_info() {
    BANNER_WEATHER=""; BANNER_PUBIP=""
    [[ "${PROM_BANNER_ONLINE:-1}" == 0 ]] && return 1
    command -v curl &>/dev/null || return 1
    local age=999999 mt
    if [[ -f "$BANNER_CACHE" ]]; then
        mt=$(stat -c %Y "$BANNER_CACHE" 2>/dev/null || print 0)
        age=$(( ( $(date +%s) - mt ) / 60 ))
    fi
    (( age >= BANNER_TTL_MIN )) && banner_online_refresh
    BANNER_WEATHER=$(sed -n 1p "$BANNER_CACHE" 2>/dev/null)
    BANNER_PUBIP=$(sed -n 2p "$BANNER_CACHE" 2>/dev/null)
    return 0
}

banner_main() {
    print "╔══════════════════════════════════════════════════════════════════╗"
    print "║                                                                  ║"
    print "║                  P R O M E T H E R I O N  2 1 1 2                ║"
    print "║                 S Y S A D M I N   D A S H B O A R D              ║"
    print "║                                                                  ║"
    print "╚══════════════════════════════════════════════════════════════════╝"
    local ll lip
    print -r -- "[*] Usuario Activo : ${USER:-$(id -un)}@$HOST"
    print -r -- "[*] Servidor actual: $OS_NAME"
    print -r -- "[*] Gestor paquetes: $PKG_MGR   |   Script: v$VERSION"
    print -r -- "[*] Fecha          : $(date '+%A, %d de %B de %Y, %H:%M')"
    ll=$(last -n 1 "${USER:-$(id -un)}" 2>/dev/null | awk 'NR==1 && $1!="wtmp" && NF>3 {print $4" "$5" "$6" "$7" en "$2}')
    [[ -n "$ll" ]] && print -r -- "[*] Última conexión: $ll"
    lip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
    [[ -n "$lip" ]] && print -r -- "[*] IP local        : $lip"
    if banner_online_info; then
        [[ -n "$BANNER_PUBIP" && "$BANNER_PUBIP" != "N/D" ]] && print -r -- "[*] IP pública      : $BANNER_PUBIP"
        [[ -n "$BANNER_WEATHER" && "$BANNER_WEATHER" != "N/D" ]] && print -r -- "[*] Clima            : $BANNER_WEATHER"
    fi
}
