# Setting Up and Using Python Virtual Environment (venv)

## Table of Contents
1. [System Preparation](#system-preparation)
2. [Installing the Script](#installing-the-script)
3. [Installing Nextcloud](#installing-nextcloud)
   - [Automated Installation](#automated-installation)
   - [Manual Installation](#manual-installation)
4. [Updating Nextcloud](#updating-nextcloud)

---

## System Preparation

### Requirements
Before proceeding, ensure you are using **Ubuntu** with the following requirements:

- **Primary disk**: 50GB
- **Secondary disk**: At least 250GB (adjust as needed for your storage requirements)

### Installing Docker
Run the following script to install Docker:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### Partitioning and Mounting the Secondary Disk

#### Checking Available Disks
Run the following command to list available disks:
```bash
fdisk -l
```
Example output:
```plaintext
Disk /dev/sda: 50 GiB, 53687091200 bytes, 104857600 sectors
Disk /dev/sdb: 250 GiB, 268435456000 bytes, 524288000 sectors
```
#### Formatting the Disk
```bash
mkfs.ext4 /dev/sdb
```
#### Retrieving the UUID
```bash
blkid
```
Example output:
```plaintext
/dev/sdb: UUID="f0fe2cb4-7dc2-4221-b2d7-43dca43a3151" BLOCK_SIZE="4096" TYPE="ext4"
```
#### Adding to fstab
Edit `/etc/fstab`:
```bash
nano /etc/fstab
```
Add the following line:
```plaintext
UUID=f0fe2cb4-7dc2-4221-b2d7-43dca43a3151 /srv/docker/nextcloud ext4 defaults 0 2
```
#### Mounting the Disk
```bash
mkdir -p /srv/docker/nextcloud
mount -a
```
Check if the disk is mounted correctly:
```bash
df -h
```
Example output:
```plaintext
/dev/sdb        246G   28K  233G   1% /srv/docker/nextcloud
```
#### Removing `lost+found` Directory
After mounting, the `lost+found` directory is automatically created on ext4 filesystems. It should be removed before proceeding:
```bash
rm -rf /srv/docker/nextcloud/lost+found
```

If you want to install the container manually you can continue with [manual install](#updating-nextcloud)

---

## Installing the Script

### Creating a Virtual Environment
```bash
python3 -m venv env
```

### Activating the Virtual Environment
```bash
source env/bin/activate  # Linux/macOS
env\Scripts\activate     # Windows
```

### Installing Dependencies
```bash
pip install -r requirements.txt
```

### Running the Script
```bash
python nextcloud-cli.py
```

### Deactivating the Virtual Environment
```bash
deactivate
```

---

## Installing Nextcloud

### Automated Installation
```bash
python nextcloud-cli.py
```
This will set up the following directory structure:
```plaintext
/srv/docker/nextcloud/
├── docker-compose.yml
├── nextcloud.env
├── nextcloud-nginx/
│   ├── nginx.conf
│   ├── Dockerfile
├── data/
│   ├── nc_postgres/
│   ├── nc_redis/
│   ├── nc_html/
│   ├── nc_config/
│   ├── nc_custom_apps/
│   ├── nc_data/
│   ├── nginx_conf/
```

### Manual Installation
1. **Clone the repository**
   ```bash
   git clone https://github.com/netzint/nextcloud-cli.git /srv/docker/nextcloud
   ```
2. **Copy Configuration File**
   ```bash
   cp /srv/docker/nextcloud/nextcloud.env.example /srv/docker/nextcloud/nextcloud.env
   ```
3. **Modify Passwords in nextcloud.env**
   Edit `/srv/docker/nextcloud/nextcloud.env` and change:
   ```plaintext
   POSTGRES_PASSWORD=YOUR_SECURE_PASSWORD
   NEXTCLOUD_DB_PASSWORD=YOUR_SECURE_PASSWORD
   REDIS_PASS=YOUR_SECURE_PASSWORD
   NEXTCLOUD_ADMIN_PASSWORD=YOUR_SECURE_PASSWORD
   ```
4. **Configure Trusted Domains**
   Open `/srv/docker/nextcloud/nextcloud.env` and set `NEXTCLOUD_TRUSTED_DOMAINS`:
   ```plaintext
   NEXTCLOUD_TRUSTED_DOMAINS=your.domain.com
   ```
5. **Start the containers**
   ```bash
   cd /srv/docker/nextcloud
   docker-compose up -d
   ```

---

## Updating Nextcloud

```bash
python nextcloud-cli.py
```
The script will:
- Detect the currently installed Nextcloud version
- Fetch and update to the latest version
- Offer optional updates for PostgreSQL, Redis, and Nginx
- Restart Nextcloud automatically

---

## OnlyOffice Document Server Integration

### Configuration

1. **Edit your environment file**
   ```bash
   nano nextcloud.env
   ```

2. **Add OnlyOffice configuration**
   ```bash
   # OnlyOffice Document Server Configuration
   ONLYOFFICE_SERVER_URL=https://office.your-domain.com
   ONLYOFFICE_JWT_SECRET=YourJWTSecretHere
   ```

### Setup OnlyOffice Connection

#### Manual Setup
```bash
./onlyoffice_connect.sh
```

#### Automated Monitoring (Recommended)
```bash
./setup_onlyoffice_cron.sh
```

Choose your preferred monitoring frequency:
- **Every minute** - For production systems with frequent connection issues
- **Every 2 minutes** - Recommended for critical systems
- **Every 5 minutes** - Recommended for normal usage
- **Every 15 minutes** - For stable systems

### Viewing Logs
```bash
tail -f logs/onlyoffice_cron.log
```

---

## Nextcloud Talk High Performance Backend (Optional)

Das Talk High Performance Backend (HPB) verbessert die Video-/Audio-Qualität bei Gruppen-Calls erheblich. Es ist optional und kann jederzeit nachinstalliert werden.

### Voraussetzungen

- Port **3478 TCP+UDP** muss in der Firewall offen sein
- Bei NAT: Port-Forwarding für 3478 erforderlich
- Nextcloud muss bereits laufen

### Neuinstallation (mit HPB von Anfang an)

```bash
# 1. Repository klonen
git clone https://github.com/netzint/nextcloud-cli.git /srv/docker/nextcloud
cd /srv/docker/nextcloud

# 2. Basis-Konfiguration
cp nextcloud.env.example nextcloud.env
nano nextcloud.env  # Passwörter und Domain anpassen

# 3. Talk HPB konfigurieren
./configure_talk_hpb.sh --generate-secrets --update-nginx

# 4. Alle Container starten (Nextcloud + HPB)
docker compose -f docker-compose.yml -f docker-compose.talk-hpb.yml up -d
```

### Bestandsinstallation (HPB nachträglich hinzufügen)

```bash
cd /srv/docker/nextcloud

# 1. Talk HPB konfigurieren (generiert Secrets, aktualisiert nginx.conf)
./configure_talk_hpb.sh --generate-secrets --update-nginx

# 2. HPB-Container starten
docker compose -f docker-compose.yml -f docker-compose.talk-hpb.yml up -d

# 3. Nginx neu laden (wichtig!)
docker compose restart nextcloud-nginx
```

### Talk HPB Konfiguration anpassen

Die Konfiguration liegt in `talk-hpb.env`:

```bash
# Domain (muss mit NEXTCLOUD_TRUSTED_DOMAINS übereinstimmen)
NC_DOMAIN=cloud.example.com

# Timezone
TZ=Europe/Berlin

# Secrets (automatisch generiert)
TURN_SECRET=...
SIGNALING_SECRET=...
INTERNAL_SECRET=...
```

### HPB Status prüfen

```bash
# Container-Status
docker compose -f docker-compose.yml -f docker-compose.talk-hpb.yml ps

# HPB Logs
docker logs nextcloud-talk-hpb

# Nextcloud Talk-Einstellungen prüfen
docker exec --user www-data nextcloud-fpm /var/www/html/occ talk:signaling:list
```

### Recording Backend (Optional)

Für Call-Aufnahmen kann das Recording-Backend aktiviert werden:

```bash
# Mit Recording starten
docker compose -f docker-compose.yml -f docker-compose.talk-hpb.yml --profile recording up -d

# Recording in Nextcloud konfigurieren
./configure_talk_hpb.sh --with-recording
```

### HPB deaktivieren

```bash
# Nur Basis-Nextcloud starten (ohne HPB)
docker compose up -d

# HPB-Container stoppen
docker stop nextcloud-talk-hpb
```

---
