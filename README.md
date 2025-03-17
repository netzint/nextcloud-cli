# Setting Up and Using Python Virtual Environment (venv)

## Table of Contents
1. [Installing the Script](#installing-the-script)
2. [Installing Nextcloud](#installing-nextcloud)
   - [Automated Installation](#automated-installation)
   - [Manual Installation](#manual-installation)
3. [Updating Nextcloud](#updating-nextcloud)

---

## Prerequisites

Before proceeding, ensure you have the necessary dependencies installed:

- **Python** (version 3.3 or higher)
  ```bash
  python --version
  ```
- **pip** (Python package manager)
  ```bash
  pip --version
  ```

---

## Installing the Script

### Creating a Virtual Environment

To keep dependencies isolated and avoid conflicts, create a virtual environment inside your project directory:

- **On Linux/macOS:**
  ```bash
  python3 -m venv env
  ```
- **On Windows:**
  ```bash
  python -m venv env
  ```

This will create a folder called `env` containing the virtual environment.

### Activating the Virtual Environment

Before installing dependencies, activate the virtual environment:

- **On Linux/macOS:**
  ```bash
  source env/bin/activate
  ```
- **On Windows:**
  ```bash
  env\Scripts\activate
  ```

Once activated, your terminal will show `(env)` at the beginning of the prompt.

### Installing Dependencies

Ensure you have a `requirements.txt` file in your project directory, then install all required packages:

```bash
pip install -r requirements.txt
```

### Running the Script

The script **has an interactive menu**, so it must be started manually:

```bash
python nextcloud-cli.py
```

Once started, the script will present a menu where you can choose:
1. **Install Nextcloud**
2. **Update Nextcloud**
3. **Exit**

Simply **select the desired option**, and the script will guide you through the necessary steps.

### Deactivating the Virtual Environment

To exit the virtual environment, simply run:

```bash
deactivate
```

---

## Installing Nextcloud

### Automated Installation

To install Nextcloud, **start the script**:

```bash
python nextcloud-cli.py
```

Then **select the "Install Nextcloud" option**. The script will:
- Fetch and install the necessary Docker images
- Create all required directories
- Configure and start the containers

The following directory structure will be automatically created under `/srv/docker/nextcloud`:

```plaintext
/srv/docker/nextcloud/
├── docker-compose.yml    # Docker Compose configuration
├── nextcloud.env         # Environment variables for Nextcloud
├── nextcloud-nginx/      # Nginx configuration directory
│   ├── nginx.conf        # Nginx configuration file
│   ├── Dockerfile        # Nginx container build file
├── data/                 # Persistent storage for Nextcloud
│   ├── nc_postgres/      # PostgreSQL data directory
│   ├── nc_redis/         # Redis data directory
│   ├── nc_html/          # Nextcloud application files
│   ├── nc_config/        # Configuration files for Nextcloud
│   ├── nc_custom_apps/   # Custom apps directory
│   ├── nc_data/          # User files and data storage
│   ├── nginx_conf/       # Additional configuration for Nginx
```

All folders will be **automatically created** and set up.

### Manual Installation

If you prefer a manual installation, follow these steps:

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-repo/nextcloud-docker.git /srv/docker/nextcloud
   ```

2. **Start the containers**:
   ```bash
   cd /srv/docker/nextcloud
   docker-compose up -d
   ```

This will set up Nextcloud with PostgreSQL, Redis, and Nginx.

---

## Updating Nextcloud

To update Nextcloud, **start the script**:

```bash
python nextcloud-cli.py
```

Then **select the "Update Nextcloud" option**. The script will:
- Detect the currently installed Nextcloud version
- Fetch the latest available Nextcloud version
- Guide you through the update process **step by step**
- Ensure that the update is performed in the correct sequence (major versions are upgraded one at a time)
- Restart the Nextcloud service after the update

### Updating Additional Services

The script will also ask if you want to update additional services like:
- **PostgreSQL**
- **Redis**
- **Nginx**

If updates are available, the script will guide you through the process.

After the update, the system will automatically check the status of Nextcloud to ensure it is running correctly.

---

## Additional Notes

- Always ensure that the virtual environment is activated before running any Python commands.
- Using Docker ensures that Nextcloud and its dependencies remain isolated and easy to manage.
- Regularly updating your Nextcloud instance is crucial for security and performance.
- The script provides interactive options to configure Nextcloud based on your preferences.
