#!/bin/bash

# Nextcloud Talk High Performance Backend (HPB) Configuration Script
# This script configures Nextcloud Talk to use the HPB for improved video/audio performance
#
# Usage: ./configure_talk_hpb.sh [--generate-secrets] [--with-recording] [--update-nginx]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }
warning() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Parse arguments
GENERATE_SECRETS=false
WITH_RECORDING=false
UPDATE_NGINX=false

for arg in "$@"; do
    case $arg in
        --generate-secrets)
            GENERATE_SECRETS=true
            ;;
        --with-recording)
            WITH_RECORDING=true
            ;;
        --update-nginx)
            UPDATE_NGINX=true
            ;;
        --help|-h)
            echo "Usage: ./configure_talk_hpb.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --generate-secrets  Generate new secrets and update talk-hpb.env"
            echo "  --with-recording    Enable and configure recording backend"
            echo "  --update-nginx      Add HPB proxy config to nginx.conf"
            echo "  --help              Show this help message"
            exit 0
            ;;
    esac
done

# Check if talk-hpb.env exists
ENV_FILE="./talk-hpb.env"
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "./talk-hpb.env.example" ]; then
        log "Kopiere talk-hpb.env.example nach talk-hpb.env..."
        cp ./talk-hpb.env.example "$ENV_FILE"
        GENERATE_SECRETS=true
    else
        error "talk-hpb.env.example nicht gefunden!"
        exit 1
    fi
fi

# Load environment variables
set -a
source "$ENV_FILE"
source ./nextcloud.env 2>/dev/null || true
set +a

# Generate secrets function
generate_secret() {
    openssl rand -hex 16
}

if [ "$GENERATE_SECRETS" = true ]; then
    log "Generiere neue Secrets..."

    NEW_TURN_SECRET=$(generate_secret)
    NEW_SIGNALING_SECRET=$(generate_secret)
    NEW_INTERNAL_SECRET=$(generate_secret)
    NEW_RECORDING_SECRET=$(generate_secret)

    # Update env file (macOS + Linux compatible)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^TURN_SECRET=.*/TURN_SECRET=$NEW_TURN_SECRET/" "$ENV_FILE"
        sed -i '' "s/^SIGNALING_SECRET=.*/SIGNALING_SECRET=$NEW_SIGNALING_SECRET/" "$ENV_FILE"
        sed -i '' "s/^INTERNAL_SECRET=.*/INTERNAL_SECRET=$NEW_INTERNAL_SECRET/" "$ENV_FILE"
        sed -i '' "s/^RECORDING_SECRET=.*/RECORDING_SECRET=$NEW_RECORDING_SECRET/" "$ENV_FILE"
    else
        sed -i "s/^TURN_SECRET=.*/TURN_SECRET=$NEW_TURN_SECRET/" "$ENV_FILE"
        sed -i "s/^SIGNALING_SECRET=.*/SIGNALING_SECRET=$NEW_SIGNALING_SECRET/" "$ENV_FILE"
        sed -i "s/^INTERNAL_SECRET=.*/INTERNAL_SECRET=$NEW_INTERNAL_SECRET/" "$ENV_FILE"
        sed -i "s/^RECORDING_SECRET=.*/RECORDING_SECRET=$NEW_RECORDING_SECRET/" "$ENV_FILE"
    fi

    # Reload variables
    set -a
    source "$ENV_FILE"
    set +a

    log "Secrets wurden generiert und gespeichert"
fi

# Validate required variables
if [ -z "$NC_DOMAIN" ]; then
    error "NC_DOMAIN ist nicht gesetzt in $ENV_FILE!"
    exit 1
fi

if [ -z "$SIGNALING_SECRET" ] || [ -z "$TURN_SECRET" ] || [ -z "$INTERNAL_SECRET" ]; then
    error "Secrets fehlen! Bitte mit --generate-secrets ausführen."
    exit 1
fi

echo ""
log "=========================================="
log "  Talk HPB Konfiguration"
log "=========================================="
echo ""
info "NC_DOMAIN:       $NC_DOMAIN"
info "SIGNALING_SECRET: ${SIGNALING_SECRET:0:8}..."
info "TURN_SECRET:      ${TURN_SECRET:0:8}..."
info "STUN/TURN Port:   ${TALK_PORT:-3478}"
echo ""

# Update nginx.conf if requested
NGINX_CONF="./nextcloud-nginx/nginx.conf"
if [ "$UPDATE_NGINX" = true ]; then
    log "Aktualisiere nginx.conf..."

    if grep -q "standalone-signaling" "$NGINX_CONF"; then
        warning "HPB Konfiguration bereits in nginx.conf vorhanden"
    else
        # Backup
        cp "$NGINX_CONF" "${NGINX_CONF}.bak"

        # Create temp file with HPB config
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

        # Insert before "location / {" using awk (works on both macOS and Linux)
        awk -v hpb="$(cat "$HPB_TMP")" '
            /location \/ \{/ && !done {
                print hpb
                done=1
            }
            {print}
        ' "$NGINX_CONF" > "${NGINX_CONF}.new" && mv "${NGINX_CONF}.new" "$NGINX_CONF"

        rm -f "$HPB_TMP"

        log "nginx.conf wurde aktualisiert (Backup: nginx.conf.bak)"
        warning "Nginx-Container muss neu gestartet werden!"
    fi
fi

# Check if nextcloud-fpm is running
if ! docker ps --format '{{.Names}}' | grep -q "nextcloud-fpm"; then
    warning "nextcloud-fpm Container läuft nicht!"
    warning "Bitte zuerst starten: docker compose up -d"
    echo ""
    log "Manuelle Konfiguration der Secrets:"
    echo "    SIGNALING_SECRET: $SIGNALING_SECRET"
    echo "    TURN_SECRET:      $TURN_SECRET"
    exit 0
fi

# Check/Install Talk app
log "Prüfe Nextcloud Talk App..."
APP_LIST=$(docker exec --user www-data nextcloud-fpm /var/www/html/occ app:list 2>/dev/null || echo "")

if ! echo "$APP_LIST" | grep -qi "spreed"; then
    log "Installiere Nextcloud Talk App..."
    if docker exec --user www-data nextcloud-fpm /var/www/html/occ app:install spreed; then
        log "Talk App erfolgreich installiert"
    else
        error "Installation fehlgeschlagen!"
        exit 1
    fi
else
    log "Talk App ist installiert"
fi

# Enable if disabled
if echo "$APP_LIST" | grep -A1 "Disabled" | grep -qi "spreed"; then
    log "Aktiviere Talk App..."
    docker exec --user www-data nextcloud-fpm /var/www/html/occ app:enable spreed
fi

# Configure HPB
log "Konfiguriere High Performance Backend..."

# Signaling server (URL für Nextcloud -> HPB)
HPB_URL="https://${NC_DOMAIN}/standalone-signaling"
SIGNALING_SERVERS="[{\"server\":\"${HPB_URL}\",\"verify\":true}]"

docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set spreed signaling_servers --value="$SIGNALING_SERVERS"
log "Signaling Server: $HPB_URL"

# Signaling secret
docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set spreed signaling_secret --value="$SIGNALING_SECRET"

# STUN server
STUN_SERVER="${NC_DOMAIN}:${TALK_PORT:-3478}"
docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set spreed stun_servers --value="[\"${STUN_SERVER}\"]"
log "STUN Server: $STUN_SERVER"

# TURN server
TURN_CONFIG="[{\"server\":\"${STUN_SERVER}\",\"secret\":\"${TURN_SECRET}\",\"protocols\":\"udp,tcp\"}]"
docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set spreed turn_servers --value="$TURN_CONFIG"
log "TURN Server: $STUN_SERVER"

# Recording (optional)
if [ "$WITH_RECORDING" = true ]; then
    log "Konfiguriere Recording Backend..."

    if [ -z "$RECORDING_SECRET" ]; then
        error "RECORDING_SECRET fehlt!"
        exit 1
    fi

    RECORDING_URL="https://${NC_DOMAIN}/recording"
    RECORDING_CONFIG="[{\"server\":\"${RECORDING_URL}\",\"secret\":\"${RECORDING_SECRET}\"}]"
    docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set spreed recording_servers --value="$RECORDING_CONFIG"
    log "Recording Server: $RECORDING_URL"
fi

echo ""
log "=========================================="
log "  Konfiguration abgeschlossen!"
log "=========================================="
echo ""

# Final instructions
if ! grep -q "standalone-signaling" "$NGINX_CONF" 2>/dev/null; then
    warning "WICHTIG: Nginx-Konfiguration fehlt noch!"
    echo ""
    echo "Option 1: Automatisch hinzufügen:"
    echo "    ./configure_talk_hpb.sh --update-nginx"
    echo ""
    echo "Option 2: Manuell aus Template kopieren:"
    echo "    Siehe: nextcloud-nginx/nginx-talk-hpb.conf.template"
    echo ""
fi

log "HPB Container starten:"
echo "    docker compose -f docker-compose.yml -f docker-compose.talk-hpb.yml up -d"
echo ""

if [ "$WITH_RECORDING" = true ]; then
    echo "Mit Recording:"
    echo "    docker compose -f docker-compose.yml -f docker-compose.talk-hpb.yml --profile recording up -d"
    echo ""
fi

log "Fertig!"
