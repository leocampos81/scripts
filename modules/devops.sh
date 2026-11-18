#!/usr/bin/env zsh
# Módulo: DevOps & Automatización

# --- SISTEMA UPDATE ---
sys_update_system() {
    if [[ "$PKG_MGR" == "unknown" ]]; then msg_err "No se detectó gestor de paquetes."; return 0; fi
    confirm "¿Actualizar TODOS los paquetes con $PKG_MGR?" || { msg_info "Cancelado."; return 0; }
    msg_info "Actualizando sistema con $PKG_MGR..."
    case "$PKG_MGR" in
        apt)    sudo apt-get update && sudo apt-get dist-upgrade -y ;;
        dnf)    sudo dnf upgrade -y --refresh --nobest --skip-broken ;;
        pacman) sudo pacman -Syu --noconfirm ;;
    esac
    msg_ok "Sistema actualizado."
    log_action "Sistema: actualización con $PKG_MGR"
}

# --- GIT MULTI-REMOTO (Rediseñado) ---
git_ok() {
    command -v git &>/dev/null || { need git || return 1; }
    if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        msg_err "No hay un repositorio Git en $REPO_DIR"
        return 1
    fi
}

# Función interna para hacer el push/pull según el menú
git_action_push() {
    local rem="$1"
    if [[ "$rem" == "BOTH" ]]; then
        for r in $(git -C "$REPO_DIR" remote); do
            msg_info " -> Subiendo a '$r'..."
            git -C "$REPO_DIR" push "$r" 2>&1
        done
    else
        msg_info "Subiendo a '$rem'..."
        git -C "$REPO_DIR" push "$rem" 2>&1
    fi
}

git_action_pull() {
    local rem="$1"
    if [[ "$rem" == "BOTH" ]]; then
        rem="origin" # El pull siempre se hace desde el principal para evitar conflictos
    fi
    msg_info "Descargando desde '$rem'..."
    if ! git -C "$REPO_DIR" pull "$rem" --ff-only 2>/dev/null; then
        git -C "$REPO_DIR" pull "$rem" --no-rebase
    fi
}

# --- MENÚS GIT ESPECÍFICOS ---
menu_git_remote() {
    local rem_name="$1"
    local rem_label="$2"
    local color="$3"
    
    while true; do
        clear
        print "=========================================================="
        print -r -- "  ${color}GIT: $rem_label${C_RST}"
        print "=========================================================="
        print " 1) Ver estado del repositorio"
        print " 2) Ver últimos commits"
        print " 3) Descargar cambios (git pull)"
        print " 4) Subir cambios (git push)"
        print ""
        print " q) Volver al menú de Git"
        print "=========================================================="
        local opt; prompt_input "Elige una opción [1-4 o q]: " opt
        case "$opt" in
            1) 
                msg_info "Rama actual: $(git -C "$REPO_DIR" branch --show-current)"
                git -C "$REPO_DIR" status -sb
                pause_screen ;;
            2) 
                git -C "$REPO_DIR" log --oneline --decorate -n 5
                pause_screen ;;
            3) 
                git_action_pull "$rem_name"
                pause_screen ;;
            4) 
                if [[ -z "$(git -C "$REPO_DIR" status -s)" ]]; then msg_warn "No hay cambios para subir."; pause_screen; continue; fi
                msg_info "Archivos modificados:"; git -C "$REPO_DIR" status -s
                local msg; prompt_input "Mensaje de commit: " msg
                [[ -z "$msg" ]] && continue
                git -C "$REPO_DIR" add -A && git -C "$REPO_DIR" commit -m "$msg" || { pause_screen; continue; }
                git_action_push "$rem_name"
                pause_screen ;;
            q|Q) return 0 ;;
            *) msg_warn "Opción no válida."; sleep 1 ;;
        esac
    done
}

menu_git_both() {
    while true; do
        clear
        print "=========================================================="
        print -r -- "  ${C_YEL}GIT: AMBOS REMOTOS (Sincronización Total)${C_RST}"
        print "=========================================================="
        print " 1) Ver estado del repositorio"
        print " 2) Ver últimos commits"
        print " 3) Descargar cambios (Pull desde 'origin')"
        print " 4) Subir cambios a TODOS (Push a todos los remotos)"
        print ""
        print " q) Volver al menú de Git"
        print "=========================================================="
        local opt; prompt_input "Elige una opción [1-4 o q]: " opt
        case "$opt" in
            1) 
                msg_info "Rama actual: $(git -C "$REPO_DIR" branch --show-current)"
                git -C "$REPO_DIR" status -sb
                pause_screen ;;
            2) 
                git -C "$REPO_DIR" log --oneline --decorate -n 5
                pause_screen ;;
            3) 
                git_action_pull "BOTH"
                pause_screen ;;
            4) 
                if [[ -z "$(git -C "$REPO_DIR" status -s)" ]]; then msg_warn "No hay cambios para subir."; pause_screen; continue; fi
                msg_info "Archivos modificados:"; git -C "$REPO_DIR" status -s
                local msg; prompt_input "Mensaje de commit: " msg
                [[ -z "$msg" ]] && continue
                git -C "$REPO_DIR" add -A && git -C "$REPO_DIR" commit -m "$msg" || { pause_screen; continue; }
                git_action_push "BOTH"
                pause_screen ;;
            q|Q) return 0 ;;
            *) msg_warn "Opción no válida."; sleep 1 ;;
        esac
    done
}

menu_git() {
    git_ok || return 0
    while true; do
        clear
        print "=========================================================="
        print -r -- "  SINCRONIZACIÓN GIT"
        print "=========================================================="
        print " ¿Con qué repositorio quieres trabajar hoy?"
        print ""
        
        # Autodetección de remotos y armado del menú
        local -a remotes
        remotes=(${(f)"$(git -C "$REPO_DIR" remote)"})
        local -A rmap
        local i=1 r url label color
        
        for r in "${remotes[@]}"; do
            url=$(git -C "$REPO_DIR" remote get-url "$r" 2>/dev/null)
            label="$r"
            color="$C_RST"
            if [[ "$url" == *"github.com"* ]]; then label="$r (GitHub)"; color="$C_CYN"
            elif [[ "$url" == *"gitlab.com"* ]]; then label="$r (GitLab)"; color="$C_ORG"; fi
            
            # Usamos print en lugar de printf para evitar el error "bad option: -"
            print " $i) ${color}${label}${C_RST}"
            rmap[$i]="$r|$label|$color"
            i=$(( i + 1 ))
        done
        
        if (( ${#remotes} > 1 )); then
            print " $i) ${C_YEL}AMBOS (Sincronizar con todos)${C_RST}"
            rmap[$i]="BOTH|Ambos Remotos|$C_YEL"
        fi
        
        print ""
        print " q) Volver al menú principal"
        print "=========================================================="
        
        local choice; prompt_input "Elige una opción [1-$i o q]: " choice
        [[ -z "$choice" || "$choice" == "q" ]] && return 0
        
        if [[ "$choice" == <-> && -n "${rmap[$choice]:-}" ]]; then
            local data="${rmap[$choice]}"
            local rname="${data%%|*}"
            local rest="${data#*|}"
            local rlabel="${rest%%|*}"
            local rcolor="${rest##*|}"
            
            if [[ "$rname" == "BOTH" ]]; then
                menu_git_both
            else
                menu_git_remote "$rname" "$rlabel" "$rcolor"
            fi
        else
            msg_warn "Opción no válida."; sleep 1
        fi
    done
}

# --- AUTOMATIZACIÓN (Ansible / Terraform) ---
AUTO_BASE="${PROM_AUTOMATION_DIR:-$HOME}"

auto_overview() {
    section "ENTORNO DE AUTOMATIZACIÓN"
    kv "Carpeta base" "$AUTO_BASE"
    local v
    if command -v ansible &>/dev/null; then v=$(ansible --version 2>/dev/null | head -n1); else v="no instalado"; fi
    kv "Ansible" "$v"
    if command -v terraform &>/dev/null; then v=$(terraform version 2>/dev/null | head -n1); else v="no instalado"; fi
    kv "Terraform" "$v"
}

auto_set_base() {
    local d; prompt_input "Carpeta base [actual: $AUTO_BASE]: " d
    [[ -z "$d" ]] && return 0
    if [[ -d "$d" ]]; then AUTO_BASE="$d"; msg_ok "Base: $AUTO_BASE"; else msg_err "No existe."; fi
}

auto_find() {
    timeout 20 find "$AUTO_BASE" -maxdepth "$1" '(' -name .git -o -name .terraform -o -name node_modules ')' -prune -o "${@:2}" -print 2>/dev/null
}

ans_playbooks() {
    need ansible || return 0
    local -a plays
    plays=( ${(f)"$(auto_find 5 -type f -name '*.yml')"} )
    if (( ${#plays} == 0 )); then msg_warn "No se encontraron playbooks .yml en $AUTO_BASE."; return 0; fi
    local i=1 f
    for f in "${plays[@]}"; do print " $i) $f"; i=$((i+1)); done
    local play; prompt_input "Selecciona el número del playbook: " play
    [[ -z "$play" ]] && return 0
    if [[ "$play" == <-> ]] && (( play >= 1 && play <= ${#plays} )); then
        local target="${plays[$play]}"
        msg_warn "Ejecutando playbook: $target"
        ( cd "${target:h}" && ansible-playbook "$target" )
    fi
}

tf_plan() {
    need terraform || return 0
    local -a dirs
    dirs=( ${(f)"$(auto_find 5 -type f -name '*.tf' | xargs -n1 dirname 2>/dev/null | sort -u)"} )
    if (( ${#dirs} == 0 )); then msg_warn "No se encontraron proyectos .tf en $AUTO_BASE."; return 0; fi
    local i=1 d
    for d in "${dirs[@]}"; do print " $i) $d"; i=$((i+1)); done
    local proj; prompt_input "Selecciona el número del proyecto: " proj
    [[ -z "$proj" ]] && return 0
    if [[ "$proj" == <-> ]] && (( proj >= 1 && proj <= ${#dirs} )); then
        local target="${dirs[$proj]}"
        msg_info "Ejecutando init + plan en $target..."
        ( cd "$target" && terraform init -input=false >/dev/null && terraform plan )
    fi
}

menu_automation() {
    run_menu "HERRAMIENTAS DE AUTOMATIZACIÓN (IaC)" \
        "Estado del entorno|auto_overview" \
        "Cambiar carpeta base|auto_set_base" \
        "#ANSIBLE" \
        "Listar y ejecutar playbooks|ans_playbooks" \
        "#TERRAFORM" \
        "Planificar cambios (init + plan)|tf_plan"
}

# --- DOCKER ---
dk_list_names() { "${DOCKER[@]}" ps -a --format '  > {{.Names}} ({{.Status}})' 2>/dev/null; }
dk_ps() { "${DOCKER[@]}" ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null; }
dk_stats() { "${DOCKER[@]}" stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null; }
dk_logs() {
    dk_list_names
    local n; prompt_input "Nombre del contenedor: " n
    [[ -z "$n" ]] && return 0
    run_interruptible "${DOCKER[@]}" logs -f --tail 50 "$n"
}
dk_ctl() {
    dk_list_names
    local n a; prompt_input "Nombre del contenedor: " n; prompt_input "1) Restart 2) Stop 3) Start: " a
    case "$a" in
        1) sudo docker restart "$n" ;;
        2) sudo docker stop "$n" ;;
        3) sudo docker start "$n" ;;
    esac
}
dk_prune() {
    confirm "¿Ejecutar docker system prune -f?" || return 0
    sudo docker system prune -f
}

menu_docker() {
    if ! need docker; then pause_screen; return 0; fi
    if docker info &>/dev/null; then DOCKER=(docker); else DOCKER=("${SUDO[@]}" docker); fi
    run_menu "GESTIÓN Y ESTADO DE DOCKER" \
        "Ver contenedores|dk_ps" \
        "Monitoreo CPU/RAM|dk_stats" \
        "Logs de un contenedor|dk_logs" \
        "Reiniciar / Detener / Iniciar|dk_ctl" \
        "Limpieza general|dk_prune"
}

# --- Menú principal del módulo ---
devops_menu() {
    run_menu "DEVOPS & AUTOMATIZACIÓN" \
        "Mantenimiento y sincronización Git|menu_git|nopause" \
        "Herramientas de automatización (Ansible, Terraform)|menu_automation|nopause" \
        "Servicios y contenedores Docker|menu_docker|nopause"
}
