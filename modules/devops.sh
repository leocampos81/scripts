#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: DEVOPS (menú y panel de estado). La lógica vive en git.sh, iac.sh y
#  docker.sh; este módulo solo los compone.
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

devops_panel() {
    print ""
    local br ch iac=""
    if git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        br=$(git -C "$REPO_DIR" branch --show-current); ch=$(git -C "$REPO_DIR" status -s | wc -l | tr -d ' ')
        kv "Git" "${REPO_DIR/#$HOME/~}  [${br:-HEAD desacoplado}, $ch cambios]"
    else
        kv "Git" "sin repositorio en ${REPO_DIR/#$HOME/~}"
    fi
    if command -v docker &>/dev/null; then
        if timeout 3 docker info &>/dev/null; then kv "Docker" "${C_GRN}[OK]${C_RST} daemon activo"
        else kv "Docker" "${C_YEL}[!]${C_RST} instalado, daemon inactivo o sin permisos"; fi
    else
        kv "Docker" "no instalado"
    fi
    command -v terraform &>/dev/null && iac="terraform "
    command -v tofu &>/dev/null && iac="${iac}tofu"
    kv "Ansible" "$(command -v ansible &>/dev/null && print instalado || print 'no instalado')"
    kv "Terraform/Tofu" "${iac:-no instalado}"
    kv "Base proyectos" "${AUTO_BASE/#$HOME/~}"
}

menu_devops() {
    MENU_HOOK=devops_panel
    run_menu "DEVOPS - CÓDIGO, INFRAESTRUCTURA Y CONTENEDORES" \
        "#CONTROL DE VERSIONES" \
        "Git multi-remoto: estado, pull, push, ramas|menu_git|nopause" \
        "#INFRAESTRUCTURA COMO CÓDIGO" \
        "Ansible: inventarios, playbooks, ad-hoc, vault|menu_ansible|nopause" \
        "Terraform / OpenTofu: plan, apply seguro, drift|menu_terraform|nopause" \
        "Entorno IaC: versiones y proyectos detectados|auto_overview" \
        "Cambiar carpeta base de búsqueda de proyectos|auto_set_base" \
        "#CONTENEDORES" \
        "Docker y Compose: contenedores, logs, shell, up/down|menu_docker|nopause"
}
