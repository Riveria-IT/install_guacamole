# Apache Guacamole – Installer (Docker + PostgreSQL)

Installiert **Apache Guacamole 1.6.x** in Docker (PostgreSQL + `guacd` + Web‑App).  
Getestet unter **Ubuntu 22.04 (Jammy)** – läuft im **Proxmox‑LXC** und auf **klassischen VMs**.

**URL:** `http://<HOST-IP>:8080/guacamole/`  
**Erstlogin:** `guacadmin / guacadmin` → **sofort ändern**

---

## ⚡️ Quickstart

### Einzeiler (lädt & startet direkt)

**curl**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Riveria-IT/install_guacamole/main/install_guacamole.sh)"
```

**wget**
```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/Riveria-IT/install_guacamole/main/install_guacamole.sh)"
```

### Mit Optionen (Beispiel)
```bash
DB_PASS='SehrSicher!2025_$' \
HOST_HTTP_PORT=8080 \
NUKE_IMAGES=1 \
ENABLE_UFW=0 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Riveria-IT/install_guacamole/main/install_guacamole.sh)"
```
> Alternativ ohne Pipe (Datei speichern → ausführen):
> ```bash
> wget -qO /tmp/install_guacamole.sh https://raw.githubusercontent.com/Riveria-IT/install_guacamole/main/install_guacamole.sh
> chmod +x /tmp/install_guacamole.sh
> DB_PASS='SehrSicher!2025_$' /tmp/install_guacamole.sh
> ```

---

## 🧰 Was das Script macht

1. **Clean‑Reinstall:** stoppt & löscht alte Container/Volumes/Netze sowie `/opt/guacamole` (optional Images mit `NUKE_IMAGES=1`).  
2. Installiert **Docker + Compose v2** aus dem offiziellen Docker‑Repository.  
3. Für LXC: setzt Registry‑Mirror, optional `fuse-overlayfs` (stabil in Containern).  
4. Schreibt den **Compose‑Stack**: `postgres:16`, `guacamole/guacd:1.6.x`, `guacamole/guacamole:1.6.x`.  
5. Importiert das **Guacamole‑DB‑Schema**.  
6. Prüft die Erreichbarkeit von `http://127.0.0.1:8080/guacamole/`.

**Umgebungsvariablen (alle optional – beim Aufruf setzen):**

- `DB_NAME` (default `guacamole_db`)  
- `DB_USER` (default `guac_user`)  
- `DB_PASS` (**bitte setzen**)  
- `HOST_HTTP_PORT` (default `8080`)  
- `NUKE_IMAGES=1` → Images zusätzlich löschen & frisch ziehen  
- `ENABLE_UFW=1` → UFW nur für LAN/WG öffnen (siehe unten)  
- `LAN_SUBNET` / `WG_SUBNET` → UFW‑Netze festlegen

---

## ✅ Voraussetzungen

### Proxmox **LXC‑Container** (empfohlen: *unprivileged*)

Auf dem **Proxmox‑Host** (CTID anpassen, z. B. `182`):
```bash
pct stop <CTID>
pct set  <CTID> -unprivileged 1 -features nesting=1,keyctl=1,fuse=1
pct start <CTID>
pct config <CTID> | grep -E 'unprivileged|features'  # Kontrolle
```

Im **Container**:
```bash
apt-get update
apt-get install -y fuse-overlayfs curl
```

> Der Installer setzt einen **Registry‑Mirror** (`https://mirror.gcr.io`) und nutzt – wenn möglich –
> `fuse-overlayfs` als Storage‑Treiber. Das ist in LXC‑Umgebungen meist zuverlässiger.

### **VM** (KVM/VMware/Hyper‑V)
Keine LXC‑Sonderfeatures nötig. Docker läuft mit Default‑Treiber (`overlay2`).  
Der Installer funktioniert identisch.

---

## 🔧 Bedienung

```bash
# Stack-Verzeichnis
cd /opt/guacamole

# Start / Stop
docker compose up -d
docker compose down

# Logs
docker compose logs --no-log-prefix guacamole | tail -n 100
docker compose logs --no-log-prefix postgres  | tail -n 100

# Update (Images neu ziehen & neu starten)
docker compose pull
docker compose up -d
```

---

## 🆘 Troubleshooting

### 1) `docker compose pull` → **503 Service Unavailable** (Docker Hub)
**Ursache:** Registry‑Aussetzer oder Rate‑Limit.  
**Fix (manuell; wird im Installer standardmäßig gesetzt):**
```bash
cat >/etc/docker/daemon.json <<'JSON'
{
  "registry-mirrors": ["https://mirror.gcr.io"],
  "storage-driver": "fuse-overlayfs"
}
JSON
systemctl daemon-reload
systemctl restart docker || service docker restart
docker info | egrep -A1 'Storage Driver|Registry Mirrors'
```
**Retry‑Pulls:**
```bash
cd /opt/guacamole
until docker pull postgres:16; do echo retry pg; sleep 10; done
until docker pull guacamole/guacd:1.6.0; do echo retry guacd; sleep 10; done
until docker pull guacamole/guacamole:1.6.0; do echo retry guac; sleep 10; done
```
**Optional:** `docker login` (senkt Rate‑Limits).  
**Fallback nur für Postgres (wenn Docker Hub hart zickt):**
```yaml
# /opt/guacamole/docker-compose.override.yml
services:
  postgres:
    image: ghcr.io/bitnami/postgresql:16
    environment:
      POSTGRESQL_DATABASE: "guacamole_db"
      POSTGRESQL_USERNAME: "guac_user"
      POSTGRESQL_PASSWORD: "ChangeMeSuperSafe123!"
```

### 2) Docker startet nach Änderung an `daemon.json` nicht (LXC)
**Symptome:** `Job for docker.service failed …`  
- Paket fehlt → `apt-get install -y fuse-overlayfs`  
- LXC‑Feature fehlt → auf Host `nesting=1,keyctl=1,fuse=1` aktivieren (s. oben).  
- Notlösung (ohne FUSE):  
  ```bash
  cat >/etc/docker/daemon.json <<'JSON'
  { "registry-mirrors": ["https://mirror.gcr.io"] }
  JSON
  systemctl restart docker || service docker restart
  ```

### 3) Guacamole zeigt „FEHLER“/Login scheitert
**Log:** `SCRAM-based authentication ... password is an empty string`  
**Ursache:** falsche/alte DB‑ENV‑Variablen. Ab 1.6.x **POSTGRESQL_*** verwenden:
```yaml
environment:
  POSTGRESQL_HOSTNAME: "postgres"
  POSTGRESQL_DATABASE: "guacamole_db"
  POSTGRESQL_USERNAME: "guac_user"
  POSTGRESQL_PASSWORD: "ChangeMeSuperSafe123!"
```
**DB‑Volume neu + Schema importieren (falls alte Creds drin waren):**
```bash
cd /opt/guacamole
docker compose down
docker volume rm guacamole_db || true   # Name kann je nach Compose <projekt>_db heißen
docker compose up -d postgres guacd
docker run --rm guacamole/guacamole:1.6.0 /opt/guacamole/bin/initdb.sh --postgresql \
  | docker exec -i guac-postgres psql -U guac_user -d guacamole_db
docker compose up -d guacamole
```

---

## 🔒 Sicherheit (nur LAN / WireGuard)

Optional **UFW** aktivieren, um Port 8080 nur für LAN/WG zu öffnen:
```bash
apt-get install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from 192.168.1.0/24 to any port 8080 proto tcp   # anpassen
ufw allow from 10.6.0.0/24     to any port 8080 proto tcp   # anpassen
ufw --force enable
```

---

## ℹ️ Hinweise
- Nach der Installation **Passwort von `guacadmin`** sofort ändern.
- TOTP‑2FA lässt sich im Benutzer‑Profil aktivieren.
- Lies dir Scripts vor produktivem Einsatz kurz durch.

---

## Lizenz
MIT (oder anpassen).
