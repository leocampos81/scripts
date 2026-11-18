#!/usr/bin/env zsh
# Módulo: Herramientas Locales (Tus scripts)

tools_espacio() {
    if [[ -x "$SCRIPT_DIR/modules/espacio.sh" ]]; then
        run_interruptible "$SCRIPT_DIR/modules/espacio.sh"
    else
        msg_err "No se encuentra modules/espacio.sh"
    fi
}

tools_comprimir() {
    if [[ -x "$SCRIPT_DIR/modules/comprimir.sh" ]]; then
        run_interruptible "$SCRIPT_DIR/modules/comprimir.sh"
    else
        msg_err "No se encuentra modules/comprimir.sh"
    fi
}

tools_swap_watch() {
    if [[ -x "$SCRIPT_DIR/modules/swap-watch.sh" ]]; then
        msg_info "Iniciando monitor de Swap (Ctrl+C para detener)..."
        sleep 1
        run_interruptible "$SCRIPT_DIR/modules/swap-watch.sh"
    else
        msg_err "No se encuentra modules/swap-watch.sh"
    fi
}

tools_segundos() {
    if [[ -x "$SCRIPT_DIR/modules/segundos.sh" ]]; then
        run_interruptible "$SCRIPT_DIR/modules/segundos.sh"
    else
        msg_err "No se encuentra modules/segundos.sh"
    fi
}

tools_diff_time() {
    if [[ -x "$SCRIPT_DIR/modules/diff_time.sh" ]]; then
        run_interruptible "$SCRIPT_DIR/modules/diff_time.sh"
    else
        msg_err "No se encuentra modules/diff_time.sh"
    fi
}

# El update.sh ya lo tenemos en Sysadmin, así que lo quitamos de aquí para no duplicar
tools_menu() {
    run_menu "HERRAMIENTAS LOCALES (TUS SCRIPTS)" \
        "Analizar y comprimir espacio (espacio.sh)|tools_espacio" \
        "Comprimir/Descomprimir archivos (comprimir.sh)|tools_comprimir" \
        "Monitor interactivo de RAM/Swap (swap-watch.sh)|tools_swap_watch" \
        "Convertidor de segundos (segundos.sh)|tools_segundos" \
        "Diferencia de tiempo (diff_time.sh)|tools_diff_time"
}
