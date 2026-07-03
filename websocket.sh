#!/bin/bash
# ==========================================
#   NETSIMON 4.0 - WEBSOCKET & SOCKS MANAGER
# ==========================================

P=$'\033[1;35m'; G=$'\033[1;32m'; R=$'\033[1;31m'; Y=$'\033[1;33m'
W=$'\033[1;37m'; C=$'\033[1;36m'; B=$'\033[1;34m'; NC=$'\033[0m'
T=$'\033[38;2;0;255;239m'

BASE="/etc/painel"
PROXY_PY="$BASE/proxy.py"

check_proto() {
    local porta=$1
    local pid
    pid=$(lsof -t -i :"$porta" -sTCP:LISTEN 2>/dev/null | head -n1)
    if [ -z "$pid" ]; then echo -e "${R}OFF${NC}"; return; fi
    local cmd; cmd=$(ps -fp "$pid" -o args= 2>/dev/null)
    if [[ "$cmd" == *"proxy.py"* ]]; then
        echo -e "${G}WS/PROXY ● ${NC}"
    else
        echo -e "${Y}OUTRO${NC}"
    fi
}

stop_port() {
    local pid; pid=$(lsof -t -i :"$1" -sTCP:LISTEN 2>/dev/null)
    [ -z "$pid" ] && return 1
    kill -9 $pid 2>/dev/null; sleep 1; return 0
}

start_proxy() {
    local porta=$1 nome=$2
    stop_port "$porta"
    screen -dmS "$nome" python3 "$PROXY_PY" "$porta"
    sleep 1
    local pid; pid=$(lsof -t -i :"$porta" -sTCP:LISTEN 2>/dev/null)
    [ -n "$pid" ] && echo -e "${G}[OK] Proxy na porta $porta iniciado!${NC}" || \
        echo -e "${R}[ERRO] Falha na porta $porta. proxy.py em $BASE?${NC}"
}

while true; do
    clear
    echo -e "${P}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${P}║${W}             🌐 NETSIMON 4.0 — WEBSOCKET MANAGER              ${P}║${NC}"
    echo -e "${P}╠══════════════════════════════════════════════════════════════╣${NC}"
    printf "  ${W}PORTA  80 : %-30b${NC}\n" "$(check_proto 80)"
    printf "  ${W}PORTA 8080: %-30b${NC}\n" "$(check_proto 8080)"
    echo -e "${P}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${P}║${T} 1)${NC} Iniciar WebSocket Proxy ${C}(Porta 80)${NC}"
    echo -e "${P}║${T} 2)${NC} Iniciar WebSocket Proxy ${C}(Porta 8080)${NC}"
    echo -e "${P}║${T} 3)${NC} Parar Porta 80"
    echo -e "${P}║${T} 4)${NC} Parar Porta 8080"
    echo -e "${P}║${T} 5)${NC} Reiniciar ambos (80 + 8080)"
    echo -e "${P}║${T} 6)${NC} Relatório de portas"
    echo -e "${P}║${R} 0)${NC} Voltar"
    echo -e "${P}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -ne "${Y} Escolha: ${NC}"; read opt

    case $opt in
        1) start_proxy 80 "ws80"; sleep 2 ;;
        2) start_proxy 8080 "ws8080"; sleep 2 ;;
        3) stop_port 80 && echo -e "${G}Porta 80 encerrada.${NC}" || echo -e "${Y}Nada rodando na 80.${NC}"; sleep 2 ;;
        4) stop_port 8080 && echo -e "${G}Porta 8080 encerrada.${NC}" || echo -e "${Y}Nada rodando na 8080.${NC}"; sleep 2 ;;
        5) stop_port 80; stop_port 8080; start_proxy 80 "ws80"; start_proxy 8080 "ws8080"; sleep 2 ;;
        6)
            clear
            echo -e "${P}══ PORTAS LISTEN ══════════════════════════════${NC}"
            lsof -i :80,8080 -sTCP:LISTEN 2>/dev/null
            echo -e "${P}══ CONEXÕES ATIVAS (top 20) ═══════════════════${NC}"
            ss -tnp 2>/dev/null | grep -E ":80 |:8080 " | grep ESTAB | head -20
            read -p "ENTER..." ;;
        0) exit 0 ;;
        *) echo -e "${R}Inválido!${NC}"; sleep 1 ;;
    esac
done
