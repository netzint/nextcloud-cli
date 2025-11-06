#!/bin/bash

# Setup script for OnlyOffice connection monitoring cronjob
# This script adds a cronjob that regularly checks and maintains the OnlyOffice connection

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONLYOFFICE_SCRIPT="$SCRIPT_DIR/onlyoffice_connect.sh"
LOG_DIR="$SCRIPT_DIR/logs"

# Make sure the onlyoffice_connect.sh script exists
if [ ! -f "$ONLYOFFICE_SCRIPT" ]; then
    error "onlyoffice_connect.sh nicht gefunden in $SCRIPT_DIR"
    exit 1
fi

# Make scripts executable
log "Setze Ausführungsrechte..."
chmod +x "$ONLYOFFICE_SCRIPT"

# Create logs directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    log "Erstelle Log-Verzeichnis: $LOG_DIR"
    mkdir -p "$LOG_DIR"
fi

log "🔧 OnlyOffice Cron Job Setup"
echo ""
echo "Wähle die Überwachungsfrequenz:"
echo "1) Alle 1 Minute (für Produktionssysteme mit häufigen Verbindungsproblemen)"
echo "2) Alle 2 Minuten (empfohlen für kritische Systeme)"
echo "3) Alle 5 Minuten (empfohlen für normale Nutzung)"
echo "4) Alle 15 Minuten (für stabile Systeme)"
echo "5) Alle 30 Minuten (nur wenn Verbindung sehr stabil ist)"
echo "6) Stündlich"
echo "7) Manuell (zeigt nur Cronjob-Eintrag an)"
echo ""
read -p "Auswahl [1-7]: " choice

case $choice in
    1)
        CRON_SCHEDULE="* * * * *"
        DESCRIPTION="jede Minute"
        ;;
    2)
        CRON_SCHEDULE="*/2 * * * *"
        DESCRIPTION="alle 2 Minuten"
        ;;
    3)
        CRON_SCHEDULE="*/5 * * * *"
        DESCRIPTION="alle 5 Minuten"
        ;;
    4)
        CRON_SCHEDULE="*/15 * * * *"
        DESCRIPTION="alle 15 Minuten"
        ;;
    5)
        CRON_SCHEDULE="*/30 * * * *"
        DESCRIPTION="alle 30 Minuten"
        ;;
    6)
        CRON_SCHEDULE="0 * * * *"
        DESCRIPTION="stündlich"
        ;;
    7)
        CRON_JOB="$CRON_SCHEDULE $ONLYOFFICE_SCRIPT >> $LOG_DIR/onlyoffice_cron.log 2>&1"
        echo ""
        echo "Füge folgende Zeile manuell zu deinem Crontab hinzu:"
        echo "---"
        echo "$CRON_JOB"
        echo "---"
        echo ""
        echo "Befehl zum Bearbeiten des Crontabs:"
        echo "  crontab -e"
        exit 0
        ;;
    *)
        error "Ungültige Auswahl"
        exit 1
        ;;
esac

# Create the cron job entry
CRON_JOB="$CRON_SCHEDULE cd $SCRIPT_DIR && $ONLYOFFICE_SCRIPT >> $LOG_DIR/onlyoffice_cron.log 2>&1"

# Check if cron job already exists
EXISTING_CRON=$(crontab -l 2>/dev/null | grep -F "$ONLYOFFICE_SCRIPT")

if [ -n "$EXISTING_CRON" ]; then
    warning "Ein Cronjob für onlyoffice_connect.sh existiert bereits:"
    echo "  $EXISTING_CRON"
    echo ""
    read -p "Möchtest du ihn ersetzen? [j/N]: " replace

    if [[ "$replace" =~ ^[jJyY]$ ]]; then
        # Remove old cron job and add new one
        (crontab -l 2>/dev/null | grep -vF "$ONLYOFFICE_SCRIPT"; echo "$CRON_JOB") | crontab -
        log "✅ Cronjob aktualisiert: $DESCRIPTION"
    else
        log "Abgebrochen. Bestehender Cronjob bleibt unverändert."
        exit 0
    fi
else
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    log "✅ Cronjob hinzugefügt: $DESCRIPTION"
fi

echo ""
log "📋 Aktuelle Cronjobs:"
crontab -l | grep -F "$ONLYOFFICE_SCRIPT"

echo ""
log "📁 Logs werden gespeichert in: $LOG_DIR/onlyoffice_cron.log"
log "🔍 Log anzeigen: tail -f $LOG_DIR/onlyoffice_cron.log"

echo ""
log "✅ Setup abgeschlossen!"
echo ""
echo "Du kannst das Script auch manuell ausführen:"
echo "  $ONLYOFFICE_SCRIPT"
