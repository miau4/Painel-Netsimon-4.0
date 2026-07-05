#!/bin/bash
# ==========================================
#   NETSIMON 4.0 - INSTALADOR (OTIMIZADO)
#   VERSÃO CORRIGIDA PARA COMPATIBILIDADE COM DEVICE CHECK
#   [PATCH] Corrigido travamento do apt em prompts interativos
#           (iptables-persistent pedindo confirmação via whiptail)
# ==========================================

# [PATCH] Garante que NENHUM apt/dpkg abra prompt interativo (whiptail, debconf, etc.)
export DEBIAN_FRONTEND=noninteractive

C=$'\033[1;36m'; G=$'\033[1;32m'; R=$'\033[1;31m'; Y=$'\033[1;33m'; W=$'\033[1;37m'; NC=$'\033[0m'
REPO="https://raw.githubusercontent.com/miau4/Painel-Netsimon-4.0/main"
BASE="/etc/painel"
XRAY_CONF="/usr/local/etc/xray/config.json"
SSL_DIR="/etc/xray-manager/ssl"

clear
echo -e "${C}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║${W}              🚀 INSTALADOR NETSIMON 4.0                       ${C}║${NC}"
echo -e "${C}╚══════════════════════════════════════════════════════════════╝${NC}"

# 1. Timezone e Firewall
echo -ne "${W}[+] Sincronizando relógio e liberando firewall... ${NC}"
timedatectl set-timezone America/Sao_Paulo
iptables -F && iptables -X
iptables -t nat -F && iptables -t nat -X
iptables -t mangle -F && iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
systemctl stop apache2 oracle-cloud-agent oracle-cloud-agent-updater &>/dev/null
systemctl disable apache2 oracle-cloud-agent oracle-cloud-agent-updater &>/dev/null
apt purge apache2 -y &>/dev/null
echo -e "${G}OK${NC}"

# 2. Dependências
echo -ne "${W}[+] Instalando dependências... ${NC}"

# [PATCH] Pré-configura o iptables-persistent para salvar as regras atuais
# (IPv4 e IPv6) sem exibir a tela de confirmação do whiptail, que era o que
# travava a instalação esperando um Enter que nunca chegava.
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections

apt update -y &>/dev/null
apt install -y wget curl jq python3 python3-pip dos2unix nginx \
    stunnel4 net-tools lsof iptables-persistent screen at &>/dev/null
systemctl enable --now atd &>/dev/null
echo -e "${G}OK${NC}"

# 3. Nginx na porta 81 (COM SUPORTE A PHP PARA DEVICE CHECK)
echo -ne "${W}[+] Configurando Nginx (porta 81 com PHP)... ${NC}"
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/netsimon_web <<'EOF'
server {
    listen 81;
    server_name _;

    location / {
        root /var/www/html;
        index index.html;
    }

    location ~ \.php$ {
        root /var/www/html;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
ln -sf /etc/nginx/sites-available/netsimon_web /etc/nginx/sites-enabled/
systemctl restart nginx &>/dev/null
echo -e "${G}OK${NC}"

# 3.1 Instalar e habilitar PHP-FPM (NECESSÁRIO PARA DEVICE CHECK)
echo -ne "${W}[+] Instalando PHP 8.1 FPM... ${NC}"
apt install -y php8.1-cli php8.1-fpm php8.1-sqlite3 php8.1-curl &>/dev/null
systemctl enable php8.1-fpm &>/dev/null
systemctl start php8.1-fpm &>/dev/null
echo -e "${G}OK${NC}"

# 4. Stunnel
echo -ne "${W}[+] Configurando Stunnel (porta 8443)... ${NC}"
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -sha256 \
    -subj "/CN=Netsimon" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem &>/dev/null
cat > /etc/stunnel/stunnel.conf <<'EOF'
pid = /var/run/stunnel4.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssh]
accept = 8443
connect = 127.0.0.1:22
EOF
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4
systemctl restart stunnel4 &>/dev/null
echo -e "${G}OK${NC}"

# 5. Estrutura de diretórios
echo -ne "${W}[+] Criando estrutura de diretórios... ${NC}"
mkdir -p "$BASE" "$SSL_DIR" "/etc/slowdns" "/var/log/xray" "/usr/local/etc/xray" "/etc/xray-manager"
touch /var/log/xray/access.log /var/log/xray/error.log
chmod -R 777 /var/log/xray
touch "$BASE/usuarios.db"
touch "/etc/xray-manager/blocked.db"

# [PATCH] O painel Atlas detecta usuários "online" via uma sonda SSH própria
# (onlines.php/updateon.php) que lê o log em /var/log/v2ray/access.log — um
# caminho legado de quando o painel usava v2ray em vez de Xray. Sem isso, o
# Atlas nunca encontra o log e ninguém aparece online, mesmo com tudo certo.
# Criamos um symlink apontando pro log real do Xray. Só cria se não houver
# nada real nesse caminho ainda (evita sobrescrever uma instalação antiga
# de v2ray, se existir).
if [ ! -e "/var/log/v2ray" ]; then
    ln -s /var/log/xray /var/log/v2ray
fi
echo -e "${G}OK${NC}"

# 6. Download dos módulos
arquivos=(
    "menu.sh" "adduser.sh" "addtest.sh" "deluser.sh"
    "online.sh" "limit.sh" "unblock.sh" "websocket.sh"
    "xray.sh" "slowdns-server.sh" "monitor.sh" "proxy.py"
    "boot_check.sh" "repair.sh" "checkuser.py" "checkuser.sh"
    "atlas.sh" "xray_lib.sh"
)

echo -e "${Y}[!] Baixando módulos Netsimon 4.0...${NC}"
for file in "${arquivos[@]}"; do
    printf "${W}  -> %-20s ${NC}" "$file"
    wget -q -O "$BASE/$file" "$REPO/$file"
    if [ -s "$BASE/$file" ]; then
        chmod +x "$BASE/$file"
        dos2unix "$BASE/$file" &>/dev/null
        echo -e "${G}[OK]${NC}"
    else
        echo -e "${R}[FALHA]${NC}"
    fi
done

# 7. Xray
echo -ne "${W}[+] Instalando Xray... ${NC}"
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) &>/dev/null
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray 2>/dev/null

# [PATCH] O instalador oficial do Xray, na linha acima, sobrescreve o dono/permissão
# de /var/log/xray para nobody:nogroup (0600). Como o xray.service deste script roda
# com User=root e CapabilityBoundingSet restrito (sem CAP_DAC_OVERRIDE), o processo
# não consegue abrir esses arquivos mesmo sendo root, e falha com "permission denied".
# Reaplica a permissão aberta DEPOIS do instalador oficial, garantindo que fique valendo.
chown -R root:root /var/log/xray
chmod -R 777 /var/log/xray

# Gera SSL
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -subj "/C=BR/ST=SP/L=SP/O=NetSimon/CN=www.tim.com.br" \
    -keyout "$SSL_DIR/privkey.pem" -out "$SSL_DIR/fullchain.pem" &>/dev/null
chmod 644 "$SSL_DIR/privkey.pem" "$SSL_DIR/fullchain.pem"

cat > "$XRAY_CONF" <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "api": {
    "services": ["HandlerService","LoggerService","StatsService"],
    "tag": "api"
  },
  "stats": {},
  "policy": {
    "levels": { "0": { "statsUserDownlink": true, "statsUserOnline": true, "statsUserUplink": true } },
    "system": { "statsInboundDownlink": true, "statsInboundUplink": true }
  },
  "inbounds": [
    {
      "tag": "api",
      "port": 2000,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" },
      "listen": "127.0.0.1"
    },
    {
      "tag": "inbound-netsimon",
      "port": 443,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "xhttpSettings": {
          "path": "/",
          "host": "",
          "mode": "",
          "noSSEHeader": false,
          "scMaxBufferedPosts": 30,
          "scMaxEachPostBytes": "1000000",
          "scStreamUpServerSecs": "20-80",
          "xPaddingBytes": "100-1000"
        },
        "tlsSettings": {
          "certificates": [{ "certificateFile": "$SSL_DIR/fullchain.pem", "keyFile": "$SSL_DIR/privkey.pem" }],
          "alpn": ["http/1.1"]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": { "domainStrategy": "UseIP" }, "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "inboundTag": ["api"], "outboundTag": "api", "type": "field" },
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" },
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" }
    ]
  }
}
EOF
echo -e "${G}OK${NC}"

# 7.1 Otimização de Kernel (NETSIMON)
echo -ne "${W}[+] Aplicando Otimizações de Kernel... ${NC}"
sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
cat <<EOF >> /etc/sysctl.conf
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_fin_timeout=15
EOF
sysctl -p &>/dev/null
echo -e "${G}OK${NC}"

# 8. Systemd do Xray
echo -ne "${W}[+] Configurando serviço Xray... ${NC}"
cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service - Netsimon 4.0
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable xray &>/dev/null
systemctl start xray
echo -e "${G}OK${NC}"

# 8.1 Resync de usuários já existentes (reinstalação)
# O config.json acima sempre nasce com "clients": [] zerado. Se
# $BASE/usuarios.db já existir de uma instalação anterior (o "touch"
# do passo 5 não apaga o arquivo se ele já existir), esses usuários
# ficariam "fantasmas": presentes no painel, mas ausentes do Xray.
# Antes, quem recolocava esses usuários no Xray era o atlas_sync
# (cron de 1 em 1 min) — só que ele rodava em paralelo com qualquer
# criação manual de usuário logo após a instalação, e essa corrida
# era exatamente a causa do bug "User X already exists" que derrubava
# o Xray. Aqui fazemos esse resync uma única vez, de forma síncrona e
# serializada (via xray_add_client_safe, com lock), antes de qualquer
# cron ou uso manual do painel começar.
if [ -s "$BASE/usuarios.db" ] && [ -f "$BASE/xray_lib.sh" ]; then
    echo -ne "${W}[+] Ressincronizando usuários existentes no Xray... ${NC}"
    source "$BASE/xray_lib.sh"
    resync_count=0
    while IFS='|' read -r ruser ruuid _ _ _; do
        [ -z "$ruser" ] && continue
        [ -z "$ruuid" ] && continue
        xray_add_client_safe "$ruser" "$ruuid" 443
        [ $? -eq 0 ] && ((resync_count++))
    done < "$BASE/usuarios.db"
    [ "$resync_count" -gt 0 ] && systemctl restart xray &>/dev/null
    echo -e "${G}OK${NC} ($resync_count usuário(s) restaurado(s))"
fi

# 9. Watchdog do Xray
echo "* * * * * root if ! systemctl is-active --quiet xray; then systemctl restart xray; fi" \
    > /etc/cron.d/xray_watchdog

# 10. Atalhos, limiter e crontab
echo -ne "${W}[+] Ativando Limiter e atalhos... ${NC}"
echo "bash $BASE/menu.sh" > /usr/local/bin/menu
chmod +x /usr/local/bin/menu
screen -dmS limitador bash "$BASE/limit.sh"
(crontab -l 2>/dev/null | grep -v "limit.sh"; echo "@reboot screen -dmS limitador bash $BASE/limit.sh") | crontab -
(crontab -l 2>/dev/null | grep -v "boot_check.sh"; echo "@reboot bash $BASE/boot_check.sh") | crontab -

# 10.1 Sincronização Atlas -> Local INDEPENDENTE do limiter.
#      Antes o sync rodava dentro do loop do limit.sh: se o limiter
#      fosse desligado (ex.: instabilidade no Xray), o sync parava
#      junto, mesmo sendo duas coisas sem relação entre si. Agora é
#      um cron próprio, com flock pra nunca rodar duas instâncias
#      sobrepostas (a chamada ao Atlas tem timeout de 10s, então pode
#      acumular se a API estiver lenta). Funciona com o limiter ligado,
#      desligado, ou nem instalado.
cat > "$BASE/atlas_sync_cron.sh" <<'EOF'
#!/bin/bash
source /etc/painel/atlas.sh
atlas_sync_users >> /var/log/netsimon_limit.log 2>&1
EOF
chmod +x "$BASE/atlas_sync_cron.sh"
echo "* * * * * root flock -n /tmp/atlas_sync.lock $BASE/atlas_sync_cron.sh" \
    > /etc/cron.d/atlas_sync

netfilter-persistent save &>/dev/null
echo -e "${G}OK${NC}"

# 11. Configuração do Atlas API
echo ""
echo -e "${Y}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${Y}║${W}            🌐 CONFIGURAÇÃO DO ATLAS API                       ${Y}║${NC}"
echo -e "${Y}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "${W}Para integrar com o painel Atlas em painel.netsimon.fun,${NC}"
echo -e "${W}informe sua API Key. Você pode configurar depois com a opção 20 do menu.${NC}"
echo -ne "${C}Cole sua API Key (ou Enter para pular): ${NC}"
read atlas_key
if [ -n "$atlas_key" ]; then
    echo "$atlas_key" > "$BASE/atlas.key"
    chmod 600 "$BASE/atlas.key"
    echo -e "${G}✅ Atlas configurado!${NC}"
else
    echo -e "${Y}⚠ Atlas não configurado. Use a opção 20 do menu para configurar.${NC}"
fi

echo ""

# Fix: mascara swap órfão para evitar filesystem em read-only no boot
if [ ! -f /swapfile ]; then
    systemctl mask swapfile.swap &>/dev/null
fi

# 12. Preservar configurações do Device Check (se existirem)
echo -ne "${W}[+] Verificando integridade do Device Check... ${NC}"
if [ -f "/var/www/html/device_check.php" ] && [ -f "/var/www/html/netsimon_devices.db" ]; then
    # Fazer backup
    cp /var/www/html/device_check.php /var/www/html/device_check.php.bak
    cp /var/www/html/netsimon_devices.db /var/www/html/netsimon_devices.db.bak
    echo -e "${G}OK${NC} (Sistema de bloqueio preservado)"
else
    echo -e "${Y}PULADO${NC} (Device Check não instalado)"
fi

echo ""
echo -e "${G}✅ INSTALAÇÃO NETSIMON 4.0 CONCLUÍDA!${NC}"
echo -e "${W}Portas: ${C}443 (Xray), 80 (WS), 81 (Web com PHP), 8443 (SSL), 2000 (API interna)${NC}"
echo -e "${W}Device Check: ${C}http://2.netsimon.fun:81/device_check.php${NC}"
echo -e "${W}Digite ${C}menu${W} para começar.${NC}"
