#!/usr/bin/env zsh
# Módulo: Fail2ban (Seguridad del Servidor)

f2b_installed() { command -v fail2ban-client &>/dev/null; }

f2b_install() {
    if f2b_installed; then return 0; fi
    msg_warn "Fail2ban no está instalado."
    if confirm "¿Instalarlo ahora usando $PKG_MGR?"; then
        "${PKG_INSTALL[@]}" fail2ban
        if f2b_installed; then
            msg_ok "Fail2ban instalado."
            sudo systemctl enable --now fail2ban
            log_action "Fail2ban: instalado y habilitado"
            return 0
        else
            msg_err "La instalación falló."
            return 1
        fi
    fi
    return 1
}

f2b_status() {
    f2b_install || return 0
    msg_info "Estado general de Fail2ban:"
    sudo fail2ban-client status
}

f2b_jail_status() {
    f2b_install || return 0
    local jail
    prompt_input "Nombre de la 'jail' (ej: sshd, apache-auth, nginx-limit-req): " jail
    if [[ -n "$jail" ]]; then
        sudo fail2ban-client status "$jail"
    fi
}

f2b_unban() {
    f2b_install || return 0
    local jail ip
    prompt_input "Jail de donde desbanear (ej: sshd): " jail
    prompt_input "IP a desbanear: " ip
    if [[ -n "$jail" && -n "$ip" ]]; then
        sudo fail2ban-client set "$jail" unbanip "$ip"
        msg_ok "IP $ip desbaneada de $jail (si estaba)."
    fi
}

f2b_ban() {
    f2b_install || return 0
    local jail ip
    prompt_input "Jail donde banear (ej: sshd): " jail
    prompt_input "IP a banear: " ip
    if [[ -n "$jail" && -n "$ip" ]]; then
        sudo fail2ban-client set "$jail" banip "$ip"
        msg_ok "IP $ip baneada de $jail."
    fi
}

f2b_reload() {
    f2b_install || return 0
    msg_info "Recargando configuración de Fail2ban..."
    sudo fail2ban-client reload
    msg_ok "Configuración recargada."
}

f2b_logs() {
    f2b_install || return 0
    local logfile="/var/log/fail2ban.log"
    [[ -f "$logfile" ]] || { msg_err "No se encontró $logfile"; return 0; }
    msg_info "Mostrando log en vivo (Ctrl+C para salir)..."
    run_interruptible sudo tail -f "$logfile"
}

menu_fail2ban() {
    f2b_install || return 0
    run_menu "FAIL2BAN - SEGURIDAD DEL SERVIDOR" \
        "#ESTADO" \
        "Ver estado general (jails activas)|f2b_status" \
        "Ver estado de una jail (IPs baneadas)|f2b_jail_status" \
        "#GESTIÓN DE IPS" \
        "Desbanear una IP manualmente|f2b_unban" \
        "Banear una IP manualmente|f2b_ban" \
        "#MANTENIMIENTO" \
        "Recargar configuración|f2b_reload" \
        "Ver log en tiempo real (tail -f)|f2b_logs"
}
