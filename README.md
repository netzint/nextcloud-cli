Netzint CLI – Nextcloud Installation and Update Documentation
==============================================================

Version: 1.0
Erstellt am: 2025-03-13

--------------------------------------------------
Inhaltsverzeichnis
--------------------------------------------------
1. Überblick
2. Features
3. Systemvoraussetzungen
4. Installation und Setup
5. Nutzung der CLI
   5.1 Starten der CLI
   5.2 Installationsprozess
   5.3 Updateprozess
6. Konfiguration und Einstellungen
7. Code-Struktur & Entwicklerdokumentation
   7.1 Dateistruktur
   7.2 Wichtige Funktionen
   7.3 Externe Bibliotheken
   7.4 Erweiterungsmöglichkeiten
8. Fehlerbehebung und FAQ
9. Anhang
10. Lizenz und Mitwirkende
--------------------------------------------------

1. Überblick
------------
Netzint CLI ist ein Command-Line-Interface (CLI) Tool, das die Installation und Aktualisierung einer Nextcloud-FPM-Instanz in Kombination mit unterstützenden Services wie PostgreSQL, Redis und Nginx automatisiert. Die Anwendung verwendet Docker und Docker Compose, um alle Komponenten in Containern zu betreiben und bietet dabei:

- Automatisierte Einrichtung durch interaktive Prompts
- Versionierung: Automatisches Abrufen gültiger Docker-Image-Versionen von Docker Hub
- Konfigurationsgenerierung: Erstellung von docker-compose.yml und nextcloud.env
- Update-Mechanismus: Schrittweises Aktualisieren von Nextcloud auf neuere Versionen

2. Features
-----------
+ Automatische Installation:
  Führt den Nutzer durch einen geführten Einrichtungsprozess mit automatischer Generierung von Passwörtern und Konfigurationsdateien.
+ Version Management:
  Ruft gültige Versionen für Nextcloud-FPM, PostgreSQL, Redis und Nginx direkt von Docker Hub ab.
+ Docker Compose Integration:
  Erstellt und verwaltet die docker-compose.yml, um Container einfach zu starten und zu stoppen.
+ Updateprozess:
  Erkennt die aktuell installierte Version und ermöglicht ein schrittweises Update auf neue Major-Versionen.

3. Systemvoraussetzungen
------------------------
- Python 3.6+
- Docker & Docker Compose (müssen installiert und betriebsbereit sein)
- Internetverbindung (zum Abrufen von Docker Hub-Daten)
- Folgende Python-Bibliotheken:
  - requests
  - docker
  - PyYAML
  - InquirerPy
  - rich
  - packaging

4. Installation und Setup
-------------------------
1. Repository klonen oder herunterladen:
   git clone https://github.com/dein-benutzername/netzint-cli.git
   cd netzint-cli

2. Abhängigkeiten installieren:
   pip install -r requirements.txt

3. Docker starten:
   Stelle sicher, dass Docker und Docker Compose korrekt installiert und gestartet sind.

5. Nutzung der CLI
------------------
5.1 Starten der CLI
   Die Anwendung wird über den Befehl "ni-cli" gestartet. Nutze dazu:
      ./ni-cli
   Falls die Datei nicht ausführbar ist:
      python3 ni-cli.py

5.2 Installationsprozess
   Beim Starten der CLI erscheint ein Menü:
   - Service Auswahl:
     Aktuell wird nur Nextcloud unterstützt (Moodle ist noch in Entwicklung).
   - Aktion wählen:
     Wähle zwischen "Installation" und "Update".
   - Basisverzeichnis festlegen:
     Standardmäßig wird "./docker/nextcloud/" als Basispfad verwendet.
   - Interaktive Konfiguration:
     a) Automatische Installation:
        - Zufällig generierte Passwörter für PostgreSQL, Redis und den Nextcloud-Admin.
        - Anlage notwendiger lokaler Verzeichnisse.
        - Erstellung von Konfigurationsdateien (docker-compose.yml, nextcloud.env, Nginx-Konfiguration).
     b) Manuelle Konfiguration:
        - Eigene Passwörter und Einstellungen können eingegeben werden.
        - Versionen für PostgreSQL, Redis, Nextcloud-FPM und Nginx lassen sich manuell auswählen.

5.3 Updateprozess
   Der Updateprozess umfasst folgende Schritte:
   - Versionsdetektion:
     Das Tool erkennt die aktuell installierte Nextcloud-Version anhand des Container-Namens (enthält "nextcloud-fpm").
   - Updatepfad erstellen:
     Es wird ein Updatepfad für Major-Versionen zusammengestellt.
   - Versionsauswahl:
     Du kannst wählen, ob auf die neueste Version oder auf eine bestimmte Zielversion aktualisiert wird.
   - Schrittweises Update:
     * Container werden gestoppt.
     * Die docker-compose.yml wird angepasst.
     * Die Container werden neu gestartet.
     * Zwischen den Schritten erfolgt eine Wartezeit, um sicherzustellen, dass Nextcloud betriebsbereit ist.
     * Interne OCC-Befehle (Nextcloud-Befehle) aktualisieren die Datenbank und Konfiguration.
   - Zusätzliche Container:
     Optional können auch Updates für PostgreSQL, Redis und Nginx separat durchgeführt werden.

6. Konfiguration und Einstellungen
------------------------------------
Folgende Dateien werden generiert:
- docker-compose.yml:
  Enthält alle Service-Definitionen und Volume-Mappings.
  Beispiel:
    services:
      postgres:
        image: postgres:13
        volumes:
          - ./docker/nextcloud/data/nc_postgres:/var/lib/postgresql/data:Z
        env_file:
          - ./docker/nextcloud/nextcloud.env

- nextcloud.env:
  Speichert alle sensiblen Umgebungsvariablen (Datenbankpasswörter, Admin-Credentials etc.).
  Beispiel:
    POSTGRES_PASSWORD=dein_passwort
    NEXTCLOUD_DB_USER=nextcloud
    POSTGRES_USER=nextcloud
    POSTGRES_DB=nextcloud
    NEXTCLOUD_DB_PASSWORD=dein_passwort
    REDIS_PASS=dein_passwort
    NEXTCLOUD_ADMIN_USER=admin
    NEXTCLOUD_ADMIN_PASSWORD=dein_passwort
    POSTGRES_HOST=postgres
    REDIS_HOST=redis

- Nginx-Konfiguration:
  Befindet sich im Unterordner "app/" und besteht aus nginx.conf sowie einem einfachen Dockerfile.

- Portkonfiguration:
  Standardmäßig wird HTTP auf Port 8080 und HTTPS auf Port 8443 zugewiesen (sofern nicht anders festgelegt).

7. Code-Struktur & Entwicklerdokumentation
-------------------------------------------
7.1 Dateistruktur
   netzint-cli/
     ├── ni-cli.py                   # Hauptanwendung
     ├── README.md                   # Dokumentation (dieses Dokument)
     ├── requirements.txt            # Abhängigkeiten
     └── (weitere Konfigurations- und Supportdateien)

7.2 Wichtige Funktionen
   - Version Fetching:
     * fetch_nextcloud_fpm_versions(): Sammelt gültige Nextcloud-FPM-Versionen von Docker Hub.
     * fetch_semver_versions(): Ruft semantische Versionen für PostgreSQL, Redis und Nginx ab.
   - Konfigurationsdateien erstellen:
     * write_compose_file(): Schreibt die docker-compose.yml.
     * create_env_file(): Erzeugt die Datei nextcloud.env.
   - Service Management:
     * run_installation(): Führt den Installationsprozess durch.
     * run_update_process(): Steuert den Updateprozess für Nextcloud.
     * update_docker_compose_images(): Aktualisiert die Image-Versionen in der Compose-Datei.
   - Hilfsfunktionen:
     * generate_password(): Erstellt sichere Zufallspasswörter.
     * maybe_container_name(): Generiert Container-Namen basierend auf dem Servicenamen und der Version.

7.3 Externe Bibliotheken
   Bibliothek      Zweck
   ------------- -----------------------------------------------------------
   requests      HTTP-Anfragen zum Abrufen von Docker Hub-Daten
   docker        Interaktion mit der Docker Engine
   PyYAML        Lesen und Schreiben von YAML-Dateien
   InquirerPy    Interaktive CLI-Prompts
   rich          Formatierte Konsolenausgaben
   packaging     Vergleich und Validierung von Versionsnummern

7.4 Erweiterungsmöglichkeiten
   - Neue Services hinzufügen:
     Beispiel: Unterstützung von Moodle anhand der Implementierung von Nextcloud in build_compose_services().
   - Anpassung der Prompts:
     Zusätzliche Konfigurationsoptionen können in prompt_installation_settings() integriert werden.
   - Erweiterung des Updateprozesses:
     Verfeinerung des Update-Workflows durch weitere Prüfungen oder Anpassungen.

8. Fehlerbehebung und FAQ
--------------------------
Probleme                     Mögliche Ursache                           Lösung
-------------------------    -----------------------------------------    -------------------------------------------
Container startet nicht      Falsche Konfiguration / fehlende Verzeichnisse   Überprüfe die docker-compose.yml und Dateirechte
Fehler beim Versionsabruf    Netzwerkprobleme oder API-Änderungen         Prüfe die Internetverbindung und aktualisiere Timeouts
Berechtigungsprobleme        Fehlende Zugriffsrechte                      Stelle sicher, dass der Benutzer ausreichende Rechte besitzt

FAQ:
Q: Was tun, wenn der Updateprozess fehlschlägt?
A: Lies die Konsolenausgabe, prüfe die Log-Dateien und stelle sicher, dass alle Abhängigkeiten (Docker, Docker Compose) aktuell sind.

9. Anhang
---------
Beispiel-Codeausschnitt: Update der Docker Compose Images

def update_docker_compose_images(new_version, service, base_path):
    """
    Aktualisiert den Image-Eintrag in der docker-compose.yml für den angegebenen Service.
    """
    compose_file = os.path.join(base_path, "docker-compose.yml")
    with open(compose_file, "r") as file:
        compose_data = yaml.safe_load(file)
    if service in compose_data.get("services", {}):
        compose_data["services"][service]["image"] = f"nextcloud:{new_version}"
    with open(compose_file, "w") as file:
        yaml.dump(compose_data, file, default_flow_style=False)

10. Lizenz und Mitwirkende
---------------------------
Dieses Projekt steht unter der MIT-Lizenz. Beiträge und Feedback sind jederzeit willkommen.
Für Fehlerberichte oder Feature-Wünsche bitte ein Issue im Repository eröffnen.

--------------------------------------------------
Vielen Dank, dass du den Netzint CLI nutzt!
Für weitere Fragen oder Unterstützung konsultiere bitte auch die Inline-Kommentare im Quellcode.
--------------------------------------------------
