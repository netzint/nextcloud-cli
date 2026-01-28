#!/bin/bash

# Nextcloud Talk High Performance Backend (HPB) - Vollautomatisches Setup
# Usage: ./configure_talk_hpb.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo ""
echo "=========================================="
echo "  Talk HPB - Automatisches Setup"
echo "=========================================="
echo ""

# ============================================================================
# SCHRITT 1: Environment-Datei erstellen
# ============================================================================
ENV_FILE="./talk-hpb.env"

if [ ! -f "$ENV_FILE" ]; then
    if [ ! -f "./talk-hpb.env.example" ]; then
        error "talk-hpb.env.example nicht gefunden!"
    fi
    info "Erstelle talk-hpb.env..."
    cp ./talk-hpb.env.example "$ENV_FILE"
fi

# Domain aus nextcloud.env holen falls vorhanden
if [ -f "./nextcloud.env" ]; then
    # Versuche verschiedene Quellen für die Domain
    NC_DOMAIN_FROM_ENV=$(grep -E "^NEXTCLOUD_TRUSTED_DOMAINS=" ./nextcloud.env | cut -d'=' -f2 | head -1)

    # Falls nextcloud.local oder leer, versuche NEXTCLOUD_URL
    if [ -z "$NC_DOMAIN_FROM_ENV" ] || [ "$NC_DOMAIN_FROM_ENV" = "nextcloud.local" ]; then
        NC_DOMAIN_FROM_ENV=$(grep -E "^NEXTCLOUD_URL=" ./nextcloud.env | cut -d'=' -f2 | sed 's|https://||;s|http://||;s|/.*||' | head -1)
    fi

    # Falls immer noch nichts, prüfe ob talk-hpb.env bereits eine gültige Domain hat
    if [ -z "$NC_DOMAIN_FROM_ENV" ] || [ "$NC_DOMAIN_FROM_ENV" = "nextcloud.local" ]; then
        EXISTING_DOMAIN=$(grep -E "^NC_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2)
        if [ -n "$EXISTING_DOMAIN" ] && [ "$EXISTING_DOMAIN" != "nextcloud.local" ]; then
            NC_DOMAIN_FROM_ENV="$EXISTING_DOMAIN"
        fi
    fi

    if [ -n "$NC_DOMAIN_FROM_ENV" ] && [ "$NC_DOMAIN_FROM_ENV" != "nextcloud.local" ]; then
        info "Domain gefunden: $NC_DOMAIN_FROM_ENV"
        sed -i "s/^NC_DOMAIN=.*/NC_DOMAIN=$NC_DOMAIN_FROM_ENV/" "$ENV_FILE"
        sed -i "s/^TALK_HOST=.*/TALK_HOST=$NC_DOMAIN_FROM_ENV/" "$ENV_FILE"
    fi
fi

# ============================================================================
# SCHRITT 2: Secrets generieren falls leer
# ============================================================================
source "$ENV_FILE"

generate_secret() { openssl rand -hex 16; }

if [ -z "$TURN_SECRET" ] || [ "$TURN_SECRET" = "" ]; then
    info "Generiere TURN_SECRET..."
    NEW_SECRET=$(generate_secret)
    sed -i "s/^TURN_SECRET=.*/TURN_SECRET=$NEW_SECRET/" "$ENV_FILE"
fi

if [ -z "$SIGNALING_SECRET" ] || [ "$SIGNALING_SECRET" = "" ]; then
    info "Generiere SIGNALING_SECRET..."
    NEW_SECRET=$(generate_secret)
    sed -i "s/^SIGNALING_SECRET=.*/SIGNALING_SECRET=$NEW_SECRET/" "$ENV_FILE"
fi

if [ -z "$INTERNAL_SECRET" ] || [ "$INTERNAL_SECRET" = "" ]; then
    info "Generiere INTERNAL_SECRET..."
    NEW_SECRET=$(generate_secret)
    sed -i "s/^INTERNAL_SECRET=.*/INTERNAL_SECRET=$NEW_SECRET/" "$ENV_FILE"
fi

if [ -z "$RECORDING_SECRET" ] || [ "$RECORDING_SECRET" = "" ]; then
    info "Generiere RECORDING_SECRET..."
    NEW_SECRET=$(generate_secret)
    sed -i "s/^RECORDING_SECRET=.*/RECORDING_SECRET=$NEW_SECRET/" "$ENV_FILE"
fi

# Reload
source "$ENV_FILE"

if [ -z "$NC_DOMAIN" ] || [ "$NC_DOMAIN" = "nextcloud.local" ]; then
    error "NC_DOMAIN nicht gesetzt! Bitte in talk-hpb.env anpassen."
fi

log "Domain: $NC_DOMAIN"
log "Secrets generiert"

# ============================================================================
# SCHRITT 3: Nginx-Konfiguration aktualisieren
# ============================================================================
NGINX_CONF="./nextcloud-nginx/nginx.conf"

if [ ! -f "$NGINX_CONF" ]; then
    error "nginx.conf nicht gefunden: $NGINX_CONF"
fi

if grep -q "standalone-signaling" "$NGINX_CONF"; then
    log "Nginx HPB-Config bereits vorhanden"
else
    info "Füge HPB-Config zu nginx.conf hinzu..."

    cp "$NGINX_CONF" "${NGINX_CONF}.bak"

    # Temporäre Datei mit HPB-Config
    HPB_TMP=$(mktemp)
    cat > "$HPB_TMP" << 'HPBCONF'

        # Talk HPB Signaling (WebSocket)
        location /standalone-signaling/ {
            proxy_pass http://nextcloud-talk-hpb:8081/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 3600s;
            proxy_buffering off;
        }

HPBCONF

    # Mit awk einfügen (funktioniert auf Linux und macOS)
    awk -v hpb="$(cat "$HPB_TMP")" '
        /location \/ \{/ && !done {
            print hpb
            done=1
        }
        {print}
    ' "${NGINX_CONF}.bak" > "$NGINX_CONF"

    rm -f "$HPB_TMP"
    log "Nginx-Config aktualisiert"
fi

# ============================================================================
# SCHRITT 4: Container starten/neustarten
# ============================================================================
info "Starte Container..."

# HPB Container starten
docker compose -f docker-compose.yml -f docker-compose.talk-hpb.yml up -d --force-recreate nextcloud-talk-hpb 2>/dev/null || \
docker-compose -f docker-compose.yml -f docker-compose.talk-hpb.yml up -d --force-recreate nextcloud-talk-hpb

# Nginx neu starten (um neue Config zu laden)
docker compose -f docker-compose.yml -f docker-compose.talk-hpb.yml restart nextcloud-nginx 2>/dev/null || \
docker-compose -f docker-compose.yml -f docker-compose.talk-hpb.yml restart nextcloud-nginx

log "Container gestartet"

# Warten bis HPB bereit ist
info "Warte auf HPB..."
sleep 5

# ============================================================================
# SCHRITT 5: Nextcloud Talk konfigurieren
# ============================================================================
info "Konfiguriere Nextcloud Talk..."

# Config-Berechtigung fixen
docker exec nextcloud-fpm chown -R www-data:www-data /var/www/html/config 2>/dev/null || true

# Talk App installieren/aktivieren
docker exec --user www-data nextcloud-fpm php occ app:install spreed 2>/dev/null || true
docker exec --user www-data nextcloud-fpm php occ app:enable spreed 2>/dev/null || true

# Signaling Server konfigurieren
HPB_URL="https://${NC_DOMAIN}/standalone-signaling"
docker exec --user www-data nextcloud-fpm php occ config:app:set spreed signaling_servers \
    --value="[{\"server\":\"${HPB_URL}\",\"verify\":true}]"

# Signaling Secret
docker exec --user www-data nextcloud-fpm php occ config:app:set spreed signaling_secret \
    --value="$SIGNALING_SECRET"

# STUN Server
STUN_SERVER="${NC_DOMAIN}:${TALK_PORT:-3478}"
docker exec --user www-data nextcloud-fpm php occ config:app:set spreed stun_servers \
    --value="[\"${STUN_SERVER}\"]"

# TURN Server
docker exec --user www-data nextcloud-fpm php occ config:app:set spreed turn_servers \
    --value="[{\"server\":\"${STUN_SERVER}\",\"secret\":\"${TURN_SECRET}\",\"protocols\":\"udp,tcp\"}]"

log "Nextcloud Talk konfiguriert"

# ============================================================================
# SCHRITT 6: Status prüfen
# ============================================================================
echo ""
echo "=========================================="
echo "  Setup abgeschlossen!"
echo "=========================================="
echo ""
info "HPB URL:     $HPB_URL"
info "STUN/TURN:   $STUN_SERVER"
echo ""

# Container-Status
if docker ps --format '{{.Names}}' | grep -q "nextcloud-talk-hpb"; then
    log "HPB Container läuft"
else
    warning "HPB Container läuft nicht!"
fi

# Signaling-Test
echo ""
info "Teste Verbindung..."
if docker exec nextcloud-nginx curl -s -o /dev/null -w "%{http_code}" http://nextcloud-talk-hpb:8081/api/v1/welcome | grep -q "200"; then
    log "HPB erreichbar via nginx"
else
    warning "HPB nicht erreichbar - prüfe Logs: docker logs nextcloud-talk-hpb"
fi

echo ""
log "Fertig! Teste Talk im Browser."
echo ""
