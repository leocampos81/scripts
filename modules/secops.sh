#!/usr/bin/env zsh
# ==============================================================================
#  Módulo: DEVSECOPS
#  Controles de seguridad para código, infraestructura, contenedores y host.
#  Usa los escáneres profesionales si están instalados (gitleaks, trivy, tfsec,
#  checkov, hadolint, ansible-lint, yamllint) y, si no, hace verificaciones
#  propias básicas. Los hallazgos de secretos NUNCA muestran el valor, solo
#  archivo:línea y el tipo, para no exponerlos en pantalla ni en el scrollback.
# ==============================================================================
[[ "$ZSH_EVAL_CONTEXT" == *:file* ]] || { print "Este archivo es un módulo de prom_claude.sh: no se ejecuta directamente."; exit 1; }

typeset -ga SEC_PATTERNS SEC_DOCKER
SEC_PATTERNS=(
    "Clave de acceso AWS|AKIA[0-9A-Z]{16}"
    "Clave privada|-----BEGIN ((RSA|EC|DSA|OPENSSH|PGP) )?PRIVATE KEY-----"
    "Token de GitHub|gh[pousr]_[A-Za-z0-9]{36,}"
    "Token de Slack|xox[baprs]-[A-Za-z0-9-]{10,}"
    "Clave API de Google|AIza[0-9A-Za-z_-]{35}"
    "JWT|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
    "Credencial asignada|(password|passwd|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9/+_.-]{8,}"
)
SEC_NOISE='(var\.|\$\{?[A-Za-z_]|\{\{|os\.environ|getenv|example|changeme|<[a-z_]+>)'

sec_dk() {   # deja en SEC_DOCKER el comando docker (con sudo si hace falta)
    SEC_DOCKER=(docker)
    docker info &>/dev/null || { (( EUID != 0 )) && SEC_DOCKER=(sudo docker); }
}

sec_panel() {
    print ""
    local t line=""
    for t in gitleaks trivy tfsec checkov hadolint ansible-lint yamllint; do
        if command -v "$t" &>/dev/null; then line+=" ${C_GRN}${t}${C_RST}"; else line+=" ${t}(-)"; fi
    done
    kv "Escáneres" "$line"
    kv "Repo activo" "${REPO_DIR/#$HOME/~}"
    kv "Nota" "sin escáner instalado se usan verificaciones básicas propias"
}

# ------------------------------------------------------------------------------
#  1) Secretos en código y archivos sensibles versionados
# ------------------------------------------------------------------------------
sec_secrets() {
    local d out rc p label rx total=0 n
    prompt_input "Carpeta a escanear [Default: $REPO_DIR]: " d
    d="${d:-$REPO_DIR}"
    [[ -d "$d" ]] || { msg_err "La carpeta '$d' no existe."; return 0; }

    if command -v gitleaks &>/dev/null; then
        msg_info "gitleaks (incluye el historial git si es un repositorio)..."
        out=$(gitleaks detect --source "$d" --no-banner --redact 2>&1); rc=$?
        if (( rc == 0 )); then msg_ok "gitleaks: sin secretos detectados."; return 0
        elif (( rc == 1 )); then print -r -- "$out" | tail -n 40; msg_err "gitleaks encontró secretos: rótalos y limpia el historial."; return 0
        else msg_warn "gitleaks falló (código $rc); uso la verificación básica propia."; fi
    fi

    msg_info "Verificación básica propia en '$d' (no muestra valores):"
    local -a excl=( --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=.venv
                    --exclude-dir=venv --exclude-dir=.cache --exclude='*.lock' --exclude='*.min.js' )
    local -a ci
    for p in "${SEC_PATTERNS[@]}"; do
        label="${p%%|*}"; rx="${p#*|}"; ci=()
        [[ "$label" == Credencial* ]] && ci=(-i)
        if [[ "$label" == Credencial* ]]; then
            out=$(grep -rInE "${ci[@]}" "${excl[@]}" -e "$rx" -- "$d" 2>/dev/null | grep -vE "$SEC_NOISE" | cut -d: -f1,2)
        else
            out=$(grep -rInE "${ci[@]}" "${excl[@]}" -e "$rx" -- "$d" 2>/dev/null | cut -d: -f1,2)
        fi
        [[ -z "$out" ]] && continue
        n=$(print -r -- "$out" | wc -l | tr -d ' '); total=$(( total + n ))
        print -r -- " ${C_RED}[!]${C_RST} $label: $n coincidencia(s)"
        print -r -- "$out" | head -n 12 | sed 's/^/       /'
        (( n > 12 )) && print "       ... y $(( n - 12 )) más"
    done

    # archivos sensibles versionados en git
    if git -C "$d" rev-parse --is-inside-work-tree &>/dev/null; then
        out=$(git -C "$d" ls-files 2>/dev/null \
              | grep -E '(^|/)(\.env(\..*)?|id_(rsa|dsa|ecdsa|ed25519)|.*\.(pem|key|p12|pfx)|.*\.tfstate(\..*)?|credentials(\..*)?|\.npmrc|\.pypirc)$' \
              | grep -vE '\.(example|sample|dist|template)$')
        if [[ -n "$out" ]]; then
            n=$(print -r -- "$out" | wc -l | tr -d ' '); total=$(( total + n ))
            print -r -- " ${C_RED}[!]${C_RST} Archivos sensibles VERSIONADOS en git: $n"
            print -r -- "$out" | head -n 12 | sed 's/^/       /'
        fi
    fi
    print ""
    if (( total == 0 )); then msg_ok "Sin hallazgos con las reglas básicas. (Instala gitleaks para analizar también el historial.)"
    else msg_warn "$total hallazgo(s). Si algo es real: rota la credencial y elimínala del historial (git filter-repo)."; fi
    log_action "DevSecOps: escaneo de secretos en $d ($total hallazgos)"
}

# ------------------------------------------------------------------------------
#  2) Seguridad de IaC (Terraform / Ansible)
# ------------------------------------------------------------------------------
sec_scan_rules() {   # sec_scan_rules <dir> "<include1 include2>" regla1 regla2 ...  (regla = "Etiqueta|regex")
    local d="$1" incs="$2" r out n total=0 inc; shift 2
    local -a incl=()
    for inc in ${=incs}; do incl+=( --include="$inc" ); done
    for r in "$@"; do
        out=$(grep -rInE "${incl[@]}" --exclude-dir=.terraform --exclude-dir=.git -e "${r#*|}" -- "$d" 2>/dev/null | cut -d: -f1,2)
        [[ -z "$out" ]] && continue
        n=$(print -r -- "$out" | wc -l | tr -d ' '); total=$(( total + n ))
        print -r -- " ${C_YEL}[!]${C_RST} ${r%%|*}: $n"
        print -r -- "$out" | head -n 6 | sed 's/^/       /'
    done
    SEC_TOTAL=$(( SEC_TOTAL + total ))
}

sec_iac() {
    local d def="${TF_DIR:-}" ran=0
    [[ -z "$def" && -n "$ANS_PLAY" ]] && def="${ANS_PLAY:h}"
    [[ -z "$def" ]] && def="$PWD"
    prompt_input "Carpeta del proyecto IaC [Default: $def]: " d
    d="${d:-$def}"
    [[ -d "$d" ]] || { msg_err "La carpeta '$d' no existe."; return 0; }
    SEC_TOTAL=0

    local has_tf has_yml
    has_tf=$(find "$d" -maxdepth 3 -name '*.tf' -not -path '*/.terraform/*' 2>/dev/null | head -n 1)
    has_yml=$(find "$d" -maxdepth 3 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | head -n 1)

    if [[ -n "$has_tf" ]]; then
        section "TERRAFORM"
        if command -v tfsec &>/dev/null; then ran=1; tfsec "$d" --no-colour 2>&1 | tail -n 40
        elif command -v checkov &>/dev/null; then ran=1; checkov -d "$d" --quiet --compact 2>&1 | tail -n 40
        elif command -v trivy &>/dev/null; then ran=1; trivy config "$d" 2>&1 | tail -n 40
        else
            msg_info "Sin tfsec/checkov/trivy: verificación básica propia."
            sec_scan_rules "$d" "*.tf" \
                "Ingreso abierto a todo Internet (0.0.0.0/0)|cidr_blocks[[:space:]]*=[[:space:]]*\[[^]]*\"0\.0\.0\.0/0\"" \
                "Recurso con acceso público|publicly_accessible[[:space:]]*=[[:space:]]*true" \
                "Cifrado deshabilitado|(encrypted|storage_encrypted|enable_encryption)[[:space:]]*=[[:space:]]*false" \
                "ACL pública|acl[[:space:]]*=[[:space:]]*\"public-read(-write)?\"" \
                "Secreto en texto plano|(password|secret|access_key|secret_key|token)[[:space:]]*=[[:space:]]*\"[^\"\$]{6,}\""
        fi
    fi
    if [[ -n "$has_yml" ]]; then
        section "ANSIBLE / YAML"
        if command -v ansible-lint &>/dev/null; then ran=1; ansible-lint "$d" 2>&1 | tail -n 40; fi
        if command -v yamllint &>/dev/null; then ran=1; yamllint -f parsable "$d" 2>&1 | head -n 25; fi
        if (( ! ran )); then
            msg_info "Sin ansible-lint/yamllint: verificación básica propia."
            sec_scan_rules "$d" "*.yml *.yaml" \
                "Validación de certificados desactivada|validate_certs:[[:space:]]*(no|false|False)" \
                "Errores ignorados (ignore_errors)|ignore_errors:[[:space:]]*(yes|true|True)" \
                "Permisos 0777|mode:[[:space:]]*['\"]?0?777" \
                "Contraseña en claro (¿falta ansible-vault?)|(password|passwd):[[:space:]]*['\"]?[A-Za-z0-9/+_.-]{6,}['\"]?[[:space:]]*$"
        fi
    fi
    [[ -z "$has_tf" && -z "$has_yml" ]] && { msg_warn "No encontré archivos .tf ni .yml en '$d'."; return 0; }
    print ""
    (( SEC_TOTAL == 0 )) && msg_ok "Sin hallazgos con las reglas básicas." || msg_warn "$SEC_TOTAL hallazgo(s) con las reglas básicas."
    log_action "DevSecOps: revisión IaC en $d"
}

# ------------------------------------------------------------------------------
#  3) Dockerfile
# ------------------------------------------------------------------------------
sec_dockerfile() {
    local -a found
    found=( ${(f)"$(auto_find 4 -type f '(' -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' ')' | sort)"} )
    found+=("[escribir ruta manualmente]")
    pick_from_list "Dockerfiles bajo $AUTO_BASE:" "${found[@]}" || return 0
    local f="$PICKED" issues=0 out
    [[ "$f" == "[escribir ruta manualmente]" ]] && prompt_input "Ruta del Dockerfile: " f
    [[ -f "$f" ]] || { msg_err "No existe '$f'."; return 0; }

    if command -v hadolint &>/dev/null; then
        msg_info "hadolint:"; hadolint "$f"; return 0
    fi
    msg_info "Verificación básica propia de '${f:t}' (instala hadolint para el análisis completo):"
    out=$(awk '{ if (tolower($1)=="from") { img=$2; if (img ~ /^--platform/) img=$3;
                   if (!(tolower(img) in st) && img!="scratch") {
                     if (img !~ /:/ && img !~ /@sha256/) print NR": imagen base sin tag fijo ("img")";
                     else if (img ~ /:latest$/) print NR": usa :latest ("img")" }
                   for (i=1;i<=NF;i++) if (tolower($i)=="as") st[tolower($(i+1))]=1 } }' "$f")
    [[ -n "$out" ]] && { print -r -- "$out" | sed 's/^/ [!] línea /'; issues=$(( issues + $(print -r -- "$out" | wc -l) )); }
    if ! grep -qiE '^USER[[:space:]]+[^[:space:]]+' "$f"; then print " [!] sin instrucción USER: el contenedor corre como root"; issues=$(( issues + 1 )); fi
    out=$(grep -nE '^ADD[[:space:]]' "$f" | cut -d: -f1 | tr '\n' ' ')
    [[ -n "$out" ]] && { print " [!] ADD en línea(s) $out: prefiere COPY salvo que necesites descomprimir/URL"; issues=$(( issues + 1 )); }
    out=$(grep -nE '(curl|wget)[^|]*\|[[:space:]]*(sudo )?(ba)?sh' "$f" | cut -d: -f1 | tr '\n' ' ')
    [[ -n "$out" ]] && { print " [!] 'curl | sh' en línea(s) $out: ejecuta código remoto sin verificar"; issues=$(( issues + 1 )); }
    out=$(grep -niE '^(ENV|ARG)[[:space:]]+[A-Z_]*(PASSWORD|SECRET|TOKEN|KEY)[A-Z_]*[= ]' "$f" | cut -d: -f1 | tr '\n' ' ')
    [[ -n "$out" ]] && { print " [!] posible secreto en ENV/ARG (línea(s) $out): queda en las capas de la imagen"; issues=$(( issues + 1 )); }
    out=$(grep -nE 'chmod[[:space:]]+(-R[[:space:]]+)?777' "$f" | cut -d: -f1 | tr '\n' ' ')
    [[ -n "$out" ]] && { print " [!] chmod 777 en línea(s) $out"; issues=$(( issues + 1 )); }
    grep -qiE '^HEALTHCHECK' "$f" || print " [i] sin HEALTHCHECK (recomendado en producción)"
    print ""
    (( issues == 0 )) && msg_ok "Sin hallazgos con las reglas básicas." || msg_warn "$issues hallazgo(s)."
    log_action "DevSecOps: Dockerfile ${f:t} ($issues hallazgos)"
}

# ------------------------------------------------------------------------------
#  4) Contenedores en ejecución: postura de seguridad
# ------------------------------------------------------------------------------
sec_containers() {
    command -v docker &>/dev/null || { msg_warn "docker no está instalado."; return 0; }
    sec_dk
    local -a names
    names=( ${(f)"$("${SEC_DOCKER[@]}" ps --format '{{.Names}}' 2>/dev/null)"} )
    (( ${#names} )) || { msg_info "No hay contenedores en ejecución (o sin permisos para verlos)."; return 0; }
    local n priv user net mounts caps flags bad=0
    printf " %-22s %s\n" "CONTENEDOR" "HALLAZGOS"
    for n in "${names[@]}"; do
        priv=$("${SEC_DOCKER[@]}" inspect -f '{{.HostConfig.Privileged}}' "$n" 2>/dev/null)
        user=$("${SEC_DOCKER[@]}" inspect -f '{{.Config.User}}' "$n" 2>/dev/null)
        net=$("${SEC_DOCKER[@]}" inspect -f '{{.HostConfig.NetworkMode}}' "$n" 2>/dev/null)
        mounts=$("${SEC_DOCKER[@]}" inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$n" 2>/dev/null)
        caps=$("${SEC_DOCKER[@]}" inspect -f '{{.HostConfig.CapAdd}}' "$n" 2>/dev/null)
        flags=""
        [[ "$priv" == true ]] && flags+=" PRIVILEGED"
        [[ -z "$user" || "$user" == root || "$user" == 0 ]] && flags+=" corre-como-root"
        [[ "$net" == host ]] && flags+=" red-host"
        [[ "$mounts" == *docker.sock* ]] && flags+=" monta-docker.sock"
        [[ "$mounts" == "/ "* || "$mounts" == *" / "* ]] && flags+=" monta-/"
        [[ -n "$caps" && "$caps" != "[]" && "$caps" != "<no value>" ]] && flags+=" cap-add$caps"
        if [[ -n "$flags" ]]; then printf " %-22s %s%s%s\n" "$n" "$C_YEL" "${flags# }" "$C_RST"; bad=$(( bad + 1 ))
        else printf " %-22s %s\n" "$n" "${C_GRN}sin hallazgos${C_RST}"; fi
    done
    print ""
    msg_info "Criterios: privilegiado, root, red del host, docker.sock montado, capacidades añadidas."
    (( bad )) && msg_warn "$bad contenedor(es) con hallazgos." || msg_ok "Ningún contenedor con hallazgos."
    log_action "DevSecOps: auditoría de contenedores ($bad con hallazgos)"
}

# ------------------------------------------------------------------------------
#  5) Vulnerabilidades con trivy
# ------------------------------------------------------------------------------
sec_trivy() {
    if ! command -v trivy &>/dev/null; then
        msg_warn "trivy no está instalado."
        msg_info "Instalación: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
        return 0
    fi
    local choice d
    print " 1) Imagen Docker local   2) Carpeta / proyecto (fs)   3) Configuración IaC (Terraform, K8s, Dockerfile)"
    prompt_input "Elige [1-3]: " choice
    case "$choice" in
        1) sec_dk
           local -a imgs
           imgs=( ${(f)"$("${SEC_DOCKER[@]}" images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -v '<none>')"} )
           pick_from_list "Imágenes locales:" "${imgs[@]}" || return 0
           trivy image --severity HIGH,CRITICAL "$PICKED" ;;
        2) prompt_input "Carpeta [Default: $REPO_DIR]: " d; d="${d:-$REPO_DIR}"
           [[ -d "$d" ]] || { msg_err "No existe '$d'."; return 0; }
           trivy fs --severity HIGH,CRITICAL "$d" ;;
        3) prompt_input "Carpeta [Default: ${TF_DIR:-$PWD}]: " d; d="${d:-${TF_DIR:-$PWD}}"
           [[ -d "$d" ]] || { msg_err "No existe '$d'."; return 0; }
           trivy config "$d" ;;
        *) msg_warn "Opción no válida."; return 0 ;;
    esac
    log_action "DevSecOps: trivy ($choice)"
}

# ------------------------------------------------------------------------------
#  6) Host: SSH, permisos y parches
# ------------------------------------------------------------------------------
sec_ssh_row() {   # parámetro actual esperado ok(0/1)
    local mark="${C_GRN}OK${C_RST}"; (( $4 )) || mark="${C_RED}REVISAR${C_RST}"
    printf " %-24s %-18s %-22s %s\n" "$1" "$2" "$3" "$mark"
}

sec_ssh() {
    local cfg v ok
    cfg=$("${SUDO[@]}" sshd -T 2>/dev/null)
    if [[ -z "$cfg" ]]; then
        msg_warn "No pude leer la configuración de sshd (¿sshd instalado? 'sshd -T' requiere root)."
    else
        sshd_val() { print -r -- "$cfg" | awk -v k="$1" '$1==k{ $1=""; sub(/^ /,""); print; exit}'; }
        section "CONFIGURACIÓN DE sshd"
        printf " %-24s %-18s %-22s %s\n" "Parámetro" "Actual" "Esperado" "Estado"
        v=$(sshd_val permitrootlogin);        [[ "$v" == (no|prohibit-password|without-password) ]] && ok=1 || ok=0
        sec_ssh_row PermitRootLogin "$v" "no / prohibit-password" $ok
        v=$(sshd_val passwordauthentication); [[ "$v" == no ]] && ok=1 || ok=0
        sec_ssh_row PasswordAuthentication "$v" "no (solo claves)" $ok
        v=$(sshd_val pubkeyauthentication);   [[ "$v" == yes ]] && ok=1 || ok=0
        sec_ssh_row PubkeyAuthentication "$v" "yes" $ok
        v=$(sshd_val permitemptypasswords);   [[ "$v" == no ]] && ok=1 || ok=0
        sec_ssh_row PermitEmptyPasswords "$v" "no" $ok
        v=$(sshd_val x11forwarding);          [[ "$v" == no ]] && ok=1 || ok=0
        sec_ssh_row X11Forwarding "$v" "no" $ok
        v=$(sshd_val maxauthtries);           [[ "$v" == <-> && $v -le 4 ]] && ok=1 || ok=0
        sec_ssh_row MaxAuthTries "$v" "<= 4" $ok
        v=$(sshd_val logingracetime);         [[ "$v" == <-> && $v -le 60 && $v -gt 0 ]] && ok=1 || ok=0
        sec_ssh_row LoginGraceTime "$v" "<= 60 s" $ok
        v=$(sshd_val port);                   sec_ssh_row Port "$v" "(informativo)" 1
    fi

    section "TU DIRECTORIO ~/.ssh"
    local d="$HOME/.ssh" f perm age
    if [[ ! -d "$d" ]]; then print " (no existe ~/.ssh)"; else
        perm=$(stat -c %a "$d"); [[ "$perm" == 700 ]] && print " ${C_GRN}OK${C_RST} ~/.ssh permisos $perm" || print " ${C_RED}REVISAR${C_RST} ~/.ssh permisos $perm (debería ser 700)"
        for f in "$d"/id_*(N) ; do
            [[ "$f" == *.pub ]] && continue
            perm=$(stat -c %a "$f")
            [[ "$perm" == (600|400) ]] && print " ${C_GRN}OK${C_RST} ${f:t} permisos $perm" || print " ${C_RED}REVISAR${C_RST} ${f:t} permisos $perm (debería ser 600)"
            age=$(( ( $(date +%s) - $(stat -c %Y "$f") ) / 86400 ))
            (( age > 365 )) && print " ${C_YEL}[!]${C_RST} ${f:t}: clave de $age días; considera rotarla"
            ssh-keygen -l -f "$f" 2>/dev/null | awk '{print "     " $1 " bits, tipo " $NF}'
        done
        [[ -f "$d/authorized_keys" ]] && print " [i] authorized_keys: $(grep -c . "$d/authorized_keys") clave(s) autorizadas"
    fi
    log_action "DevSecOps: auditoría SSH"
}

sec_perms() {
    local f perm out
    section "ARCHIVOS CRÍTICOS"
    for f in /etc/shadow /etc/passwd /etc/sudoers /etc/ssh/sshd_config; do
        [[ -e "$f" ]] || continue
        perm=$(stat -c '%a %U:%G' "$f"); print " $f  $perm"
    done
    print " (esperado: shadow 0/400/600/640 root; passwd 644; sudoers 440; sshd_config 600/644)"
    section "ESCRIBIBLES POR TODOS EN /etc"
    out=$("${SUDO[@]}" find /etc -xdev -type f -perm -0002 2>/dev/null | head -n 15)
    [[ -n "$out" ]] && print -r -- "$out" | sed 's/^/ [!] /' || print " ${C_GRN}OK${C_RST} ninguno"
    section "SUID / SGID (revisa que todos te suenen)"
    out=$(timeout 40 "${SUDO[@]}" find / -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | sort)
    print -r -- "  total: $(print -r -- "$out" | grep -c .)"
    print -r -- "$out" | head -n 25 | sed 's/^/  /'
    section "ARCHIVOS SIN DUEÑO / GRUPO"
    out=$(timeout 40 "${SUDO[@]}" find / -xdev \( -nouser -o -nogroup \) -print 2>/dev/null | head -n 10)
    [[ -n "$out" ]] && print -r -- "$out" | sed 's/^/ [!] /' || print " ${C_GRN}OK${C_RST} ninguno"
    log_action "DevSecOps: auditoría de permisos"
}

sec_patches() {
    local running latest
    running=$(uname -r)
    case "$PKG_MGR" in
        apt)
            msg_info "Actualizaciones de SEGURIDAD pendientes (simulación):"
            apt-get -s upgrade 2>/dev/null | awk '/^Inst/ && /[Ss]ecurity/{print "   " $2 "  " $3 " -> " $4}' | head -n 30
            latest=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -n 1)
            [[ -f /var/run/reboot-required ]] && msg_warn "Reinicio requerido (reboot-required)." ;;
        dnf|yum)
            msg_info "Avisos de seguridad pendientes:"
            "$PKG_MGR" -q updateinfo list security 2>/dev/null | head -n 30
            msg_info "Resumen:"; "$PKG_MGR" -q updateinfo summary 2>/dev/null | head -n 10
            latest=$(rpm -q kernel --last 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/^kernel-//')
            if command -v needs-restarting &>/dev/null; then
                needs-restarting -r 2>&1 | tail -n 3
            else msg_info "needs-restarting no instalado (paquete dnf-utils / yum-utils)."; fi ;;
        *) msg_info "El detalle de avisos de seguridad no está implementado para '$PKG_MGR'." ;;
    esac
    print ""
    kv "Kernel en uso" "$running"
    kv "Kernel instalado" "${latest:-N/D}"
    if [[ -n "$latest" && "$latest" != "$running"* && "$running" != "$latest"* ]]; then
        msg_warn "El kernel instalado más reciente no es el que está en ejecución: falta reiniciar."
    fi
    log_action "DevSecOps: parches de seguridad"
}

menu_secops() {
    MENU_HOOK=sec_panel
    run_menu "DEVSECOPS - SEGURIDAD EN CÓDIGO, INFRAESTRUCTURA Y HOST" \
        "#CÓDIGO E IAC" \
        "Secretos en el repo/carpeta (gitleaks o reglas propias)|sec_secrets" \
        "Seguridad de Terraform y Ansible (tfsec/checkov/ansible-lint)|sec_iac" \
        "Auditar un Dockerfile (hadolint o reglas propias)|sec_dockerfile" \
        "#CONTENEDORES E IMÁGENES" \
        "Postura de seguridad de los contenedores en ejecución|sec_containers" \
        "Vulnerabilidades de imágenes / proyectos / IaC (trivy)|sec_trivy" \
        "#HOST Y ACCESO" \
        "Auditoría de SSH (sshd -T y ~/.ssh)|sec_ssh" \
        "Permisos, SUID/SGID y archivos huérfanos|sec_perms" \
        "Parches de seguridad pendientes y kernel|sec_patches" \
        "SELinux, firewall, accesos y usuarios privilegiados|menu_security|nopause"
}
