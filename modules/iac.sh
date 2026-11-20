#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: IAC  -  infraestructura como código: Ansible y Terraform/OpenTofu
#  Se carga con 'source' desde prom_claude.sh (no se ejecuta directamente).
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

ANS_VER=""; ANS_CFG=""; ANS_INV=""; ANS_INV_INFO=""; ANS_PLAY=""; ANS_LIMIT=""; ANS_CHECKED=""
typeset -ga ANS_ARGS
TF_BIN=""; TF_VER=""; TF_DIR=""; TF_VARFILE=""; TF_PLAN="prom.tfplan"
typeset -ga TF_ARGS

auto_set_base() {
    local d
    prompt_input "Carpeta base de búsqueda [actual: $AUTO_BASE]: " d
    [[ -z "$d" ]] && return 0
    if [[ ! -d "$d" ]]; then msg_err "No existe la carpeta '$d'."; return 0; fi
    AUTO_BASE="${d:A}"
    msg_ok "Carpeta base: $AUTO_BASE"
    log_action "Automatización: base = $AUTO_BASE"
}

# ------------------------------------------------------------------------------
#  Descubrimiento
# ------------------------------------------------------------------------------
ans_find_playbooks() {
    local f
    auto_find 5 -type f '(' -name '*.yml' -o -name '*.yaml' ')' | while IFS= read -r f; do
        [[ "$f" == */roles/* || "$f" == */group_vars/* || "$f" == */host_vars/* || "$f" == */molecule/* ]] && continue
        grep -qE '^[[:space:]]*-?[[:space:]]*hosts:' "$f" 2>/dev/null || continue
        grep -qE '^[[:space:]]*-?[[:space:]]*(tasks|roles|pre_tasks|post_tasks|import_playbook):' "$f" 2>/dev/null \
            && print -r -- "$f"
    done | sort
}

ans_find_inventories() {
    {
        auto_find 5 -type f '(' -iname 'inventory*' -o -name hosts -o -name 'hosts.ini' -o -name 'hosts.yml' -o -name 'hosts.yaml' ')' \
            | grep -vE '\.(md|txt|sh|py|j2)$'
        [[ -f /etc/ansible/hosts ]] && print -r -- /etc/ansible/hosts
    } | sort -u
}

tf_find_dirs() {
    auto_find 5 -type f -name '*.tf' | grep -v '/modules/' | sed 's#/[^/]*$##' | sort -u
}

auto_overview() {
    section "ENTORNO DE AUTOMATIZACIÓN"
    kv "Carpeta base" "$AUTO_BASE"
    local v
    if command -v ansible &>/dev/null; then v=$(ansible --version 2>/dev/null | head -n1); else v="no instalado"; fi
    kv "Ansible" "$v"
    command -v ansible-lint &>/dev/null && kv "ansible-lint" "instalado" || kv "ansible-lint" "no instalado"
    if command -v terraform &>/dev/null; then v=$(terraform version 2>/dev/null | head -n1); else v="no instalado"; fi
    kv "Terraform" "$v"
    if command -v tofu &>/dev/null; then v=$(tofu version 2>/dev/null | head -n1); else v="no instalado"; fi
    kv "OpenTofu" "$v"
    msg_info "Buscando proyectos (hasta 5 niveles bajo la base)..."
    kv "Playbooks" "$(ans_find_playbooks | wc -l | tr -d ' ') encontrados"
    kv "Inventarios" "$(ans_find_inventories | wc -l | tr -d ' ') encontrados"
    kv "Proyectos TF" "$(tf_find_dirs | wc -l | tr -d ' ') carpetas con *.tf"
    local nk rc
    nk=$(ssh-add -l 2>/dev/null); rc=$?
    case $rc in
        0) kv "ssh-agent" "${C_GRN}[OK]${C_RST} $(print -r -- "$nk" | wc -l | tr -d ' ') clave(s) cargada(s)" ;;
        1) kv "ssh-agent" "${C_YEL}[!]${C_RST} activo pero sin claves (ssh-add)" ;;
        *) kv "ssh-agent" "${C_YEL}[!]${C_RST} sin agente (Ansible usará claves por defecto o -K)" ;;
    esac
}

# ==============================================================================
#  ANSIBLE
# ==============================================================================
ans_inv_info() {
    local g hosts groups
    g=$(ansible-inventory -i "$ANS_INV" --graph 2>/dev/null)
    if [[ -z "$g" ]]; then ANS_INV_INFO="no se pudo leer: revisa la sintaxis"; return; fi
    hosts=$(print -r -- "$g" | grep -E '\|--[^@]' | sed 's/.*|--//' | sort -u | wc -l | tr -d ' ')
    groups=$(print -r -- "$g" | grep -c '@')
    ANS_INV_INFO="$hosts hosts / $groups grupos"
}

ans_panel() {
    print ""
    kv "Versión" "${ANS_VER:-N/D}"
    kv "Config" "${ANS_CFG:-ninguno}"
    kv "Inventario" "${ANS_INV:-(sin seleccionar)}${ANS_INV:+  [$ANS_INV_INFO]}"
    kv "Playbook" "${ANS_PLAY:-(sin seleccionar)}"
    kv "Límite" "${ANS_LIMIT:-(todos los hosts)}"
    local nk rc
    nk=$(ssh-add -l 2>/dev/null); rc=$?
    case $rc in
        0) kv "ssh-agent" "${C_GRN}[OK]${C_RST} $(print -r -- "$nk" | wc -l | tr -d ' ') clave(s) cargada(s)" ;;
        1) kv "ssh-agent" "${C_YEL}[!]${C_RST} activo pero sin claves" ;;
        *) kv "ssh-agent" "${C_YEL}[!]${C_RST} sin agente" ;;
    esac
}

# Ejecuta ansible-playbook desde la carpeta del playbook (ansible.cfg y roles/ del proyecto)
ans_pb() { ( cd "${ANS_PLAY:h}" && ansible-playbook "$@" ); }

ans_need_inv()  { [[ -n "$ANS_INV"  ]] && return 0; msg_warn "Primero selecciona un inventario."; return 1; }
ans_need_play() { [[ -n "$ANS_PLAY" ]] && return 0; msg_warn "Primero selecciona un playbook.";  return 1; }

# Argumentos comunes: inventario + límite
ans_base_opts() {
    ANS_ARGS=(-i "$ANS_INV")
    [[ -n "$ANS_LIMIT" ]] && ANS_ARGS+=(--limit "$ANS_LIMIT")
}

ans_ask_become() {
    if confirm "¿Elevar privilegios (become/sudo)?"; then
        ANS_ARGS+=(-b)
        confirm "¿Pedir contraseña de sudo (-K)?" && ANS_ARGS+=(-K)
    fi
}

ans_select_inv() {
    local -a found
    found=( ${(f)"$(ans_find_inventories)"} )
    found+=("[escribir ruta manualmente]")
    pick_from_list "Inventarios encontrados bajo $AUTO_BASE:" "${found[@]}" || return 0
    local choice="$PICKED"
    if [[ "$choice" == "[escribir ruta manualmente]" ]]; then
        prompt_input "Ruta del inventario (archivo o carpeta): " choice
    fi
    [[ -z "$choice" ]] && return 0
    if [[ ! -e "$choice" ]]; then msg_err "No existe: $choice"; return 0; fi
    ANS_INV="${choice:A}"; ANS_LIMIT=""
    ans_inv_info
    msg_ok "Inventario activo: $ANS_INV ($ANS_INV_INFO)"
    log_action "Ansible: inventario $ANS_INV"
}

ans_select_play() {
    local -a found
    found=( ${(f)"$(ans_find_playbooks)"} )
    found+=("[escribir ruta manualmente]")
    pick_from_list "Playbooks encontrados bajo $AUTO_BASE:" "${found[@]}" || return 0
    local choice="$PICKED"
    if [[ "$choice" == "[escribir ruta manualmente]" ]]; then
        prompt_input "Ruta del playbook: " choice
    fi
    [[ -z "$choice" ]] && return 0
    if [[ ! -f "$choice" ]]; then msg_err "No existe: $choice"; return 0; fi
    ANS_PLAY="${choice:A}"; ANS_CHECKED=""
    msg_ok "Playbook activo: $ANS_PLAY"
    log_action "Ansible: playbook $ANS_PLAY"
}

ans_set_limit() {
    local l re='^[A-Za-z0-9_.:,!&*@-]+$'
    prompt_input "Límite de hosts/grupos (ej: web,db o 'srv*'; Enter = quitar): " l
    if [[ -z "$l" ]]; then ANS_LIMIT=""; msg_ok "Límite eliminado."; return 0; fi
    if [[ "$l" =~ $re ]]; then ANS_LIMIT="$l"; msg_ok "Límite: $ANS_LIMIT"; else msg_err "Patrón no válido."; fi
}

ans_graph() {
    ans_need_inv || return 0
    ansible-inventory -i "$ANS_INV" --graph
}

ans_list_inv() {
    ans_need_inv || return 0
    ansible-inventory -i "$ANS_INV" --list | head -n 200
    msg_info "(se muestran las primeras 200 líneas)"
}

ans_ping() {
    ans_need_inv || return 0
    ans_base_opts
    msg_info "ansible all -m ping (timeout 10 s)..."
    local out ok bad
    out=$(ansible all "${ANS_ARGS[@]}" -m ping -T 10 2>&1)
    print -r -- "$out"
    ok=$(print -r -- "$out" | grep -c 'SUCCESS')
    bad=$(print -r -- "$out" | grep -cE 'UNREACHABLE|FAILED')
    print ""
    print -r -- " Resumen: ${C_GRN}$ok OK${C_RST} / ${C_RED}$bad con problemas${C_RST}"
    log_action "Ansible: ping ($ok ok, $bad fallos)"
}

ans_adhoc() {
    ans_need_inv || return 0
    local choice cmd svc
    print " 1) uptime"
    print " 2) df -hP (discos)"
    print " 3) free -h (memoria)"
    print " 4) Estado de un servicio (systemctl is-active)"
    print " 5) Comando personalizado"
    prompt_input "Elige [1-5]: " choice
    case "$choice" in
        1) cmd="uptime" ;;
        2) cmd="df -hP" ;;
        3) cmd="free -h" ;;
        4) prompt_input "Nombre del servicio: " svc
           valid_ident "$svc" || { msg_err "Nombre no válido."; return 0; }
           cmd="systemctl is-active $svc" ;;
        5) prompt_input "Comando (módulo 'command', sin pipes ni redirecciones): " cmd
           [[ -z "$cmd" ]] && return 0
           confirm "¿Ejecutar '$cmd' en todos los hosts del alcance?" || return 0 ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    ans_base_opts
    ans_ask_become
    ansible all "${ANS_ARGS[@]}" -m command -a "$cmd"
    log_action "Ansible: ad-hoc '$cmd'"
}

ans_facts() {
    ans_need_inv || return 0
    ans_base_opts
    msg_info "Distribución y versión de cada host:"
    ansible all "${ANS_ARGS[@]}" -m setup -a 'filter=ansible_distribution*' -T 10 2>&1 \
        | grep -E 'SUCCESS|UNREACHABLE|FAILED|"ansible_distribution(_version)?"'
    log_action "Ansible: facts de distribución"
}

# Tags opcionales para playbooks
ans_pb_opts() {
    ans_base_opts
    local tags re='^[A-Za-z0-9_,.-]+$'
    prompt_input "Tags (separados por coma, Enter = todos): " tags
    if [[ -n "$tags" ]]; then
        [[ "$tags" =~ $re ]] && ANS_ARGS+=(--tags "$tags") || { msg_err "Tags no válidos."; return 1; }
    fi
    return 0
}

ans_syntax() {
    ans_need_play || return 0
    ans_base_opts
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY" --syntax-check \
        && msg_ok "Sintaxis correcta." || msg_err "Se encontraron errores de sintaxis."
    log_action "Ansible: syntax-check $ANS_PLAY"
}

ans_lint() {
    ans_need_play || return 0
    if ! command -v ansible-lint &>/dev/null; then
        msg_warn "ansible-lint no está instalado."
        need ansible-lint || { msg_info "Alternativa: pipx install ansible-lint"; return 0; }
    fi
    ansible-lint "$ANS_PLAY"
    log_action "Ansible: lint $ANS_PLAY"
}

ans_tasks() {
    ans_need_play || return 0
    ans_base_opts
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY" --list-tasks --list-tags
}

ans_check() {
    ans_need_inv || return 0
    ans_need_play || return 0
    ans_pb_opts || return 0
    ans_ask_become
    msg_info "Dry-run (--check --diff): no se aplican cambios."
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY" --check --diff
    ANS_CHECKED="$ANS_PLAY"
    log_action "Ansible: check $ANS_PLAY"
}

ans_run() {
    ans_need_inv || return 0
    ans_need_play || return 0
    ans_pb_opts || return 0
    ans_ask_become
    msg_info "Hosts que se verán afectados:"
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY" --list-hosts
    if [[ "$ANS_CHECKED" != "$ANS_PLAY" ]]; then
        msg_warn "No has ejecutado --check con este playbook en esta sesión."
    fi
    confirm "¿EJECUTAR el playbook de verdad?" || { msg_info "Cancelado."; return 0; }
    ans_pb "${ANS_ARGS[@]}" "$ANS_PLAY"
    log_action "Ansible: RUN $ANS_PLAY (rc=$?)"
}

ans_galaxy() {
    local req
    [[ -n "$ANS_PLAY" && -f "${ANS_PLAY:h}/requirements.yml" ]] && req="${ANS_PLAY:h}/requirements.yml"
    if [[ -n "$req" ]] && confirm "Se encontró $req. ¿Instalar dependencias?"; then
        ansible-galaxy install -r "$req"
        log_action "Ansible: galaxy install $req"
    fi
    msg_info "Collections instaladas:"
    ansible-galaxy collection list 2>/dev/null | head -n 30
    msg_info "Roles instalados:"
    ansible-galaxy role list 2>/dev/null | head -n 30
}

ans_vault() {
    local f choice
    prompt_input "Archivo (vault): " f
    [[ -f "$f" ]] || { msg_err "El archivo no existe."; return 0; }
    print " 1) Ver (view)   2) Editar (edit)   3) Cifrar (encrypt)"
    prompt_input "Elige [1-3]: " choice
    case "$choice" in
        1) ansible-vault view "$f" ;;
        2) ansible-vault edit "$f" ;;
        3) ansible-vault encrypt "$f" ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    log_action "Ansible: vault ($choice) en $f"
}

ans_config() {
    msg_info "Configuración modificada respecto a los valores por defecto:"
    ansible-config dump --only-changed
}

menu_ansible() {
    if ! need ansible; then pause_screen; return 0; fi
    ANS_VER=$(ansible --version 2>/dev/null | head -n1)
    ANS_CFG=$(ansible --version 2>/dev/null | awk -F' = ' '/config file/{print $2; exit}')
    MENU_HOOK=ans_panel
    run_menu "ANSIBLE - CENTRO DE CONTROL" \
        "#PROYECTO ACTIVO" \
        "Seleccionar inventario (autodetección)|ans_select_inv" \
        "Seleccionar playbook (autodetección)|ans_select_play" \
        "Definir límite de hosts (--limit)|ans_set_limit" \
        "#DIAGNÓSTICO DE HOSTS" \
        "Ver inventario como árbol (--graph)|ans_graph" \
        "Ver inventario completo (--list)|ans_list_inv" \
        "Ping a todos los hosts (con resumen OK/fallos)|ans_ping" \
        "Distro y versión de cada host (facts)|ans_facts" \
        "Comando ad-hoc (uptime, df, free, servicio...)|ans_adhoc" \
        "#PLAYBOOK (flujo seguro: sintaxis > lint > check > run)" \
        "Validar sintaxis|ans_syntax" \
        "Lint (ansible-lint)|ans_lint" \
        "Listar tareas y tags|ans_tasks" \
        "Dry-run (--check --diff)|ans_check" \
        "EJECUTAR playbook (lista hosts y pide confirmación)|ans_run" \
        "#MANTENIMIENTO" \
        "Galaxy: dependencias, collections y roles|ans_galaxy" \
        "Vault: ver / editar / cifrar|ans_vault" \
        "Configuración activa (ansible-config)|ans_config"
    MENU_HOOK=""
}

# ==============================================================================
#  TERRAFORM / OPENTOFU
# ==============================================================================
tfx() { "$TF_BIN" -chdir="$TF_DIR" "$@"; }

tf_need_dir() { [[ -n "$TF_DIR" && -d "$TF_DIR" ]] && return 0; msg_warn "Primero selecciona un proyecto."; return 1; }

tf_need_init() {
    [[ -d "$TF_DIR/.terraform" ]] && return 0
    msg_warn "El proyecto no está inicializado."
    confirm "¿Ejecutar '$TF_BIN init' ahora?" || return 1
    tfx init
}

tf_var_args() {
    TF_ARGS=()
    [[ -n "$TF_VARFILE" ]] && TF_ARGS+=(-var-file="$TF_VARFILE")
}

tf_panel() {
    print ""
    kv "Binario" "${TF_VER:-N/D}"
    kv "Proyecto" "${TF_DIR:-(sin seleccionar)}"
    [[ -n "$TF_DIR" && -d "$TF_DIR" ]] || return 0

    local -a tfs=("$TF_DIR"/*.tf(N))
    kv "Archivos .tf" "${#tfs}"
    if [[ -d "$TF_DIR/.terraform" ]]; then
        kv "Init" "${C_GRN}[OK]${C_RST} inicializado"
        local ws; ws=$(timeout 5 "$TF_BIN" -chdir="$TF_DIR" workspace show 2>/dev/null)
        kv "Workspace" "${ws:-N/D}"
        local sl rc
        sl=$(TF_INPUT=0 timeout 5 "$TF_BIN" -chdir="$TF_DIR" state list 2>/dev/null < /dev/null); rc=$?
        if (( rc == 0 )); then
            if [[ -z "$sl" ]]; then kv "Estado" "vacío (nada desplegado)"
            else kv "Estado" "$(print -r -- "$sl" | wc -l | tr -d ' ') recursos gestionados"; fi
        else
            kv "Estado" "no consultable ahora (¿backend remoto sin credenciales?)"
        fi
    else
        kv "Init" "${C_YEL}[!]${C_RST} pendiente (ejecuta init)"
    fi

    local prov=""
    if [[ -f "$TF_DIR/.terraform.lock.hcl" ]]; then
        prov=$(grep -E '^provider "' "$TF_DIR/.terraform.lock.hcl" | sed -E 's#^provider "[^/]*/##; s#".*##' | tr '\n' ' ')
        kv "Providers" "${prov:-ninguno}"
    fi
    # Servicios locales de los que dependen ciertos providers
    if [[ "$prov" == *docker* ]]; then
        if timeout 3 docker info &>/dev/null; then kv "Docker" "${C_GRN}[OK]${C_RST} daemon activo"
        else kv "Docker" "${C_YEL}[!]${C_RST} daemon inactivo o sin permisos (provider docker)"; fi
    fi
    if [[ "$prov" == *libvirt* ]]; then
        if systemctl is-active --quiet libvirtd 2>/dev/null || systemctl is-active --quiet virtqemud 2>/dev/null; then
            kv "libvirt" "${C_GRN}[OK]${C_RST} servicio activo"
        else
            kv "libvirt" "${C_YEL}[!]${C_RST} servicio inactivo (provider libvirt)"
        fi
    fi
    if [[ -f "$TF_DIR/$TF_PLAN" ]]; then
        kv "Plan guardado" "${C_YEL}sí${C_RST} ($(stat -c %y "$TF_DIR/$TF_PLAN" 2>/dev/null | cut -c1-16)) listo para apply"
    else
        kv "Plan guardado" "no"
    fi
    [[ -n "$TF_VARFILE" ]] && kv "Var-file" "${TF_VARFILE:t}"
    return 0
}

tf_select_dir() {
    local -a found
    found=( ${(f)"$(tf_find_dirs)"} )
    found+=("[escribir ruta manualmente]")
    pick_from_list "Proyectos Terraform bajo $AUTO_BASE (se omiten carpetas modules/):" "${found[@]}" || return 0
    local choice="$PICKED"
    if [[ "$choice" == "[escribir ruta manualmente]" ]]; then
        prompt_input "Ruta de la carpeta del proyecto: " choice
    fi
    [[ -z "$choice" ]] && return 0
    if [[ ! -d "$choice" ]]; then msg_err "No existe la carpeta: $choice"; return 0; fi
    TF_DIR="${choice:A}"; TF_VARFILE=""
    msg_ok "Proyecto activo: $TF_DIR"
    log_action "Terraform: proyecto $TF_DIR"
}

tf_select_varfile() {
    tf_need_dir || return 0
    local -a vf
    vf=( ${(f)"$(find "$TF_DIR" -maxdepth 1 -type f '(' -name '*.tfvars' -o -name '*.tfvars.json' ')' 2>/dev/null | sort)"} )
    vf+=("(ninguno)")
    pick_from_list "Archivos de variables en $TF_DIR:" "${vf[@]}" || return 0
    if [[ "$PICKED" == "(ninguno)" ]]; then TF_VARFILE=""; msg_ok "Sin var-file."
    else TF_VARFILE="$PICKED"; msg_ok "Var-file: $TF_VARFILE"; fi
}

tf_init() {
    tf_need_dir || return 0
    local -a extra=()
    confirm "¿Incluir -upgrade (actualiza providers)?" && extra=(-upgrade)
    tfx init "${extra[@]}"
    log_action "Terraform: init en $TF_DIR"
}

tf_validate() {
    tf_need_dir || return 0
    tf_need_init || return 0
    tfx validate
}

tf_fmt() {
    tf_need_dir || return 0
    msg_info "Archivos que no cumplen el formato canónico:"
    tfx fmt -check -diff -recursive
    local rc=$?
    if (( rc == 3 )); then
        confirm "¿Aplicar 'fmt -recursive' para corregirlos?" && tfx fmt -recursive
    elif (( rc == 0 )); then
        msg_ok "Todo el código ya está formateado."
    fi
}

tf_plan() {
    tf_need_dir || return 0
    tf_need_init || return 0
    tf_var_args
    msg_info "$TF_BIN plan -out=$TF_PLAN"
    tfx plan -out="$TF_PLAN" "${TF_ARGS[@]}"
    local rc=$?
    (( rc == 0 )) && chmod 600 "$TF_DIR/$TF_PLAN" 2>/dev/null
    (( rc == 0 )) && msg_ok "Plan guardado. Revísalo y luego usa 'apply'."
    log_action "Terraform: plan en $TF_DIR (rc=$rc)"
}

tf_show_plan() {
    tf_need_dir || return 0
    [[ -f "$TF_DIR/$TF_PLAN" ]] || { msg_warn "No hay plan guardado."; return 0; }
    tfx show -no-color "$TF_PLAN" | ${PAGER:-less}
}

tf_drift() {
    tf_need_dir || return 0
    tf_need_init || return 0
    tf_var_args
    msg_info "Buscando diferencias entre el código y la infraestructura real..."
    local out rc
    out=$(tfx plan -detailed-exitcode -input=false -lock=false -no-color "${TF_ARGS[@]}" 2>&1); rc=$?
    print -r -- "$out" | tail -n 30
    print ""
    case $rc in
        0) msg_ok "Sin cambios: la infraestructura coincide con el código." ;;
        2) msg_warn "Hay diferencias (cambios pendientes o drift)." ;;
        *) msg_err "El plan falló (revisa credenciales/backend/variables)." ;;
    esac
    log_action "Terraform: drift en $TF_DIR (rc=$rc)"
}

tf_apply() {
    tf_need_dir || return 0
    if [[ ! -f "$TF_DIR/$TF_PLAN" ]]; then
        msg_warn "No hay plan guardado. 'apply' solo se permite desde un plan revisado: ejecuta 'plan' primero."
        return 0
    fi
    msg_info "Plan guardado el $(stat -c %y "$TF_DIR/$TF_PLAN" 2>/dev/null | cut -c1-16). Resumen:"
    tfx show -no-color "$TF_PLAN" | tail -n 25
    local ws ans
    ws=$(tfx workspace show 2>/dev/null)
    print ""
    msg_warn "Se aplicarán cambios REALES (workspace '${ws:-default}')."
    prompt_input "Escribe el nombre del proyecto (${TF_DIR:t}) para confirmar: " ans
    [[ "$ans" == "${TF_DIR:t}" ]] || { msg_info "Cancelado."; return 0; }
    tfx apply "$TF_PLAN"
    local rc=$?
    (( rc == 0 )) && rm -f "$TF_DIR/$TF_PLAN"
    log_action "Terraform: APPLY en $TF_DIR (rc=$rc)"
}

tf_destroy() {
    tf_need_dir || return 0
    tf_need_init || return 0
    tf_var_args
    msg_info "Generando plan de destrucción (aún no se destruye nada)..."
    tfx plan -destroy -out="$TF_PLAN" "${TF_ARGS[@]}" || return 0
    chmod 600 "$TF_DIR/$TF_PLAN" 2>/dev/null
    local ws ans
    ws=$(tfx workspace show 2>/dev/null)
    print ""
    msg_warn "PELIGRO: esto ELIMINARÁ la infraestructura del workspace '${ws:-default}'."
    prompt_input "Escribe exactamente 'DESTRUIR ${TF_DIR:t}' para continuar: " ans
    if [[ "$ans" != "DESTRUIR ${TF_DIR:t}" ]]; then
        rm -f "$TF_DIR/$TF_PLAN"; msg_info "Cancelado. Plan de destrucción descartado."; return 0
    fi
    tfx apply "$TF_PLAN"
    local rc=$?
    rm -f "$TF_DIR/$TF_PLAN"
    log_action "Terraform: DESTROY en $TF_DIR (rc=$rc)"
}

tf_state_list() { tf_need_dir || return 0; tf_need_init || return 0; tfx state list; }

tf_state_show() {
    tf_need_dir || return 0
    tf_need_init || return 0
    local -a res
    res=( ${(f)"$(tfx state list 2>/dev/null)"} )
    pick_from_list "Recursos en el estado:" "${res[@]}" || return 0
    tfx state show "$PICKED"
}

tf_output()    { tf_need_dir || return 0; tf_need_init || return 0; tfx output; }
tf_providers() { tf_need_dir || return 0; tf_need_init || return 0; tfx providers; }

tf_workspace() {
    tf_need_dir || return 0
    tf_need_init || return 0
    msg_info "Workspaces:"
    tfx workspace list
    local act name
    print " 1) Cambiar a un workspace existente   2) Crear uno nuevo"
    prompt_input "Elige [1-2, Enter = nada]: " act
    [[ -z "$act" ]] && return 0
    prompt_input "Nombre del workspace: " name
    valid_ident "$name" || { msg_err "Nombre no válido."; return 0; }
    case "$act" in
        1) tfx workspace select "$name" ;;
        2) tfx workspace new "$name" ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    log_action "Terraform: workspace $act $name en $TF_DIR"
}

menu_terraform() {
    TF_BIN=""
    if   command -v terraform &>/dev/null; then TF_BIN=terraform
    elif command -v tofu      &>/dev/null; then TF_BIN=tofu
    else
        need terraform
        msg_info "Alternativa libre y compatible: OpenTofu (https://opentofu.org/docs/intro/install/)"
        pause_screen; return 0
    fi
    TF_VER=$("$TF_BIN" version 2>/dev/null | head -n1)
    MENU_HOOK=tf_panel
    run_menu "TERRAFORM / OPENTOFU - CENTRO DE CONTROL" \
        "#PROYECTO ACTIVO" \
        "Seleccionar proyecto (autodetección de carpetas *.tf)|tf_select_dir" \
        "Seleccionar archivo de variables (var-file)|tf_select_varfile" \
        "#PREPARAR Y VALIDAR" \
        "init (opcional -upgrade)|tf_init" \
        "validate|tf_validate" \
        "fmt (revisar y corregir formato)|tf_fmt" \
        "#CAMBIOS (flujo seguro: plan > revisar > apply)" \
        "plan (guarda plan en $TF_PLAN)|tf_plan" \
        "Ver el plan guardado|tf_show_plan" \
        "Detectar drift (plan -detailed-exitcode)|tf_drift" \
        "APPLY del plan guardado (pide escribir el nombre del proyecto)|tf_apply" \
        "DESTROY (plan previo + confirmación reforzada)|tf_destroy" \
        "#ESTADO" \
        "Listar recursos (state list)|tf_state_list" \
        "Ver un recurso (state show)|tf_state_show" \
        "Outputs|tf_output" \
        "Providers|tf_providers" \
        "Workspaces: listar / cambiar / crear|tf_workspace"
    MENU_HOOK=""
}
