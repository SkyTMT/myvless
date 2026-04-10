#!/bin/bash
# =============================================================
# VLESS + Reality + 3x-ui Docker
# Запуск на чистом сервере:
# bash <(curl -fsSL https://raw.githubusercontent.com/SkyTMT/myvless/main/setup.sh)
# =============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

REPO="https://raw.githubusercontent.com/SkyTMT/myvless/main"
WORKDIR="/root/myvless"

[[ $EUID -ne 0 ]] && err "Run as root: sudo bash setup.sh"

# =============================================================
# 1. Рабочая директория + docker-compose.yml
# =============================================================
log "Setting up working directory: $WORKDIR"
mkdir -p "$WORKDIR/data/db" "$WORKDIR/data/cert"
cd "$WORKDIR"

log "Downloading docker-compose.yml..."
curl -fsSL "$REPO/docker-compose.yml" -o docker-compose.yml

# =============================================================
# 2. Интерактивная конфигурация
# =============================================================
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}   VLESS + Reality Setup${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

read -p "Panel port [23232]: " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-23232}

read -p "Panel path [skyvless]: " PANEL_PATH
PANEL_PATH=${PANEL_PATH:-skyvless}

read -p "VLESS port [443]: " VLESS_PORT
VLESS_PORT=${VLESS_PORT:-443}

# Создаём .env
cat > .env << EOF
PANEL_PORT=$PANEL_PORT
PANEL_PATH=$PANEL_PATH
VLESS_PORT=$VLESS_PORT
TZ=UTC
EOF

log "Config saved to .env"

# =============================================================
# 3. Системные пакеты
# =============================================================
log "Updating system..."
apt update && apt upgrade -y
apt install -y curl wget ufw fail2ban unattended-upgrades \
    openssl ca-certificates gnupg lsb-release

# =============================================================
# 4. Docker
# =============================================================
if command -v docker &>/dev/null; then
    warn "Docker already installed: $(docker --version)"
else
    log "Installing Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    log "Docker installed: $(docker --version)"
fi

# =============================================================
# 5. Firewall
# =============================================================
log "Configuring UFW..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow ${VLESS_PORT}/tcp
ufw allow ${PANEL_PORT}/tcp
ufw --force enable

# =============================================================
# 6. Fail2ban
# =============================================================
log "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = 22
maxretry = 5
bantime = 3600
findtime = 600
EOF
systemctl enable fail2ban
systemctl restart fail2ban

# =============================================================
# 7. Автообновления
# =============================================================
dpkg-reconfigure -f noninteractive unattended-upgrades

# =============================================================
# 8. BBR
# =============================================================
log "Optimizing network stack..."
grep -q "tcp_congestion_control" /etc/sysctl.conf || cat >> /etc/sysctl.conf << 'EOF'

# VLESS optimizations
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
EOF
sysctl -p

# =============================================================
# 9. SNI Scanner
# =============================================================
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}   SNI Scanner${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "Введи TLD страны сервера:"
echo -e "  ${YELLOW}at${NC} Austria  ${YELLOW}de${NC} Germany  ${YELLOW}fi${NC} Finland"
echo -e "  ${YELLOW}nl${NC} Netherlands  ${YELLOW}fr${NC} France  ${YELLOW}se${NC} Sweden"
echo -e "  ${YELLOW}gb${NC} UK  ${YELLOW}ch${NC} Switzerland  ${YELLOW}pl${NC} Poland"
echo -e "  ${YELLOW}cz${NC} Czech  ${YELLOW}es${NC} Spain  ${YELLOW}it${NC} Italy"
echo -n "> "
read TLD

CANDIDATES=(
    "www.adobe.com"
    "www.spotify.com"
    "www.salesforce.com"
    "www.intel.com"
    "www.ikea.com"
    "www.booking.com"
    "www.klarna.com"
    "www.unity.com"
    "www.hm.com"
    "www.zara.com"
)

case "$TLD" in
    at) CANDIDATES+=("www.billa.at" "www.spar.at" "www.orf.at" "www.austria.info" "www.raiffeisen.at" "www.drei.at") ;;
    fi) CANDIDATES+=("www.elisa.fi" "www.dna.fi" "www.yle.fi" "www.finnair.com" "www.nordea.fi") ;;
    de) CANDIDATES+=("www.telekom.de" "www.dhl.de" "www.otto.de" "www.zalando.de" "www.lidl.de") ;;
    nl) CANDIDATES+=("www.ing.nl" "www.ns.nl" "www.ah.nl" "www.bol.com" "www.philips.com") ;;
    fr) CANDIDATES+=("www.sncf.com" "www.orange.fr" "www.fnac.com" "www.leboncoin.fr" "www.laposte.fr") ;;
    se) CANDIDATES+=("www.svt.se" "www.sj.se" "www.ica.se" "www.telia.se" "www.dn.se") ;;
    gb|uk) CANDIDATES+=("www.bbc.co.uk" "www.sky.com" "www.bt.com" "www.tesco.com" "www.vodafone.co.uk") ;;
    ch) CANDIDATES+=("www.sbb.ch" "www.migros.ch" "www.post.ch" "www.swisscom.ch" "www.ubs.com") ;;
    pl) CANDIDATES+=("www.allegro.pl" "www.onet.pl" "www.wp.pl" "www.pko.pl" "www.orange.pl") ;;
    cz) CANDIDATES+=("www.seznam.cz" "www.csob.cz" "www.o2.cz" "www.alza.cz" "www.czc.cz") ;;
    es) CANDIDATES+=("www.elcorteingles.es" "www.mercadona.es" "www.movistar.es" "www.renfe.com") ;;
    it) CANDIDATES+=("www.trenitalia.com" "www.telecomitalia.it" "www.mediaworld.it" "www.unipolsai.it") ;;
    *) warn "Unknown TLD, using global candidates only" ;;
esac

echo ""
log "Scanning ${#CANDIDATES[@]} candidates..."
echo ""

declare -A RESULTS

for domain in "${CANDIDATES[@]}"; do
    result=$(curl -s --connect-timeout 3 --max-time 5 \
        -w "%{time_connect} %{http_version}" \
        -o /dev/null "https://$domain" 2>/dev/null || echo "9999 0")
    ms=$(echo $result | awk '{printf "%.0f", $1*1000}')
    ver=$(echo $result | awk '{print $2}')
    if [[ "$ver" == "2" || "$ver" == "3" ]]; then
        echo -e "  ${GREEN}${ms}ms [H${ver}]${NC} $domain"
        RESULTS[$domain]=$ms
    else
        echo -e "  ${RED}${ms}ms [skip]${NC} $domain"
    fi
done

echo ""
echo -e "${YELLOW}Выбери SNI (или Enter для лучшего автоматически):${NC}"

# Топ 1 автоматически
BEST_SNI=""
BEST_PING=9999
for domain in "${!RESULTS[@]}"; do
    if [[ ${RESULTS[$domain]} -lt $BEST_PING ]]; then
        BEST_PING=${RESULTS[$domain]}
        BEST_SNI=$domain
    fi
done

echo -e "Лучший вариант: ${GREEN}$BEST_SNI${NC} (${BEST_PING}ms)"
echo -n "> "
read CHOSEN_SNI
CHOSEN_SNI=${CHOSEN_SNI:-$BEST_SNI}
[[ -z "$CHOSEN_SNI" ]] && CHOSEN_SNI="www.microsoft.com"

log "SNI: $CHOSEN_SNI"

# =============================================================
# 10. Запуск контейнера
# =============================================================
log "Starting 3x-ui container..."
docker compose up -d

log "Waiting for panel to start..."
sleep 15

# Настраиваем порт и путь через SQLite
log "Configuring panel port and path..."
apt install -y sqlite3 -qq
DB="$WORKDIR/data/db/x-ui.db"
for i in $(seq 1 20); do [[ -f "$DB" ]] && break; sleep 2; done
sqlite3 "$DB" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webPort','${PANEL_PORT}');"
sqlite3 "$DB" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webBasePath','${PANEL_PATH}');"

# Ждём пока контейнер создаст базу
for i in $(seq 1 20); do
    [[ -f "$DB" ]] && break
    sleep 2
done

sqlite3 "$DB" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webPort','${PANEL_PORT}');"
sqlite3 "$DB" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webBasePath','${PANEL_PATH}');"
log "Panel configured: port=${PANEL_PORT} path=${PANEL_PATH}"

docker restart 3x-ui
sleep 5

# =============================================================
# 11. Итог
# =============================================================
SERVER_IP=$(curl -s ifconfig.me)

echo ""
echo "============================================================"
echo -e "${GREEN}  DONE!${NC}"
echo "============================================================"
echo ""
echo -e "${YELLOW}  Panel:${NC}   http://$SERVER_IP:${PANEL_PORT}/${PANEL_PATH}"
echo -e "${YELLOW}  Login:${NC}   admin / admin  (change immediately!)"
echo ""
echo -e "${YELLOW}  VLESS inbound settings:${NC}"
echo "  Port:      ${VLESS_PORT}"
echo "  Transport: TCP RAW"
echo "  Security:  Reality"
echo "  SNI:       $CHOSEN_SNI"
echo "  Target:    $CHOSEN_SNI:443"
echo "  uTLS:      chrome"
echo "  Flow:      xtls-rprx-vision"
echo ""
echo -e "${YELLOW}  Next server — just run:${NC}"
echo "  bash <(curl -fsSL https://raw.githubusercontent.com/SkyTMT/myvless/main/setup.sh)"
echo ""
echo "============================================================"

cat > "$WORKDIR/server_info.txt" << EOF
Server: $SERVER_IP
Panel: http://$SERVER_IP:${PANEL_PORT}/${PANEL_PATH}

VLESS:
  Port: ${VLESS_PORT}
  Transport: TCP RAW
  Security: Reality
  SNI: $CHOSEN_SNI
  Target: $CHOSEN_SNI:443
  uTLS: chrome
  Flow: xtls-rprx-vision
EOF

log "Saved to $WORKDIR/server_info.txt"
