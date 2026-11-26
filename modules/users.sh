#!/usr/bin/env zsh
# Módulo: Gestión de Usuarios y Grupos (con auditoría y listados interactivos)

# --- Utilidades internas del módulo ---
# Filtra usuarios "humanos" (UID >= 1000) y root
users_human_list() {
    awk -F: '$3 >= 1000 || $1 == "root" {print $1}' /etc/passwd
}

# Log de auditoría específico para este módulo
users_log() {
    local log_file="$STATE_DIR/users_audit.log"
    mkdir -p "$STATE_DIR" 2>/dev/null
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$log_file"
}

# --- 1. CONSULTAS ---
users_logins_history() {
    clear
    msg_info "Últimos inicios de sesión (last):"
    print -r -- "----------------------------------------------------------"
    last -n 15
    print -r -- "----------------------------------------------------------"
}

# --- 2. GESTIÓN DE USUARIOS ---
users_list() {
    clear
    msg_info "Usuarios del sistema:"
    print -r -- "----------------------------------------------------------"
    awk -F: '$3 >= 1000 || $1 == "root" {printf "%-20s UID:%-6s GID:%-6s Home:%-25s Shell:%s\n", $1, $3, $4, $6, $7}' /etc/passwd
    print -r -- "----------------------------------------------------------"
}

users_info() {
    clear
    # Listado interactivo para elegir el usuario
    local -a users=( $(users_human_list) )
    local i=1 u
    msg_info "Selecciona el usuario a consultar:"
    for u in "${users[@]}"; do
        printf " %2d) %s\n" "$i" "$u"
        i=$(( i + 1 ))
    done
    local choice
    prompt_input "Número (o 'q' para cancelar): " choice
    [[ -z "$choice" || "$choice" == "q" ]] && return 0

    if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#users} )); then
        local user="${users[$choice]}"
        clear
        msg_info "Información de '$user':"
        print -r -- "----------------------------------------------------------"
        id "$user"
        echo ""
        grep "^$user:" /etc/passwd | awk -F: '{printf "Home: %s\nShell: %s\n", $6, $7}'
        echo ""
        if groups "$user" | grep -qw "sudo"; then
            print -r -- "${C_YEL}[!] El usuario pertenece al grupo 'sudo'${C_RST}"
        fi
        print -r -- "----------------------------------------------------------"
    else
        msg_err "Selección no válida."
    fi
}

users_create() {
    local user shell group
    prompt_input "Nombre del nuevo usuario: " user
    valid_ident "$user" || { msg_err "Nombre no válido."; return 0; }
    
    if id "$user" &>/dev/null; then
        msg_err "El usuario '$user' ya existe."
        return 0
    fi

    prompt_input "Shell por defecto [Default: /bin/bash]: " shell
    shell="${shell:-/bin/bash}"

    # Preguntar si quiere añadir a un grupo específico
    msg_info "¿Deseas añadir el usuario a un grupo existente?"
    local -a groups=( $(awk -F: '{print $1}' /etc/group | grep -v -E "^(root|daemon|bin|sys|adm|tty|disk|lp|mail|news|uucp|man|proxy|kmem|dialout|fax|voice|cdrom|floppy|tape|sudo|audio|dip|www-data|backup|list|irc|src|gnats|shadow|utmp|video|sasl|plugdev|staff|games|users|nogroup|libvirt|docker|systemd-network|systemd-timesync|messagebus|sshd|systemd-journal|systemd-resolve|input|kvm|render|netdev|bluetooth|scanner|saned|colord|geoclue|pulse|pulse-access|rtkit|crontab|ntp|syslog|uuidd|tcpdump|landscape|fwupd|polkitd|swtpm|gnome-initial-setup|prometheus|node-exporter)" ) )
    i=1
    for u in "${groups[@]}"; do
        printf " %2d) %s\n" "$i" "$u"
        i=$(( i + 1 ))
    done
    prompt_input "Número del grupo (Enter para omitir): " g_choice
    if [[ "$g_choice" == <-> ]] && (( g_choice >= 1 && g_choice <= ${#groups} )); then
        group="${groups[$g_choice]}"
    fi

    msg_info "Creando usuario '$user'..."
    if [[ -n "$group" ]]; then
        sudo useradd -m -s "$shell" -G "$group" "$user"
    else
        sudo useradd -m -s "$shell" "$user"
    fi
    sudo passwd "$user"
    
    if id "$user" &>/dev/null; then
        msg_ok "Usuario '$user' creado correctamente."
        users_log "CREAR_USUARIO: $user (grupo: ${group:-por defecto})"
    else
        msg_err "Falló la creación del usuario."
    fi
}

users_delete() {
    clear
    # Listado interactivo de usuarios humanos
    local -a users=( $(users_human_list) )
    local i=1 u
    msg_info "Usuarios eliminables (excluyendo sistema):"
    for u in "${users[@]}"; do
        printf " %2d) %s\n" "$i" "$u"
        i=$(( i + 1 ))
    done
    local choice
    prompt_input "Número del usuario a eliminar (o 'q' para cancelar): " choice
    [[ -z "$choice" || "$choice" == "q" ]] && return 0

    if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#users} )); then
        local user="${users[$choice]}"
        prompt_input "¿Eliminar también el home directory? (s/n) [Default: n]: " confirm_delete
        if [[ "$confirm_delete" == "s" || "$confirm_delete" == "S" ]]; then
            sudo userdel -r "$user"
        else
            sudo userdel "$user"
        fi
        if ! id "$user" &>/dev/null; then
            msg_ok "Usuario '$user' eliminado."
            users_log "ELIMINAR_USUARIO: $user (home: ${confirm_delete})"
        else
            msg_err "No se pudo eliminar el usuario."
        fi
    else
        msg_err "Selección no válida."
    fi
}

users_change_password() {
    clear
    local -a users=( $(users_human_list) )
    local i=1 u
    msg_info "Usuarios disponibles para cambiar contraseña:"
    for u in "${users[@]}"; do
        printf " %2d) %s\n" "$i" "$u"
        i=$(( i + 1 ))
    done
    local choice
    prompt_input "Número del usuario (o 'q' para cancelar): " choice
    [[ -z "$choice" || "$choice" == "q" ]] && return 0

    if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#users} )); then
        local user="${users[$choice]}"
        sudo passwd "$user"
        msg_ok "Contraseña actualizada para '$user'."
        users_log "CAMBIO_PASSWORD: $user"
    else
        msg_err "Selección no válida."
    fi
}

# --- 3. GESTIÓN DE GRUPOS ---
users_list_groups() {
    clear
    msg_info "Grupos del sistema:"
    print -r -- "----------------------------------------------------------"
    awk -F: '{printf "%-20s GID:%-6s Miembros:%s\n", $1, $3, $4}' /etc/group | head -n 40
    print -r -- "----------------------------------------------------------"
}

users_create_group() {
    local group
    prompt_input "Nombre del nuevo grupo: " group
    valid_ident "$group" || { msg_err "Nombre no válido."; return 0; }
    
    if getent group "$group" &>/dev/null; then
        msg_err "El grupo '$group' ya existe."
        return 0
    fi
    
    sudo groupadd "$group"
    if getent group "$group" &>/dev/null; then
        msg_ok "Grupo '$group' creado."
        # Mostrar info del grupo recién creado
        local gid
        gid=$(getent group "$group" | cut -d: -f3)
        print -r -- "  GID: $gid"
        print -r -- "  Miembros: (ninguno)"
        users_log "CREAR_GRUPO: $group (GID: $gid)"
    else
        msg_err "No se pudo crear el grupo."
    fi
}

users_delete_group() {
    clear
    local -a groups=( $(awk -F: '{print $1}' /etc/group | grep -v -E "^(root|daemon|bin|sys|adm|tty|disk|lp|mail|news|uucp|man|proxy|kmem|dialout|fax|voice|cdrom|floppy|tape|sudo|audio|dip|www-data|backup|list|irc|src|gnats|shadow|utmp|video|sasl|plugdev|staff|games|users|nogroup|libvirt|docker|systemd-network|systemd-timesync|messagebus|sshd|systemd-journal|systemd-resolve|input|kvm|render|netdev|bluetooth|scanner|saned|colord|geoclue|pulse|pulse-access|rtkit|crontab|ntp|syslog|uuidd|tcpdump|landscape|fwupd|polkitd|swtpm|gnome-initial-setup|prometheus|node-exporter)" ) )
    local i=1 u
    msg_info "Grupos eliminables:"
    for u in "${groups[@]}"; do
        printf " %2d) %s\n" "$i" "$u"
        i=$(( i + 1 ))
    done
    local choice
    prompt_input "Número del grupo a eliminar (o 'q' para cancelar): " choice
    [[ -z "$choice" || "$choice" == "q" ]] && return 0

    if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#groups} )); then
        local group="${groups[$choice]}"
        confirm "¿Eliminar el grupo '$group'?" || return 0
        sudo groupdel "$group"
        msg_ok "Grupo '$group' eliminado."
        users_log "ELIMINAR_GRUPO: $group"
    else
        msg_err "Selección no válida."
    fi
}

users_add_to_group() {
    clear
    # 1. Listar usuarios humanos
    local -a users=( $(users_human_list) )
    local i=1 u
    msg_info "Usuarios disponibles:"
    for u in "${users[@]}"; do
        printf " %2d) %s\n" "$i" "$u"
        i=$(( i + 1 ))
    done
    local user_choice
    prompt_input "Número del usuario (o 'q' para cancelar): " user_choice
    [[ -z "$user_choice" || "$user_choice" == "q" ]] && return 0
    if ! [[ "$user_choice" == <-> ]] && (( user_choice >= 1 && user_choice <= ${#users} )); then
        msg_err "Selección no válida."; return 0
    fi
    local user="${users[$user_choice]}"

    # 2. Listar grupos existentes (excluyendo los de sistema)
    local -a groups=( $(awk -F: '{print $1}' /etc/group | grep -v -E "^(root|daemon|bin|sys|adm|tty|disk|lp|mail|news|uucp|man|proxy|kmem|dialout|fax|voice|cdrom|floppy|tape|sudo|audio|dip|www-data|backup|list|irc|src|gnats|shadow|utmp|video|sasl|plugdev|staff|games|users|nogroup|libvirt|docker|systemd-network|systemd-timesync|messagebus|sshd|systemd-journal|systemd-resolve|input|kvm|render|netdev|bluetooth|scanner|saned|colord|geoclue|pulse|pulse-access|rtkit|crontab|ntp|syslog|uuidd|tcpdump|landscape|fwupd|polkitd|swtpm|gnome-initial-setup|prometheus|node-exporter)" ) )
    i=1
    msg_info "Grupos disponibles:"
    for u in "${groups[@]}"; do
        printf " %2d) %s\n" "$i" "$u"
        i=$(( i + 1 ))
    done
    local group_choice
    prompt_input "Número del grupo (o 'q' para cancelar): " group_choice
    [[ -z "$group_choice" || "$group_choice" == "q" ]] && return 0
    if ! [[ "$group_choice" == <-> ]] && (( group_choice >= 1 && group_choice <= ${#groups} )); then
        msg_err "Selección no válida."; return 0
    fi
    local group="${groups[$group_choice]}"

    sudo usermod -aG "$group" "$user"
    msg_ok "Usuario '$user' añadido al grupo '$group'."
    msg_warn "Recuerda que el usuario debe cerrar y abrir sesión para aplicar el cambio."
    users_log "AÑADIR_GRUPO: $user -> $group"
}

users_remove_from_group() {
    clear
    local user group
    prompt_input "Nombre del usuario: " user
    prompt_input "Nombre del grupo: " group
    [[ -z "$user" || -z "$group" ]] && return 0
    
    if ! id "$user" &>/dev/null; then msg_err "El usuario no existe."; return 0; fi
    
    sudo gpasswd -d "$user" "$group"
    msg_ok "Usuario '$user' eliminado del grupo '$group'."
    users_log "QUITAR_GRUPO: $user de $group"
}

# --- 4. SESIONES ACTIVAS ---
users_active_sessions() {
    clear
    msg_info "Sesiones activas en el sistema:"
    print -r -- "----------------------------------------------------------"
    who -u
    print -r -- "----------------------------------------------------------"
}

users_kill_session() {
    clear
    msg_info "Sesiones activas:"
    print -r -- "----------------------------------------------------------"
    local -a sessions
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && sessions+=("$line")
    done < <(who -u | grep -v "USER")
    
    if (( ${#sessions} == 0 )); then
        msg_warn "No hay sesiones activas."; return 0
    fi
    local i=1
    for line in "${sessions[@]}"; do
        printf " %2d) %s\n" "$i" "$line"
        i=$(( i + 1 ))
    done
    print -r -- "----------------------------------------------------------"

    local choice
    prompt_input "Número de la sesión a cerrar (o 'q'): " choice
    [[ -z "$choice" || "$choice" == "q" ]] && return 0

    if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#sessions} )); then
        local target_line="${sessions[$choice]}"
        local tty=$(echo "$target_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^(pts\/|tty)/) {print $i; exit}}')
        local user=$(echo "$target_line" | awk '{print $1}')
        
        if [[ -z "$tty" ]]; then msg_err "No se pudo identificar el TTY."; return 0; fi

        msg_warn "Vas a cerrar la sesión de '$user' en el TTY '$tty'."
        confirm "¿Estás seguro?" || return 0

        sudo pkill -9 -t "$tty"
        if [ $? -eq 0 ]; then
            msg_ok "Sesión en $tty cerrada."
            users_log "CERRAR_SESION: $user en $tty"
        else
            msg_err "No se pudo cerrar la sesión en $tty."
        fi
    else
        msg_err "Selección no válida."
    fi
}

users_kill_all_sessions() {
    clear
    # 1. Listar usuarios con procesos activos (excluyendo procesos del sistema)
    msg_info "Usuarios con procesos activos (incluye shells abiertas):"
    print -r -- "----------------------------------------------------------"
    # Buscamos procesos que no sean del sistema (UID >= 1000 o root)
    local -a active_users
    active_users=( $(ps -eo user= | sort -u | while read -r u; do
        local uid=$(id -u "$u" 2>/dev/null)
        if [[ -n "$uid" && "$uid" -ge 1000 ]] || [[ "$u" == "root" ]]; then
            echo "$u"
        fi
    done) )
    
    if (( ${#active_users} == 0 )); then
        msg_warn "No hay usuarios con procesos activos."
        return 0
    fi

    local i=1 u
    for u in "${active_users[@]}"; do
        # Mostramos cuántos procesos tiene cada uno
        local count=$(ps -u "$u" --no-headers | wc -l)
        printf " %2d) %-15s (%d procesos)\n" "$i" "$u" "$count"
        i=$(( i + 1 ))
    done
    print -r -- "----------------------------------------------------------"

    local choice
    prompt_input "Número del usuario cuyas sesiones/procesos deseas cerrar (o 'q'): " choice
    [[ -z "$choice" || "$choice" == "q" ]] && return 0

    if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#active_users} )); then
        local target_user="${active_users[$choice]}"
        
        msg_warn "Vas a cerrar TODAS las sesiones y procesos del usuario '$target_user'."
        confirm "¿Estás seguro?" || return 0

        # Método 1: pkill (mata todos los procesos del usuario)
        msg_info "Cerrando procesos del usuario '$target_user'..."
        sudo pkill -9 -u "$target_user"
        
        # Método 2: loginctl (si existe, para limpiar la sesión de systemd)
        if command -v loginctl &>/dev/null; then
            local uid=$(id -u "$target_user" 2>/dev/null)
            if [[ -n "$uid" ]]; then
                msg_info "Cerrando sesión vía loginctl (UID: $uid)..."
                sudo loginctl terminate-user "$uid" 2>/dev/null || true
            fi
        fi

        # Verificación
        sleep 1
        if pgrep -u "$target_user" &>/dev/null; then
            msg_err "Algunos procesos de '$target_user' todavía están vivos. Revisa con 'ps -u $target_user'."
        else
            msg_ok "Todas las sesiones y procesos de '$target_user' han sido cerrados."
            log_action "Usuarios: sesiones/procesos cerrados para $target_user"
            users_log "CERRAR_TODAS_SESIONES: $target_user"
        fi
    else
        msg_err "Selección no válida."
    fi
}

# --- 5. MENÚ PRINCIPAL ---
menu_users() {
    run_menu "GESTIÓN DE USUARIOS Y GRUPOS" \
        "#CONSULTAS" \
        "Listar usuarios del sistema|users_list" \
        "Listar grupos del sistema|users_list_groups" \
        "Información detallada de un usuario|users_info" \
        "Usuarios conectados y últimos logins|users_active_sessions" \
        "Historial de inicios de sesión (last)|users_logins_history" \
        "#GESTIÓN DE USUARIOS" \
        "Crear un nuevo usuario|users_create" \
        "Eliminar un usuario|users_delete" \
        "Cambiar contraseña de un usuario|users_change_password" \
        "Cerrar sesión de un usuario/TTY|users_kill_session" \
	"Cerrar TODAS las sesiones de un usuario|users_kill_all_sessions" \
        "#GESTIÓN DE GRUPOS" \
        "Crear un nuevo grupo|users_create_group" \
        "Eliminar un grupo|users_delete_group" \
        "Añadir usuario a un grupo|users_add_to_group" \
        "Eliminar usuario de un grupo|users_remove_from_group"
}
