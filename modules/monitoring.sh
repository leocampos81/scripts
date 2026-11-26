#!/usr/bin/env zsh
# Módulo: Monitoreo y Observabilidad

# Detección de herramientas de monitoreo (Docker o binario local)
mon_detect() {
    section "STACK DE MONITOREO DETECTADO"
    local found=0

    # Prometheus
    if command -v prometheus &>/dev/null || docker ps --format '{{.Names}}' 2>/dev/null | grep -qi prometheus; then
        print " [ OK ] Prometheus (métricas)"
        found=1
    fi
    # Grafana
    if command -v grafana-server &>/dev/null || docker ps --format '{{.Names}}' 2>/dev/null | grep -qi grafana; then
        print " [ OK ] Grafana (dashboards)"
        found=1
    fi
    # Node Exporter
    if command -v node_exporter &>/dev/null || docker ps --format '{{.Names}}' 2>/dev/null | grep -qi node-exporter; then
        print " [ OK ] Node Exporter (métricas de sistema)"
        found=1
    fi
    # Loki
    if command -v loki &>/dev/null || docker ps --format '{{.Names}}' 2>/dev/null | grep -qi loki; then
        print " [ OK ] Loki (logs)"
        found=1
    fi
    # cAdvisor
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi cadvisor; then
        print " [ OK ] cAdvisor (métricas de contenedores)"
        found=1
    fi
    # Alloy (agente de Grafana)
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi alloy; then
        print " [ OK ] Alloy (agente de telemetría)"
        found=1
    fi

    if (( found == 0 )); then
        msg_warn "No se detectaron herramientas de monitoreo."
    fi
}

mon_docker_status() {
    msg_info "Contenedores relacionados con monitoreo:"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -iE "prometheus|grafana|loki|node-exporter|cadvisor|alloy" || msg_warn "No hay contenedores de monitoreo."
}

mon_prometheus() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi prometheus; then
        msg_info "Prometheus está corriendo en Docker."
        # Podríamos hacer un curl a la API de Prometheus para ver targets
        local pport=$(docker port prometheus 2>/dev/null | grep -o '9090' | head -1)
        if [[ -n "$pport" ]]; then
            msg_info "Intentando consultar targets en http://localhost:$pport/api/v1/targets..."
            curl -s "http://localhost:$pport/api/v1/targets" | jq -r '.data.activeTargets[] | "\(.labels.job) - \(.health)"' 2>/dev/null | head -n 10
        fi
    elif command -v prometheus &>/dev/null; then
        msg_info "Prometheus está instalado localmente."
    else
        msg_warn "Prometheus no detectado."
    fi
}

mon_grafana() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi grafana; then
        msg_info "Grafana está corriendo en Docker."
        msg_info "Accede a http://localhost:3000 (usuario: admin, contraseña por defecto: admin)."
    elif command -v grafana-server &>/dev/null; then
        msg_info "Grafana está instalado localmente."
    else
        msg_warn "Grafana no detectado."
    fi
}

mon_node_exporter() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi node-exporter; then
        msg_info "Node Exporter está corriendo en Docker."
        msg_info "Puedes ver las métricas en http://localhost:9100/metrics (si está mapeado)."
    elif command -v node_exporter &>/dev/null; then
        msg_info "Node Exporter está instalado localmente."
    else
        msg_warn "Node Exporter no detectado."
    fi
}

menu_monitoring() {
    run_menu "MONITOREO Y OBSERVABILIDAD" \
        "Detectar stack de monitoreo (Prometheus, Grafana, etc.)|mon_detect" \
        "#ESTADO DE CONTENEDORES" \
        "Ver contenedores de monitoreo (docker ps)|mon_docker_status" \
        "#HERRAMIENTAS ESPECÍFICAS" \
        "Estado de Prometheus|mon_prometheus" \
        "Estado de Grafana|mon_grafana" \
        "Estado de Node Exporter|mon_node_exporter"
}
