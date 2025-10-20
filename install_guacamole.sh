#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

### ── Konfiguration ─────────────────────────────────────────────────────────────
DB_NAME="${DB_NAME:-guacamole_db}"
DB_USER="${DB_USER:-guac_user}"
DB_PASS="${DB_PASS:-ChangeMeSuperSafe123!}"
GUAC_VERSION="${GUAC_VERSION:-1.6.0}"
PG_VERSION="${PG_VERSION:-16}"
HOST_HTTP_PORT="${HOST_HTTP_PORT:-8080}"
STACK_DIR="${STACK_DIR:-/opt/guacamole}"
DRIVE_DIR="${DRIVE_DIR:-$STACK_DIR/data/drive}"
RECORD_DIR="${RECORD_DIR:-$STACK_DIR/data/record}"
NUKE_IMAGES="${NUKE_IMAGES:-0}"      # 1 = Images zusätzlich löschen
DOCKERHUB_USER="${DOCKERHUB_USER:-}" # optional: für docker login
DOCKERHUB_PASS="${DOCKERHUB_PASS:-}" # optional
### ─────────────────────────────────────────────────────────────────────────────

log(){ printf "\n[i] %s\n" "$*"; }
die(){ echo "[!] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Bitte als root ausführen."
. /etc/os-release || die "/etc/os-release fehlt"
[[ "${ID:-}" == "ubuntu" ]] || die "Script ist für Ubuntu. Gefunden: ${ID:-unbekannt}"
CODENAME="${UBUNTU_CODENAME:-jammy}"

# --- Helfer: robustes Pulling mit Backoff ---
pull_img() {
  local image="$1"; local tries="${2:-12}"
  for i in $(seq 1 "$tries"); do
    if docker pull "$image"; then return 0; fi
    echo "[i] Pull '$image' fehlgeschlagen (Versuch $i/$tries) – warte $((i*5))s…"
    sleep $((i*5))
  done
  return 1
}

################################################################################
# 1) SÄUBERN
################################################################################
log "Bestehende Guacamole-Stacks/Container/Volumes/Netze säubern…"
if command -v docker >/dev/null 2>&1; then
  if [ -d "$STACK_DIR" ] && [ -f "$STACK_DIR/docker-compose.yml" ] && docker compose version >/dev/null 2>&1; then
    ( cd "$STACK_DIR" && docker compose down -v --remove-orphans || true )
  fi
  docker rm -f guacamole guacd guac-postgres 2>/dev/null || true
  for net in $(docker network ls --format '{{.Name}}' | grep -E 'guac|guacamole' || true); do
    docker network rm "$net" 2>/dev/null || true
  done
  for vol in $(docker volume ls -q | grep -E 'guac|guacamole' || true); do
    docker volume rm -f "$vol" 2>/dev/null || true
  done
  if [[ "$NUKE_IMAGES" == "1" ]]; then
    for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'guacamole/|postgres' || true); do
      docker rmi -f "$img" 2>/dev/null || true
    done
  fi
fi
[[ "$STACK_DIR" == /opt/guacamole* ]] && rm -rf "$STACK_DIR"

################################################################################
# 2) DOCKER + COMPOSE (offizielles Repo) + LXC-Overlay-Fix
################################################################################
log "Basis-Pakete installieren…"
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release apt-transport-https

log "Offizielles Docker-Repo (non-interaktiv) hinzufügen…"
install -m 0755 -d /etc/apt/keyrings
rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --batch --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" > /etc/apt/sources.list.d/docker.list
apt-get update

log "Docker Engine + Buildx + Compose-Plugin installieren…"
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
  log "Fallback: docker.io aus Ubuntu-Repo installieren…"
  apt-get install -y docker.io || die "Docker-Installation fehlgeschlagen."
}
systemctl enable --now docker 2>/dev/null || service docker start || true

# Compose v2 sicherstellen (Fallback auf CLI-Plugin)
if ! docker compose version >/dev/null 2>&1; then
  log "Compose-Plugin fehlt – installiere CLI-Plugin manuell…"
  arch="$(uname -m)"; case "$arch" in
    x86_64) comp_arch="x86_64" ;; aarch64) comp_arch="aarch64" ;; armv7l) comp_arch="armv7" ;; armv6l) comp_arch="armv6" ;;
    *) die "Nicht unterstützte Architektur: $arch" ;;
  esac
  install -d -m 0755 /usr/local/lib/docker/cli-plugins
  curl -fL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${comp_arch}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# LXC Overlay-Fix
if ! docker info >/dev/null 2>&1; then
  log "Docker info schlägt fehl – aktiviere fuse-overlayfs (LXC-Workaround)…"
  apt-get install -y fuse-overlayfs
  mkdir -p /etc/docker
  cat >/etc/docker/daemon.json <<'JSON'
{"storage-driver":"fuse-overlayfs"}
JSON
  systemctl restart docker 2>/dev/null || service docker restart || true
  docker info >/dev/null 2>&1 || die "Docker läuft nicht. Prüfe LXC-Features: nesting,keyctl,fuse."
fi

# Optional: Docker-Hub Login (hebt Limits/anomalies mitunter auf)
if [[ -n "$DOCKERHUB_USER" && -n "$DOCKERHUB_PASS" ]]; then
  log "Docker Hub Login…"
  echo "$DOCKERHUB_PASS" | docker login --username "$DOCKERHUB_USER" --password-stdin || true
fi

################################################################################
# 3) STACK ANLEGEN
################################################################################
log "Ordner anlegen…"
mkdir -p "$STACK_DIR" "$DRIVE_DIR" "$RECORD_DIR"

compose="${STACK_DIR}/docker-compose.yml"
log "docker-compose.yml schreiben…"
cat >"$compose" <<YML
services:
  postgres:
    image: postgres:${PG_VERSION}
    container_name: guac-postgres
    environment:
      POSTGRES_DB: "${DB_NAME}"
      POSTGRES_USER: "${DB_USER}"
      POSTGRES_PASSWORD: "${DB_PASS}"
    volumes:
      - db:/var/lib/postgresql/data
    restart: unless-stopped
    networks: [guacnet]

  guacd:
    image: guacamole/guacd:${GUAC_VERSION}
    container_name: guacd
    volumes:
      - ${DRIVE_DIR}:/drive
      - ${RECORD_DIR}:/record
    restart: unless-stopped
    networks: [guacnet]

  guacamole:
    image: guacamole/guacamole:${GUAC_VERSION}
    container_name: guacamole
    depends_on:
      - guacd
      - postgres
    environment:
      GUACD_HOSTNAME: "guacd"
      POSTGRESQL_HOSTNAME: "postgres"
      POSTGRESQL_DATABASE: "${DB_NAME}"
      POSTGRESQL_USERNAME: "${DB_USER}"
      POSTGRESQL_PASSWORD: "${DB_PASS}"
      REMOTE_IP_VALVE_ENABLED: "true"
    ports:
      - "${HOST_HTTP_PORT}:8080"
    restart: unless-stopped
    networks: [guacnet]

volumes:
  db:

networks:
  guacnet:
    driver: bridge
YML

cd "$STACK_DIR"

log "Images mit Retry ziehen… (Docker Hub 503 abfangen)"
pull_img "postgres:${PG_VERSION}" || die "Konnte postgres:${PG_VERSION} nicht ziehen."
pull_img "guacamole/guacd:${GUAC_VERSION}" || die "Konnte guacamole/guacd:${GUAC_VERSION} nicht ziehen."
pull_img "guacamole/guacamole:${GUAC_VERSION}" || die "Konnte guacamole/guacamole:${GUAC_VERSION} nicht ziehen."

log "postgres/guacd starten…"
docker compose up -d postgres guacd

log "Warte auf Postgres-Bereitschaft…"
for i in $(seq 1 90); do
  if docker exec guac-postgres pg_isready -U "${DB_USER}" -d "${DB_NAME}" -h 127.0.0.1 >/dev/null 2>&1; then
    break
  fi
  sleep 2
  [[ $i -eq 90 ]] && die "Postgres nicht bereit. Logs: docker logs guac-postgres"
done

log "Guacamole-Schema importieren…"
docker run --rm guacamole/guacamole:${GUAC_VERSION} /opt/guacamole/bin/initdb.sh --postgresql \
  | docker exec -i guac-postgres psql -U "${DB_USER}" -d "${DB_NAME}"

log "Guacamole-Webapp starten…"
docker compose up -d guacamole

# Reachability-Check
sleep 2
apt-get install -y --no-install-recommends curl >/dev/null 2>&1 || true
curl -fsS "http://127.0.0.1:${HOST_HTTP_PORT}/guacamole/" >/dev/null || {
  docker compose logs --no-log-prefix guacamole | tail -n 120 || true
  die "Guacamole antwortet nicht auf http://127.0.0.1:${HOST_HTTP_PORT}/guacamole/ – siehe Logs oben."
}

IP="$(hostname -I | awk '{print $1}')"
echo
echo "✅ Guacamole bereit:"
echo "   URL:   http://${IP}:${HOST_HTTP_PORT}/guacamole/"
echo "   Login: guacadmin / guacadmin  (bitte direkt ändern)"
echo "   Drive: ${DRIVE_DIR}"
echo "   Record:${RECORD_DIR}"
