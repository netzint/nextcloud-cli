#!/bin/bash

# OnlyOffice Connection Monitor & Auto-Reconnect Script
# This script checks and maintains the connection between Nextcloud and OnlyOffice Document Server

set -a
source ./nextcloud.env
set +a

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check if required environment variables are set
if [ -z "$ONLYOFFICE_SERVER_URL" ]; then
    error "ONLYOFFICE_SERVER_URL nicht in nextcloud.env gesetzt!"
    exit 1
fi

if [ -z "$ONLYOFFICE_JWT_SECRET" ]; then
    warning "ONLYOFFICE_JWT_SECRET nicht gesetzt - JWT-Authentifizierung deaktiviert"
fi

log "🔍 Prüfe OnlyOffice-Verbindung..."

# Check if OnlyOffice app is installed
APP_CHECK=$(docker exec --user www-data nextcloud-fpm /var/www/html/occ app:list | grep -i "onlyoffice")

if [ -z "$APP_CHECK" ]; then
    error "OnlyOffice App ist nicht installiert!"
    log "Installiere OnlyOffice App..."
    docker exec --user www-data nextcloud-fpm /var/www/html/occ app:install onlyoffice

    if [ $? -eq 0 ]; then
        log "✅ OnlyOffice App erfolgreich installiert"
    else
        error "❌ Installation fehlgeschlagen!"
        exit 1
    fi
fi

# Enable OnlyOffice app if disabled
if echo "$APP_CHECK" | grep -q "Disabled"; then
    log "Aktiviere OnlyOffice App..."
    docker exec --user www-data nextcloud-fpm /var/www/html/occ app:enable onlyoffice
fi

# Configure OnlyOffice Document Server URL
log "📝 Setze Document Server URL: $ONLYOFFICE_SERVER_URL"
docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set onlyoffice DocumentServerUrl --value="$ONLYOFFICE_SERVER_URL"

# Configure JWT Secret if provided
if [ -n "$ONLYOFFICE_JWT_SECRET" ]; then
    log "🔐 Setze JWT Secret..."
    docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set onlyoffice jwt_secret --value="$ONLYOFFICE_JWT_SECRET"
    docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set onlyoffice jwt_header --value="AuthorizationJwt"
else
    warning "⚠️  Kein JWT Secret gesetzt - Verbindung könnte unsicher sein!"
fi

# Additional OnlyOffice configuration for better stability
log "⚙️  Konfiguriere OnlyOffice-Einstellungen..."

# Set timeout values
docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set onlyoffice timeout --value="600"

# Enable verification peer (SSL)
docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set onlyoffice verify_peer_off --value=""

# Set storage URL if different from main URL
if [ -n "$NEXTCLOUD_URL" ]; then
    docker exec --user www-data nextcloud-fpm /var/www/html/occ config:app:set onlyoffice StorageUrl --value="$NEXTCLOUD_URL"
fi

# Test the connection
log "🔗 Teste Verbindung zum Document Server..."

CONNECTION_TEST=$(docker exec --user www-data nextcloud-fpm /var/www/html/occ onlyoffice:documentserver --check 2>&1)

if echo "$CONNECTION_TEST" | grep -qi "successfully\|erfolgreich\|success"; then
    log "✅ OnlyOffice-Verbindung erfolgreich hergestellt!"
    log "✅ Document Server ist erreichbar und funktioniert"
    exit 0
elif echo "$CONNECTION_TEST" | grep -qi "jwt"; then
    error "❌ JWT-Authentifizierung fehlgeschlagen!"
    error "Bitte prüfe das JWT Secret in nextcloud.env"
    echo "$CONNECTION_TEST"
    exit 1
elif echo "$CONNECTION_TEST" | grep -qi "curl\|connection\|timeout"; then
    error "❌ Kann Document Server nicht erreichen!"
    error "Bitte prüfe:"
    echo "  1. Ist der OnlyOffice Document Server gestartet?"
    echo "  2. Ist die URL korrekt: $ONLYOFFICE_SERVER_URL"
    echo "  3. Sind Firewall-Regeln korrekt?"
    echo "$CONNECTION_TEST"
    exit 1
else
    warning "⚠️  Unerwartete Antwort vom Document Server"
    echo "$CONNECTION_TEST"

    # Try one more time with delay
    log "Versuche erneut in 5 Sekunden..."
    sleep 5

    CONNECTION_TEST_2=$(docker exec --user www-data nextcloud-fpm /var/www/html/occ onlyoffice:documentserver --check 2>&1)

    if echo "$CONNECTION_TEST_2" | grep -qi "successfully\|erfolgreich\|success"; then
        log "✅ OnlyOffice-Verbindung erfolgreich hergestellt (2. Versuch)!"
        exit 0
    else
        error "❌ Verbindung fehlgeschlagen auch nach erneutem Versuch"
        echo "$CONNECTION_TEST_2"
        exit 1
    fi
fi
