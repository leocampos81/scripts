#!/usr/bin/env zsh
# Módulo: Gestión de Usuarios y Grupos

# --- Listados y Consultas ---
users_list() {
    clear
    msg_info "Usuarios del sistema:"
    print -r -- "----------------------------------------------------------"
    # Mostramos los usuarios con UID >= 1000 (humanos) y el root
    awk -F: '$3 >= 1000 || $1 == "root" {printf "%-20s UID:%-6s GID:%-6s Home:%-25s Shell:%s\n", $1, $3, $4, $6, $7}' /etc/passwd
    print -r -- "----------------------------------------------------------"
}

users_groups() {
    clear
    msg_info "Grupos del sistema:"
    print -r -- "----------------------------------------------------------"
    awk -F: '{printf "%-20s GID:%-6s Miembros:%s\n", $1, $3, $4}' /etc/group | head -n 30
    print -r -- "----------------------------------------------------------"
}

users_info() {
    local user
    prompt_input "Nombre de usuario a consultar: " user
    [[ -z "$user" ]] && return 0
    if id "$user" &>/dev/null; then
        clear
        msg_info "Información de '$user':"
        print -r -- "----------------------------------------------------------"
        id "$user"
        echo ""
        # Mostrar detalles del /etc/passwd
        grep "^$user:" /etc/passwd | awk -F: '{printf "Home: %s\nShell: %s\n", $6, $7}'
        echo ""
        # Mostrar si tiene sudo
        if groups "$user" | grep -qw "sudo"; then
            print -r -- "${C_YEL}[!] El usuario pertenece al grupo 'sudo'${C_RST}"
        fi
        print -r -- "----------------------------------------------------------"
    else
        msg_err "El usuario '$user' no existe."
    fi
}

users_logged() {
    clear
    msg_info "Usuarios con sesión activa actualmente:"
    print -r -- "----------------------------------------------------------"
    who
    print -r -- "----------------------------------------------------------"
    msg_info "Últimos inicios de sesión (last):"
    print -r -- "----------------------------------------------------------"
    last -n 10
    print -r -- "----------------------------------------------------------"
}

# --- Creación y Modificación ---
users_create() {
    local user shell
    prompt_input "Nombre del nuevo usuario: " user
    valid_ident "$user" || { msg_err "Nombre no válido."; return 0; }
    
    if id "$user" &>/dev/null; then
        msg_err "El usuario '$user' ya existe."
        return 0
    fi

    prompt_input "Shell por defecto [Default: /bin/bash]: " shell
    shell="${shell:-/bin/bash}"

    msg_info "Creando usuario '$user' (se pedirá contraseña)..."
    # -m crea el home, -s asigna la shell
    sudo useradd -m -s "$shell" "$user"
    sudo passwd "$user"
    
    if id "$user" &>/dev/null; then
        msg_ok "Usuario '$user' creado correctamente."
        log_action "Usuario: creado $user"
    else
        msg_err "Falló la creación del usuario."
    fi
}

users_delete() {
    local user confirm_delete
    prompt_input "Nombre del usuario a eliminar: " user
    [[ -z "$user" ]] && return 0
    if ! id "$user" &>/dev/null; then
        msg_err "El usuario '$user' no existe."
        return 0
    fi
    
    prompt_input "¿Eliminar también el home directory? (s/n) [Default: n]: " confirm_delete
    if [[ "$confirm_delete" == "s" || "$confirm_delete" == "S" ]]; then
        sudo userdel -r "$user"
    else
        sudo userdel "$user"
    fi
    
    if ! id "$user" &>/dev/null; then
        msg_ok "Usuario '$user' eliminado."
        log_action "Usuario: eliminado $user"
    else
        msg_err "No se pudo eliminar el usuario."
    fi
}

users_change_password() {
    local user
    prompt_input "Usuario a cambiar contraseña: " user
    [[ -z "$user" ]] && return 0
    if id "$user" &>/dev/null; then
        sudo passwd "$user"
        msg_ok "Contraseña actualizada."
        log_action "Usuario: cambio de contraseña para $user"
    else
        msg_err "El usuario '$user' no existe."
    fi
}

users_add_to_group() {
    local user group
    prompt_input "Nombre del usuario: " user
    prompt_input "Nombre del grupo: " group
    [[ -z "$user" || -z "$group" ]] && return 0
    
    if ! id "$user" &>/dev/null; then msg_err "El usuario no existe."; return 0; fi
    if ! getent group "$group" &>/dev/null; then msg_err "El grupo no existe."; return 0; fi
    
    sudo usermod -aG "$group" "$user"
    msg_ok "Usuario '$user' añadido al grupo '$group'."
    msg_warn "Recuerda que el usuario debe cerrar y abrir sesión para aplicar el cambio."
    log_action "Usuario: $user añadido al grupo $group"
}

users_remove_from_group() {
    local user group
    prompt_input "Nombre del usuario: " user
    prompt_input "Nombre del grupo: " group
    [[ -z "$user" || -z "$group" ]] && return 0
    
    if ! id "$user" &>/dev/null; then msg_err "El usuario no existe."; return 0; fi
    
    sudo gpasswd -d "$user" "$group"
    msg_ok "Usuario '$user' eliminado del grupo '$group'."
    log_action "Usuario: $user eliminado del grupo $group"
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
        log_action "Grupo: creado $group"
    else
        msg_err "No se pudo crear el grupo."
    fi
}

users_delete_group() {
    local group
    prompt_input "Nombre del grupo a eliminar: " group
    [[ -z "$group" ]] && return 0
    
    if ! getent group "$group" &>/dev/null; then
        msg_err "El grupo '$group' no existe."
        return 0
    fi
    
    confirm "¿Eliminar el grupo '$group'?" || return 0
    sudo groupdel "$group"
    msg_ok "Grupo '$group' eliminado (si no era el grupo primario de algún usuario)."
    log_action "Grupo: eliminado $group"
}

# --- Menú del Módulo ---
menu_users() {
    run_menu "GESTIÓN DE USUARIOS Y GRUPOS" \
        "#CONSULTAS" \
        "Listar usuarios del sistema|users_list" \
        "Listar grupos del sistema|users_groups" \
        "Información detallada de un usuario|users_info" \
        "Usuarios conectados y últimos logins|users_logged" \
        "#GESTIÓN DE USUARIOS" \
        "Crear un nuevo usuario|users_create" \
        "Eliminar un usuario|users_delete" \
        "Cambiar contraseña de un usuario|users_change_password" \
        "#GESTIÓN DE GRUPOS" \
        "Crear un nuevo grupo|users_create_group" \
        "Eliminar un grupo|users_delete_group" \
        "Añadir usuario a un grupo|users_add_to_group" \
        "Eliminar usuario de un grupo|users_remove_from_group"
}
