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
#!/bin/bash

set -e  # Exit script on error

# Add Docker GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list and install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker service
sudo systemctl enable --now docker

# Verify installation
sudo docker run --name test-container hello-world
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
If you want to install the container manually you can continue with manual install
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