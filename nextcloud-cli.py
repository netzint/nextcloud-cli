#!/usr/bin/env python3
"""
Netzint CLI – Nextcloud Installation and Update

Note: The generated files (docker-compose.yml, nextcloud.env, nginx.conf,
Dockerfile, etc.) are created exactly as in the original.
"""

import os
import time
import secrets
import requests
import docker
import yaml
import subprocess
from packaging.version import Version, InvalidVersion
from InquirerPy import prompt
from rich.console import Console
from rich.prompt import Prompt, Confirm
from rich import print

console = Console()

# ─── Constants ───────────────────────────────────────────────

NEXTCLOUD_REPO = "library/nextcloud"
POSTGRES_REPO  = "library/postgres"
REDIS_REPO     = "library/redis"
NGINX_REPO     = "library/nginx"
MAX_PAGE = 100  # Maximum number of pages to load

# ─── Utility Functions ─────────────────────────────────────────

def generate_password():
    """Generates a secure, random password."""
    return secrets.token_hex(8)

def maybe_container_name(base_name, version_str):
    """
    Returns a container name in the format 'nextcloud-{base_name}'.
    The version information is not appended.
    """
    return f"nextcloud-{base_name}"

# ─── Docker Hub Version Fetching ───────────────────────────────

def fetch_nextcloud_fpm_versions():
    """
    Fetch up to 100 tags for Nextcloud (FPM variants) from Docker Hub and return
    up to 10 distinct major versions (sorted in descending order).
    Only valid version tags are returned – "latest" is never used.
    """
    console.print("[bright_blue]🔎 Fetching Nextcloud-FPM versions from Docker Hub...[/bright_blue]")
    all_fpm_versions = []
    try:
        page = 1
        page_size = 50
        while page <= MAX_PAGE and len(all_fpm_versions) < 100:
            url = f"https://hub.docker.com/v2/repositories/{NEXTCLOUD_REPO}/tags?page_size={page_size}&page={page}"
            resp = requests.get(url, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            results = data.get("results", [])
            if not results:
                break
            for item in results:
                tag_name = item.get("name", "")
                # Skip unwanted tags
                if any(sub in tag_name for sub in ["apache", "windows", "rc", "beta"]):
                    continue
                if "fpm" not in tag_name:
                    continue
                try:
                    core_ver = tag_name.replace("-fpm", "")
                    Version(core_ver)
                    all_fpm_versions.append(tag_name)
                except InvalidVersion:
                    continue
            if not data.get("next"):
                break
            page += 1

        def parse_core(tag):
            return Version(tag.replace("-fpm", ""))
        sorted_tags = sorted(set(all_fpm_versions), key=lambda x: parse_core(x), reverse=True)
        distinct_majors = {}
        for full_tag in sorted_tags:
            core = parse_core(full_tag)
            if core.major not in distinct_majors:
                distinct_majors[core.major] = full_tag
            if len(distinct_majors) >= 10:
                break
        final_list = list(distinct_majors.values())
        # Return in descending order by default.
        final_list = sorted(final_list, key=lambda x: parse_core(x), reverse=True)
        return final_list
    except Exception as e:
        console.print(f"[bright_red]Error fetching Nextcloud-FPM versions: {e}[/bright_red]")
        return []

def fetch_semver_versions(docker_repo, max_count=10, filter_substrings=None):
    """
    Fetch valid SemVer tags from a Docker repository and return up to max_count
    distinct major versions (sorted in descending order).
    "latest" is never returned.
    """
    if filter_substrings is None:
        filter_substrings = ["windows", "rc", "beta"]
    all_versions = []
    try:
        page = 1
        page_size = 50
        while page <= MAX_PAGE and len(all_versions) < 100:
            url = f"https://hub.docker.com/v2/repositories/{docker_repo}/tags?page_size={page_size}&page={page}"
            resp = requests.get(url, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            results = data.get("results", [])
            if not results:
                break
            for item in results:
                tag_name = item.get("name", "")
                if any(sub in tag_name for sub in filter_substrings):
                    continue
                try:
                    Version(tag_name)
                    all_versions.append(tag_name)
                except InvalidVersion:
                    continue
            if not data.get("next"):
                break
            page += 1
        sorted_tags = sorted(set(all_versions), key=lambda x: Version(x), reverse=True)
        distinct = {}
        for tag in sorted_tags:
            ver = Version(tag)
            if ver.major not in distinct:
                distinct[ver.major] = tag
            if len(distinct) >= max_count:
                break
        final_list = list(distinct.values())
        final_list = sorted(final_list, key=lambda x: Version(x), reverse=True)
        return final_list
    except Exception as e:
        console.print(f"[bright_red]Error fetching versions for {docker_repo}: {e}[/bright_red]")
        return []

# ─── Postgres Healthcheck ───────────────────────────────────────

def postgres_healthcheck(pg_user, pg_password):
    """Robust healthcheck for Postgres using pg_isready."""
    return {
        "test": [
            "CMD-SHELL",
            f"pg_isready -U {pg_user} -d nextcloud -h 127.0.0.1 || exit 1"
        ],
        "interval": "10s",
        "timeout": "5s",
        "retries": 5,
        "start_period": "20s"
    }

# ─── Base Path and Filesystem Setup ─────────────────────────────

def prompt_base_path():
    """Prompts the base path for Docker files (default: ./docker/nextcloud/)."""
    return Prompt.ask("[bright_blue]Please enter the base path for Docker files[/bright_blue]", default="./docker/nextcloud/")

def setup_nginx_build_folder(base_path):
    """
    Sets up the Nginx build folder:
      - Copies nginx.conf into the folder
      - Creates a Dockerfile in the same folder.
    """
    target = os.path.join(base_path, "nextcloud-nginx")
    try:
        os.makedirs(target, exist_ok=True)
    except Exception as e:
        console.print(f"[bright_red]Error creating folder {target}: {e}[/bright_red]")
        return

    target_nginx_conf = os.path.join(target, "nginx.conf")
    nginx_conf = getNginxConf()
    try:
        with open(target_nginx_conf, "w") as f:
            f.write(nginx_conf)
        console.print(f"[bright_green]nginx.conf copied to {target_nginx_conf}.[/bright_green]")
    except Exception as e:
        console.print(f"[bright_red]Error copying nginx.conf: {e}[/bright_red]")

    dockerfile_path = os.path.join(target, "Dockerfile")
    dockerfile_content = "FROM nginx:alpine\nCOPY nginx.conf /etc/nginx/nginx.conf\n"
    try:
        with open(dockerfile_path, "w") as f:
            f.write(dockerfile_content)
        console.print(f"[bright_green]Dockerfile created in {dockerfile_path}.[/bright_green]")
    except Exception as e:
        console.print(f"[bright_red]Error creating Dockerfile: {e}[/bright_red]")

def create_local_directories(base_path):
    """Creates the required local folders for Docker volumes."""
    if Confirm.ask("[bright_blue]Create local folders for Docker volumes?[/bright_blue]", default=True):
        dirs = [
            base_path,
            os.path.join(base_path, "data"),
            os.path.join(base_path, "data", "nc_postgres"),
            os.path.join(base_path, "data", "nc_redis"),
            os.path.join(base_path, "data", "nc_html"),
            os.path.join(base_path, "data", "nc_config"),
            os.path.join(base_path, "data", "nc_custom_apps"),
            os.path.join(base_path, "data", "nc_data"),
            os.path.join(base_path, "data", "nginx_conf"),
            os.path.join(base_path, "nextcloud-ngnix")
        ]
        for d in dirs:
            try:
                os.makedirs(d, exist_ok=True)
            except Exception as e:
                console.print(f"[bright_red]Error creating folder {d}: {e}[/bright_red]")
        console.print("[bright_green]Local folders created (if not already present).[/bright_green]")
    else:
        console.print("[bright_yellow]Please ensure that the folders exist![/bright_yellow]")

def write_compose_file(compose_data, base_path):
    """Writes the docker-compose.yml file in the base path."""
    compose_file = os.path.join(base_path, "docker-compose.yml")
    try:
        with open(compose_file, "w") as f:
            yaml.dump(compose_data, f, default_flow_style=False)
        console.print(f"\n[bright_green]✅ Docker-compose file '{compose_file}' created![/bright_green]")
    except Exception as e:
        console.print(f"[bright_red]Error writing compose file: {e}[/bright_red]")

def create_env_file(path, pg_pass, nc_db_user, nc_db_pass, redis_pass, nc_admin_user, nc_admin_pass):
    """
    Writes all sensitive data into the nextcloud.env file.
    """
    lines = [
        "# nextcloud.env for Nextcloud-FPM + PostgreSQL + Redis + Nginx",
        f"POSTGRES_PASSWORD={pg_pass}",
        f"NEXTCLOUD_DB_USER={nc_db_user}",
        f"POSTGRES_USER={nc_db_user}",
        "POSTGRES_DB=nextcloud",
        f"NEXTCLOUD_DB_PASSWORD={nc_db_pass}",
        f"REDIS_PASS={redis_pass}",
        f"NEXTCLOUD_ADMIN_USER={nc_admin_user}",
        f"NEXTCLOUD_ADMIN_PASSWORD={nc_admin_pass}",
        f"POSTGRES_HOST=postgres",
        f"REDIS_HOST=redis",
        ""
    ]
    try:
        with open(path, "w") as f:
            f.write("\n".join(lines))
        console.print(f"[bright_green]Created 'nextcloud.env' at {path} with all credentials.[/bright_green]")
    except Exception as e:
        console.print(f"[bright_red]Error creating env file: {e}[/bright_red]")

def getNginxConf():
    """Returns the content of nginx.conf as a placeholder."""
    return r"""
worker_processes auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include mime.types;
    default_type  application/octet-stream;
    types {
        text/javascript mjs;
        application/wasm wasm;
    }

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    # Prevent nginx HTTP Server Detection
    server_tokens   off;

    keepalive_timeout  65;

    # Set the `immutable` cache control options only for assets with a cache busting `v` argument
    map $arg_v $asset_immutable {
        "" "";
    default ", immutable";
    }

    #gzip  on;

    upstream php-handler {
        server nextcloud-fpm:9000;
    }

    server {
        listen 80;

        # HSTS settings
        # WARNING: Only add the preload option once you read about
        # the consequences in https://hstspreload.org/. This option
        # will add the domain to a hardcoded list that is shipped
        # in all major browsers and getting removed from this list
        # could take several months.
        #add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;

        # set max upload size and increase upload timeout:
        client_max_body_size 512M;
        client_body_timeout 300s;
        fastcgi_buffers 64 4K;

        # The settings allows you to optimize the HTTP2 bandwidth.
        # See https://blog.cloudflare.com/delivering-http-2-upload-speed-improvements/
        # for tuning hints
        client_body_buffer_size 512k;

        # Enable gzip but do not remove ETag headers
        gzip on;
        gzip_vary on;
        gzip_comp_level 4;
        gzip_min_length 256;
        gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
        gzip_types application/atom+xml text/javascript application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

        # Pagespeed is not supported by Nextcloud, so if your server is built
        # with the `ngx_pagespeed` module, uncomment this line to disable it.
        #pagespeed off;

        # HTTP response headers borrowed from Nextcloud `.htaccess`
        add_header Referrer-Policy                      "no-referrer"       always;
        add_header X-Content-Type-Options               "nosniff"           always;
        add_header X-Frame-Options                      "SAMEORIGIN"        always;
        add_header X-Permitted-Cross-Domain-Policies    "none"              always;
        add_header X-Robots-Tag                         "noindex, nofollow" always;
        add_header X-XSS-Protection                     "1; mode=block"     always;

        # Remove X-Powered-By, which is an information leak
        fastcgi_hide_header X-Powered-By;

        # Path to the root of your installation
        root /var/www/html;

        # Specify how to handle directories -- specifying `/index.php$request_uri`
        # here as the fallback means that Nginx always exhibits the desired behaviour
        # when a client requests a path that corresponds to a directory that exists
        # on the server. In particular, if that directory contains an index.php file,
        # that file is correctly served; if it doesn't, then the request is passed to
        # the front-end controller. This consistent behaviour means that we don't need
        # to specify custom rules for certain paths (e.g. images and other assets,
        # `/updater`, `/ocm-provider`, `/ocs-provider`), and thus
        # `try_files $uri $uri/ /index.php$request_uri`
        # always provides the desired behaviour.
        index index.php index.html /index.php$request_uri;

        # Rule borrowed from `.htaccess` to handle Microsoft DAV clients
        location = / {
            if ( $http_user_agent ~ ^DavClnt ) {
                return 302 /remote.php/webdav/$is_args$args;
            }
        }

        location = /robots.txt {
            allow all;
            log_not_found off;
            access_log off;
        }

        # Make a regex exception for `/.well-known` so that clients can still
        # access it despite the existence of the regex rule
        # `location ~ /(\.|autotest|...)` which would otherwise handle requests
        # for `/.well-known`.
        location ^~ /.well-known {
            # The rules in this block are an adaptation of the rules
            # in `.htaccess` that concern `/.well-known`.

            location = /.well-known/carddav { return 301 /remote.php/dav/; }
            location = /.well-known/caldav  { return 301 /remote.php/dav/; }

            location /.well-known/acme-challenge    { try_files $uri $uri/ =404; }
            location /.well-known/pki-validation    { try_files $uri $uri/ =404; }

            # Let Nextcloud's API for `/.well-known` URIs handle all other
            # requests by passing them to the front-end controller.
            return 301 /index.php$request_uri;
        }

        # Rules borrowed from `.htaccess` to hide certain paths from clients
        location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
        location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }

        # Ensure this block, which passes PHP files to the PHP process, is above the blocks
        # which handle static assets (as seen below). If this block is not declared first,
        # then Nginx will encounter an infinite rewriting loop when it prepends `/index.php`
        # to the URI, resulting in a HTTP 500 error response.
        location ~ \.php(?:$|/) {
            # Required for legacy support
            rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|ocs-provider\/.+|.+\/richdocumentscode(_arm64)?\/proxy) /index.php$request_uri;

            fastcgi_split_path_info ^(.+?\.php)(/.*)$;
            set $path_info $fastcgi_path_info;

            try_files $fastcgi_script_name =404;

            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $path_info;
            #fastcgi_param HTTPS on;

            fastcgi_param modHeadersAvailable true;         # Avoid sending the security headers twice
            fastcgi_param front_controller_active true;     # Enable pretty urls
            fastcgi_pass php-handler;

            fastcgi_intercept_errors on;
            fastcgi_request_buffering off;

            fastcgi_max_temp_file_size 0;
        }

        # Serve static files
        location ~ \.(?:css|js|mjs|svg|gif|ico|jpg|png|webp|wasm|tflite|map|ogg|flac)$ {
            try_files $uri /index.php$request_uri;
            add_header Cache-Control "public, max-age=15778463$asset_immutable";
            add_header Referrer-Policy                   "no-referrer"       always;
            add_header X-Content-Type-Options            "nosniff"           always;
            add_header X-Frame-Options                   "SAMEORIGIN"        always;
            add_header X-Permitted-Cross-Domain-Policies "none"              always;
            add_header X-Robots-Tag                      "noindex, nofollow" always;
            add_header X-XSS-Protection                  "1; mode=block"     always;
            access_log off;     # Optional: Don't log access to assets

            location ~ \.wasm$ {
                default_type application/wasm;
            }
        }

        location ~ \.(otf|woff2?)$ {
            try_files $uri /index.php$request_uri;
            expires 7d;         # Cache-Control policy borrowed from `.htaccess`
            access_log off;     # Optional: Don't log access to assets
        }

        # Rule borrowed from `.htaccess`
        location /remote {
            return 301 /remote.php$request_uri;
        }

        location / {
            try_files $uri $uri/ /index.php$request_uri;
        }
    }
}
 """

# ─── Menu and Configuration Prompts ───────────────────────────

def start_menu():
    """
    Displays a menu where the user first chooses the service (Nextcloud or Moodle)
    and then selects whether to install or update. The user can also specify the base path.
    """
    art = r"""
    _   __     __        _       __     ____             __                ________    ____
   / | / /__  / /_____  (_)___  / /_   / __ \____  _____/ /_____  _____   / ____/ /   /  _/
  /  |/ / _ \/ __/_  / / / __ \/ __/  / / / / __ \/ ___/ //_/ _ \/ ___/  / /   / /    / /  
 / /|  /  __/ /_  / /_/ / / / / /_   / /_/ / /_/ / /__/ ,< /  __/ /     / /___/ /____/ /   
/_/ |_/\___/\__/ /___/_/_/ /_/\__/  /_____/\____/\___/_/|_|\___/_/      \____/_____/___/   
    """
    console.print(art, style="bright_blue")
    service = prompt([{
        "type": "list",
        "name": "service",
        "message": "For which service would you like to perform the action?",
        "choices": ["Nextcloud"],
        "default": "Nextcloud"
    }])
    action = prompt([{
        "type": "list",
        "name": "action",
        "message": "Install or Update?",
        "choices": ["install", "update"],
        "default": "install"
    }])
    base_path = prompt_base_path()
    return service["service"], action["action"], base_path

def prompt_installation_settings():
    """
    Asks if automatic installation should be used and returns all necessary settings.
    """
    console.print("[bright_blue]Configuring services...[/bright_blue]")
    auto_install = Confirm.ask("[bright_green]Start automatic installation?[/bright_green]", default=True)

    if auto_install:
        return {
            "install_nextcloud": True,
            "install_postgres": True,
            "install_redis": True,
            "install_nginx": True,
            "postgres_password": generate_password(),
            "nextcloud_db_user": "nextcloud",
            "nextcloud_db_pass": generate_password(),
            "redis_pass": generate_password(),
            "nc_admin_user": "admin",
            "nc_admin_pass": generate_password(),
            # This value will later be replaced with the latest version.
            "nc_fpm_version": None,
        }
    else:
        install_postgres = Confirm.ask("[bright_green]Install PostgreSQL?[/bright_green]", default=True)
        install_redis    = Confirm.ask("[bright_green]Install Redis?[/bright_green]", default=True)
        install_nginx    = Confirm.ask("[bright_green]Install Nginx?[/bright_green]", default=True)
        if Confirm.ask("[bright_yellow]Generate random passwords?[/bright_yellow]", default=True):
            pg_pass = generate_password()
            nc_db_user = "nextcloud"
            nc_db_pass = generate_password()
            redis_pass = generate_password()
        else:
            pg_pass = Prompt.ask("[bright_yellow]Postgres password[/bright_yellow]")
            nc_db_user = Prompt.ask("[bright_yellow]Nextcloud DB user?[/bright_yellow]", default="nextcloud")
            nc_db_pass = Prompt.ask("[bright_yellow]Nextcloud DB password[/bright_yellow]")
            redis_pass = Prompt.ask("[bright_yellow]Redis password (optional)[/bright_yellow]", default="")
        nc_admin_user = Prompt.ask("[bright_yellow]Nextcloud admin user?[/bright_yellow]", default="admin")
        nc_admin_pass = Prompt.ask("[bright_yellow]Nextcloud admin password?[/bright_yellow]", default=generate_password())
        return {
            "install_nextcloud": True,
            "install_postgres": install_postgres,
            "install_redis": install_redis,
            "install_nginx": install_nginx,
            "postgres_password": pg_pass,
            "nextcloud_db_user": nc_db_user,
            "nextcloud_db_pass": nc_db_pass,
            "redis_pass": redis_pass,
            "nc_admin_user": nc_admin_user,
            "nc_admin_pass": nc_admin_pass,
            "nc_fpm_version": None,
        }

def prompt_nginx_ports():
    """Prompts for custom HTTP/HTTPS ports for Nginx."""
    console.print("\n[bright_blue]Configure Nginx ports...[/bright_blue]")
    nginx_http_port = "8080"
    nginx_https_port = "8443"
    #if Confirm.ask("[bright_blue]Adjust HTTP/HTTPS ports?[/bright_blue]", default=False):
       # nginx_http_port = Prompt.ask("[bright_yellow]HTTP port?[/bright_yellow]", default="8080")
        #nginx_https_port = Prompt.ask("[bright_yellow]HTTPS port?[/bright_yellow]", default="8443")
    return nginx_http_port, nginx_https_port

# ─── Compose Services Creation ──────────────────────────────────

def build_compose_services(settings, nginx_http_port, nginx_https_port, env_file, base_path):
    """
    Builds the dictionary for docker-compose.yml based on the settings.
    Volume paths are set relative to the base path.
    """
    services = {}

    # PostgreSQL Service
    if settings["install_postgres"]:
        postgres_versions = fetch_semver_versions(POSTGRES_REPO)
        if Confirm.ask("[bright_blue]Postgres: Do you want to select a version?[/bright_blue]", default=True):
            answer = prompt([{
                "type": "list",
                "name": "chosen",
                "message": "Select a PostgreSQL version:",
                "choices": postgres_versions,
                "default": postgres_versions[0] if postgres_versions else "unknown"
            }])
            pg_version = answer["chosen"]
        else:
            pg_version = postgres_versions[0] if postgres_versions else "unknown"
        console.print(f"[bright_green]Postgres version: {pg_version}[/bright_green]")
        pg_service = {
            "image": f"postgres:{pg_version}",
            "restart": "unless-stopped",
            "volumes": [f"{os.path.join(base_path, 'data', 'nc_postgres')}:/var/lib/postgresql/data:Z"],
            "env_file": [env_file],
            "healthcheck": postgres_healthcheck("nextcloud", "${POSTGRES_PASSWORD}")
        }
        pg_cname = maybe_container_name("postgres", pg_version)
        if pg_cname:
            pg_service["container_name"] = pg_cname
        services["nextcloud-postgres"] = pg_service

    # Redis Service
    if settings["install_redis"]:
        redis_versions = fetch_semver_versions(REDIS_REPO)
        if Confirm.ask("[bright_blue]Redis: Do you want to select a version?[/bright_blue]", default=True):
            answer = prompt([{
                "type": "list",
                "name": "chosen",
                "message": "Select a Redis version:",
                "choices": redis_versions,
                "default": redis_versions[0] if redis_versions else "unknown"
            }])
            redis_version = answer["chosen"]
        else:
            redis_version = redis_versions[0] if redis_versions else "unknown"
        console.print(f"[bright_green]Redis version: {redis_version}[/bright_green]")
        redis_service = {
            "image": f"redis:{redis_version}",
            "restart": "unless-stopped",
            "volumes": [f"{os.path.join(base_path, 'data', 'nc_redis')}:/data"],
            "env_file": [env_file],
            "command": ["redis-server", "--appendonly", "yes", "--requirepass", "${REDIS_PASS}"]
        }
        redis_cname = maybe_container_name("redis", redis_version)
        if redis_cname:
            redis_service["container_name"] = redis_cname
        services["nextcloud-redis"] = redis_service

    # Nextcloud-FPM Service
    if settings["install_nextcloud"]:
        if Confirm.ask("[bright_blue]Nextcloud-FPM: Do you want to select a version from the suggestions?[/bright_blue]", default=True):
            fpm_tags = fetch_nextcloud_fpm_versions()
            if not fpm_tags:
                console.print("[bright_red]No valid versions found – aborting update.[/bright_red]")
                settings["nc_fpm_version"] = "unknown"
            else:
                answer = prompt([{
                    "type": "list",
                    "name": "chosen",
                    "message": "Select a Nextcloud-FPM version:",
                    "choices": fpm_tags,
                    "default": fpm_tags[0]
                }])
                settings["nc_fpm_version"] = answer["chosen"]
        else:
            default_version = fetch_nextcloud_fpm_versions()
            settings["nc_fpm_version"] = default_version[0] if default_version else "unknown"
        nc_service = {
            "image": f"nextcloud:{settings['nc_fpm_version']}",
            "restart": "unless-stopped",
            "env_file": [env_file],
            "volumes": [
                f"{os.path.join(base_path, 'data', 'nc_html')}:/var/www/html:z",
                f"{os.path.join(base_path, 'data', 'nc_config')}:/var/www/html/config:z",
                f"{os.path.join(base_path, 'data', 'nc_custom_apps')}:/var/www/html/custom_apps:z",
                f"{os.path.join(base_path, 'data', 'nc_data')}:/var/www/html/data:z"
            ],
            "depends_on": {}
        }
        if settings["install_postgres"]:
            nc_service["depends_on"]["postgres"] = {"condition": "service_healthy"}
        if settings["install_redis"]:
            nc_service["depends_on"]["redis"] = {"condition": "service_started"}
        nc_cname = maybe_container_name("nextcloud-fpm", settings["nc_fpm_version"])
        if nc_cname:
            nc_service["container_name"] = nc_cname
        services["nextcloud-fpm"] = nc_service

    # Nginx Service
    if settings["install_nginx"]:
        nginx_versions = fetch_semver_versions(NGINX_REPO)
        if Confirm.ask("[bright_blue]Nginx: Do you want to select a version?[/bright_blue]", default=True):
            answer = prompt([{
                "type": "list",
                "name": "chosen",
                "message": "Select an Nginx version:",
                "choices": nginx_versions,
                "default": nginx_versions[0] if nginx_versions else "unknown"
            }])
            nginx_version = answer["chosen"]
        else:
            nginx_version = nginx_versions[0] if nginx_versions else "unknown"
        console.print(f"[bright_green]Nginx version: {nginx_version}[/bright_green]")
        nginx_service = {
            "build": os.path.join(base_path, "nextcloud-ngnix"),
            "restart": "unless-stopped",
            "env_file": [env_file],
            "ports": [f"{nginx_http_port}:80", f"{nginx_https_port}:443"],
            "volumes": [f"{os.path.join(base_path, 'data', 'nc_html')}:/var/www/html:z"],
            "image": "ghcr.io/nextcloud-cli/nextcloud-ngnix:latest",
            "depends_on": {}
        }
        if settings["install_nextcloud"]:
            nginx_service["depends_on"]["nextcloud-fpm"] = {"condition": "service_started"}
        nginx_cname = maybe_container_name("nginx", nginx_version)
        if nginx_cname:
            nginx_service["container_name"] = nginx_cname
        services["nextcloud-nginx"] = nginx_service

    # Cron Service for Nextcloud
    cron_service = {
        "container_name": maybe_container_name("nextcloud-cron", settings["nc_fpm_version"]),
        "image": f"nextcloud:{settings['nc_fpm_version']}",
        "restart": "always",
        "volumes": [f"{os.path.join(base_path, 'data', 'nc_html')}:/var/www/html:z"],
        "entrypoint": "/cron.sh",
        "depends_on": {
            "postgres": {"condition": "service_healthy"},
            "redis": {"condition": "service_started"}
        }
    }
    services["nextcloud-cron"] = cron_service

    return {"services": services}

# ─── Installation Process ─────────────────────────────────────────

def run_installation(base_path):
    """
    Executes the installation process:
      1. Reads settings.
      2. Configures services including version selection.
      3. Sets up the Nginx build folder and local directories.
      4. Creates docker-compose.yml and nextcloud.env.
      5. Starts the containers.
    """
    console.print("[bright_blue]🚀 Nextcloud-FPM Installation started[/bright_blue]\n")
    settings = prompt_installation_settings()
    nginx_http_port, nginx_https_port = prompt_nginx_ports()
    setup_nginx_build_folder(base_path)
    env_file = os.path.join(base_path, "nextcloud.env")
    console.print("[bright_blue]Creating docker-compose.yml...[/bright_blue]")
    compose_data = build_compose_services(settings, nginx_http_port, nginx_https_port, env_file, base_path)
    create_local_directories(base_path)
    write_compose_file(compose_data, base_path)
    create_env_file(
        env_file,
        settings["postgres_password"],
        settings["nextcloud_db_user"],
        settings["nextcloud_db_pass"],
        settings["redis_pass"],
        settings["nc_admin_user"],
        settings["nc_admin_pass"]
    )
    compose_file = os.path.join(base_path, "docker-compose.yml")
    if Confirm.ask("\n[bright_blue]Do you want to start the containers now?[/bright_blue]", default=True):
        console.print("[bright_blue]Starting containers...[/bright_blue]")
        try:
            subprocess.run(["docker-compose", "-f", compose_file, "up", "-d"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        except subprocess.CalledProcessError as err:
            console.print(f"[bright_red]Failed to start containers. Error: {err}[/bright_red]")
            return
        console.print("\n[bright_green]🚀 Containers started successfully![/bright_green]\n")
    console.print(f"[bright_green]Nextcloud Admin URL:[/bright_green] http://localhost:{nginx_http_port}")
    console.print(f"[bright_green]Nextcloud Admin User:[/bright_green] {settings['nc_admin_user']}")
    console.print(f"[bright_green]Nextcloud Admin Password:[/bright_green] {settings['nc_admin_pass']}")
    console.print("\n[bright_blue]Thank you for using Netzint CLI![/bright_blue]")

# ─── Update Process ───────────────────────────────────────────────

def detect_version(service_substring):
    """
    Detects the version of the running Nextcloud Docker image based on a substring
    in the container name (e.g., "nextcloud-fpm").
    """
    client = docker.from_env()
    try:
        for container in client.containers.list():
            if service_substring in container.name:
                image = container.attrs["Config"]["Image"]
                version = image.split(":")[-1]
                console.print(f"[bright_green]Version for '{service_substring}': {version}[/bright_green]")
                return version
        console.print(f"[bright_red]Container with '{service_substring}' not found![/bright_red]")
        return "unknown"
    except Exception as e:
        console.print(f"[bright_red]Error detecting version: {e}[/bright_red]")
        return "unknown"

def update_docker_compose_images(new_version, service, base_path):
    """
    Updates the image for the specified service (e.g., nextcloud-fpm or nextcloud-cron)
    in the docker-compose.yml (located in the base path) to new_version.
    """
    compose_file = os.path.join(base_path, "docker-compose.yml")
    try:
        with open(compose_file, "r") as file:
            compose_data = yaml.safe_load(file)
        if service in compose_data.get("services", {}):
            compose_data["services"][service]["image"] = f"nextcloud:{new_version}"
        with open(compose_file, "w") as file:
            yaml.dump(compose_data, file, default_flow_style=False)
        console.print(f"[bright_green]{service} updated to version {new_version} in docker-compose file.[/bright_green]")
    except Exception as e:
        console.print(f"[bright_red]Error updating docker-compose file for {service}: {e}[/bright_red]")

def wait_for_nextcloud_status():
    """
    Periodically checks Nextcloud status via HTTP and waits until Nextcloud is ready.
    The raw status output is not displayed.
    """
    status_ready = False
    console.print("[bright_blue]Waiting for Nextcloud to be ready...[/bright_blue]")
    while not status_ready:
        try:
            resp = requests.get("http://localhost:8080/status.php", timeout=10)
            if ('"installed":true' in resp.text and
                '"maintenance":false' in resp.text and
                '"needsDbUpgrade":false' in resp.text):
                status_ready = True
            else:
                time.sleep(30)
        except Exception:
            time.sleep(30)

def run_occ_commands(container_id):
    """Runs Nextcloud OCC commands inside the container."""
    try:
        subprocess.run(["docker", "exec", "--user", "www-data", "-it", container_id, "php", "occ", "db:add-missing-indices"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        time.sleep(60)
        subprocess.run(["docker", "exec", "--user", "www-data", "-it", container_id, "php", "occ", "maintenance:repair", "--include-expensive"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        time.sleep(60)
        subprocess.run(["docker", "exec", "--user", "www-data", "-it", container_id, "php", "occ", "upgrade"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    except subprocess.CalledProcessError as err:
        console.print(f"[bright_red]Error running OCC commands: {err}[/bright_red]")

def get_container_id(service_substring):
    """
    Returns the container ID for a container whose name contains the given substring.
    """
    client = docker.from_env()
    try:
        for container in client.containers.list():
            if service_substring in container.name:
                return container.id
        console.print(f"[bright_red]Container with '{service_substring}' not found![/bright_red]")
        return None
    except Exception as e:
        console.print(f"[bright_red]Error retrieving container ID: {e}[/bright_red]")
        return None

def run_update_process(base_path):
    """
    Executes the Nextcloud update process:
      1. Detects the currently installed version (by searching for "nextcloud-fpm").
      2. Builds the update path (only major updates).
      3. Asks whether to update to the latest version or to a specific target version.
         Note: Even when updating to a specific version, major upgrades are applied sequentially.
      4. Performs the update step-by-step with clear messages.
    """
    installed_version = detect_version("nextcloud-fpm")
    available_versions = fetch_nextcloud_fpm_versions()
    update_path = []
    try:
        for version in available_versions:
            if Version(version.replace("-fpm", "")) > Version(installed_version.replace("-fpm", "")):
                update_path.append(version)
    except Exception as e:
        console.print(f"[bright_red]Error comparing versions: {e}[/bright_red]")
        return

    if not update_path:
        console.print("[bright_green]No newer version available for update.[/bright_green]")
        return

    # Choose update mode
    update_mode = prompt([{
        "type": "list",
        "name": "mode",
        "message": "How would you like to update?",
        "choices": ["Update to the latest version", "Update to a specific version"],
        "default": "Update to the latest version"
    }])["mode"]

    if update_mode == "Update to a specific version":
        answer = prompt([{
            "type": "list",
            "name": "target",
            "message": "Select the target version for Nextcloud update:",
            "choices": update_path,
            "default": update_path[-1]
        }])
        target_version = answer["target"]
        # Filter update_path to only include versions up to the target
        update_path = [v for v in update_path if Version(v.replace("-fpm", "")) <= Version(target_version.replace("-fpm", ""))]
        console.print(f"[bright_blue]Update will proceed sequentially up to version {target_version}.[/bright_blue]")
    else:
        console.print("[bright_blue]Update will proceed sequentially up to the latest version.[/bright_blue]")

    # Sort the update path in ascending order (major-by-major update)
    update_path = sorted(update_path, key=lambda v: Version(v.replace("-fpm", "")))
    total_steps = len(update_path)
    if total_steps == 0:
        console.print("[bright_green]No update steps are required.[/bright_green]")
        return

    compose_file = os.path.join(base_path, "docker-compose.yml")
    step_counter = 1
    for next_version in update_path:
        console.rule(f"Update Step {step_counter} of {total_steps}: Upgrading to version {next_version}")
        print("[bright_blue]Stopping containers...[/bright_blue]")
        try:
            subprocess.run(["docker-compose", "-f", compose_file, "down"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        except subprocess.CalledProcessError as err:
            console.print(f"[bright_red]Failed to stop containers: {err}[/bright_red]")
            return
        time.sleep(30)
        update_docker_compose_images(next_version, "nextcloud-fpm", base_path)
        update_docker_compose_images(next_version, "nextcloud-cron", base_path)
        print("[bright_blue]Starting containers...[/bright_blue]")
        try:
            subprocess.run(["docker-compose", "-f", compose_file, "up", "-d"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        except subprocess.CalledProcessError as err:
            console.print(f"[bright_red]Failed to start containers: {err}[/bright_red]")
            return
        time.sleep(60)
        wait_for_nextcloud_status()
        container_id = get_container_id("nextcloud-fpm")
        if container_id is not None:
            run_occ_commands(container_id)
        else:
            console.print("[bright_red]Nextcloud-FPM container not found![/bright_red]")
        console.print(f"[bright_green]Update step {step_counter} completed: Nextcloud upgraded to version {next_version}.[/bright_green]")
        step_counter += 1

def update_additional_container(service_key, docker_repo, base_path):
    """
    Updates an additional container (e.g., Postgres, Redis, or Nginx):
      - Detects the currently installed version (based on the container name, e.g., "nextcloud-postgres")
      - Fetches the latest available version from Docker Hub
      - Asks if an update should be performed and then updates the service separately.
    """
    current = detect_version(f"nextcloud-{service_key}")
    versions = fetch_semver_versions(docker_repo)
    if not versions:
        console.print(f"[bright_red]No valid versions found for {service_key}.[/bright_red]")
        return
    latest_version = versions[0]
    if Version(latest_version) <= Version(current):
        console.print(f"[bright_green]{service_key.capitalize()} is already up-to-date (version {current}).[/bright_green]")
        return
    if Confirm.ask(f"[bright_blue]Do you want to update {service_key.capitalize()} from version {current} to {latest_version}?[/bright_blue]", default=True):
        compose_file = os.path.join(base_path, "docker-compose.yml")
        try:
            update_docker_compose_images(latest_version, f"nextcloud-{service_key}", base_path)
            subprocess.run(["docker-compose", "-f", compose_file, "up", "-d", f"nextcloud-{service_key}"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            console.print(f"[bright_green]{service_key.capitalize()} updated successfully to version {latest_version}.[/bright_green]")
        except subprocess.CalledProcessError as err:
            console.print(f"[bright_red]Failed to update {service_key.capitalize()}: {err}[/bright_red]")

def run_update(base_path):
    """
    Main function for the update process:
      1. First updates Nextcloud (as above).
      2. Then asks if additional containers (Postgres, Redis, Nginx) should be updated.
    """
    console.print("[bright_blue]🚀 Nextcloud Update Process started[/bright_blue]\n")
    run_update_process(base_path)
    if Confirm.ask("[bright_blue]Do you also want to update the additional containers (Postgres, Redis, Nginx)?[/bright_blue]", default=False):
        update_additional_container("postgres", POSTGRES_REPO, base_path)
        update_additional_container("redis", REDIS_REPO, base_path)
        update_additional_container("nginx", NGINX_REPO, base_path)
    console.print("\n[bright_blue]Update process completed. Thank you![/bright_blue]")

# ─── Main ───────────────────────────────────────────────────────

def main():
    service, action, base_path = start_menu()
    if service != "Nextcloud":
        console.print("[bright_yellow]Moodle functionality is not yet implemented.[/bright_yellow]")
        return
    if action == "install":
        run_installation(base_path)
    elif action == "update":
        run_update(base_path)
    else:
        console.print("[bright_yellow]Unknown action![/bright_yellow]")

if __name__ == "__main__":
    main()
