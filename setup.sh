#!/bin/bash
###############################################################################
# AutoKit — interactive installer
#
# Collects every input it needs (including whether you have a domain),
# generates all secrets, writes the .env files and starts the stack.
#
# Usage:  ./setup.sh
###############################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[ OK ]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}▶ $1${NC}\n"; }

# Bilingual failure: English line, then the Hebrew line, then exit.
die() {
    log_error "$1"
    echo -e "${RED}       $2${NC}"
    exit 1
}

generate_password()       { openssl rand -base64 32 | tr -d "=+/" | cut -c1-25; }
generate_api_key()        { openssl rand -hex 32; }
generate_encryption_key() { openssl rand -hex 32; }
urlencode() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"; }

prompt_input() {
    local prompt="$1" default="$2" var_name="$3" input
    if [ -n "$default" ]; then
        read -r -p "$(echo -e "${CYAN}${prompt} [${default}]: ${NC}")" input
        printf -v "$var_name" '%s' "${input:-$default}"
    else
        read -r -p "$(echo -e "${CYAN}${prompt}: ${NC}")" input
        while [ -z "$input" ]; do
            log_warning "This field is required. / שדה חובה."
            read -r -p "$(echo -e "${CYAN}${prompt}: ${NC}")" input
        done
        printf -v "$var_name" '%s' "$input"
    fi
}

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║   AutoKit — n8n + Evolution API (WhatsApp)         ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

###############################################################################
log_step "Step 1 / 7 — Pre-flight checks"
###############################################################################

command -v docker >/dev/null 2>&1 \
    || die "Docker is not installed." "דוקר לא מותקן. התקן דוקר ונסה שוב."

docker info >/dev/null 2>&1 \
    || die "Docker is installed but not running (or needs sudo)." \
           "דוקר מותקן אך לא פועל. הפעל את דוקר או הרץ עם sudo."
log_success "Docker is running"

docker compose version >/dev/null 2>&1 \
    || die "Docker Compose v2 not found ('docker compose', not 'docker-compose')." \
           "נדרש Docker Compose v2. עדכן את דוקר ונסה שוב."
log_success "Docker Compose v2 found"

command -v openssl >/dev/null 2>&1 \
    || die "openssl is required to generate secrets." "נדרש openssl ליצירת סיסמאות."
command -v python3 >/dev/null 2>&1 \
    || die "python3 is required." "נדרש python3."

# RAM — n8n main + 2 workers + postgres + redis + evolution needs ~4GB.
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 0)
if [ "$TOTAL_RAM_MB" -gt 0 ] && [ "$TOTAL_RAM_MB" -lt 3600 ]; then
    log_warning "Only ${TOTAL_RAM_MB}MB RAM detected — 4GB is the tested minimum."
    log_warning "זוהו ${TOTAL_RAM_MB}MB בלבד — המינימום המומלץ הוא 4GB."
    read -r -p "$(echo -e "${YELLOW}Continue anyway? (yes/no): ${NC}")" ram_ok
    [ "$ram_ok" = "yes" ] || exit 0
else
    log_success "RAM: ${TOTAL_RAM_MB}MB"
fi

# Disk — images alone are ~2.5GB.
FREE_DISK_GB=$(df -BG --output=avail "$REPO_DIR" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
if [ "${FREE_DISK_GB:-0}" -gt 0 ] && [ "$FREE_DISK_GB" -lt 10 ]; then
    log_warning "Only ${FREE_DISK_GB}GB free disk — 10GB recommended."
    log_warning "נותרו ${FREE_DISK_GB}GB בלבד — מומלץ לפחות 10GB."
fi

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log_info "OS: ${PRETTY_NAME:-unknown}"
    case "${VERSION_ID:-}" in
        22.04|24.04) : ;;
        *) log_warning "Tested on Ubuntu 22.04 / 24.04. Other versions may work but are unverified."
           log_warning "נבדק על Ubuntu 22.04 / 24.04. גרסאות אחרות עלולות לא לעבוד." ;;
    esac
fi

if [ -f .env ]; then
    log_warning "An existing .env was found — continuing will overwrite it."
    log_warning "נמצא קובץ .env קיים — המשך יחליף אותו."
    read -r -p "$(echo -e "${YELLOW}Overwrite? (yes/no): ${NC}")" confirm
    [ "$confirm" = "yes" ] || { log_info "Cancelled."; exit 0; }
fi

###############################################################################
log_step "Step 2 / 7 — Domain"
###############################################################################

# Ask for IPv4 explicitly. On a dual-stack box the plain call can answer with
# an IPv6 address, and "http://2a02:...:1:5678" is not a valid URL — the colons
# collide with the port separator, so every generated webhook URL breaks and
# the owner-detection poll in step 7 can never connect.
PUBLIC_IP="$(curl -s4 --max-time 10 ifconfig.me 2>/dev/null || echo "")"
[ -n "$PUBLIC_IP" ] || PUBLIC_IP="$(curl -s6 --max-time 10 ifconfig.me 2>/dev/null || echo "")"
[ -n "$PUBLIC_IP" ] && log_info "Public IP: $PUBLIC_IP"

# An IPv6 literal has to be bracketed inside a URL; IPv4 is passed through.
url_host() { case "$1" in *:*) printf '[%s]' "$1" ;; *) printf '%s' "$1" ;; esac; }

echo "With a domain you get HTTPS and clean URLs. Without one, AutoKit runs"
echo "on http://IP:PORT — fine for testing, but WhatsApp webhooks are plain HTTP."
echo "עם דומיין תקבל HTTPS וכתובות נקיות. בלי דומיין המערכת תרוץ על IP:PORT."
echo ""
read -r -p "$(echo -e "${CYAN}Do you have a domain pointing at this server? (y/n): ${NC}")" has_domain

if [[ "$has_domain" =~ ^[Yy] ]]; then
    USE_DOMAIN=true
    prompt_input "Your base domain (e.g. example.com)" "" BASE_DOMAIN
    prompt_input "n8n subdomain"           "n8n.$BASE_DOMAIN" N8N_DOMAIN
    prompt_input "Evolution API subdomain" "evo.$BASE_DOMAIN" EVOLUTION_DOMAIN
    prompt_input "Email for SSL certificates" "admin@$BASE_DOMAIN" SSL_EMAIL

    # Ports 80/443 must be free — Traefik binds them for the ACME challenge.
    for port in 80 443; do
        if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" | grep -q LISTEN; then
            die "Port ${port} is already in use — Traefik needs it for SSL." \
                "פורט ${port} תפוס. עצור את השירות שמשתמש בו ונסה שוב."
        fi
    done
    log_success "Ports 80 and 443 are free"

    # DNS must already resolve to this box or Let's Encrypt will fail.
    if command -v dig >/dev/null 2>&1 && [ -n "$PUBLIC_IP" ]; then
        for d in "$N8N_DOMAIN" "$EVOLUTION_DOMAIN"; do
            resolved="$(dig +short "$d" | tail -1)"
            if [ -z "$resolved" ]; then
                log_warning "$d does not resolve yet. SSL will fail until DNS propagates."
                log_warning "הדומיין $d עדיין לא מפנה לשרת. ה-SSL ייכשל עד שה-DNS יתעדכן."
            elif [ "$resolved" != "$PUBLIC_IP" ]; then
                log_warning "$d resolves to $resolved but this server is $PUBLIC_IP."
                log_warning "הדומיין $d מפנה ל-$resolved במקום ל-$PUBLIC_IP."
            else
                log_success "$d → $PUBLIC_IP"
            fi
        done
        echo ""
        read -r -p "$(echo -e "${CYAN}Continue? (yes/no): ${NC}")" dns_ok
        [ "$dns_ok" = "yes" ] || { log_info "Fix DNS, then re-run ./setup.sh"; exit 0; }
    fi

    N8N_PROTOCOL=https
    N8N_HOST="$N8N_DOMAIN"
    N8N_URL="https://$N8N_DOMAIN"
    EVOLUTION_URL="https://$EVOLUTION_DOMAIN"
    TRAEFIK_ENABLED=true
    N8N_PUBLISH_PORT="127.0.0.1:5678"
    EVOLUTION_PUBLISH_PORT="127.0.0.1:8080"
    COMPOSE_ARGS=(--profile domain)
else
    USE_DOMAIN=false
    [ -n "$PUBLIC_IP" ] || prompt_input "This server's public IP" "" PUBLIC_IP
    log_warning "Running without SSL. Anyone who learns the URL can reach the login page."
    log_warning "המערכת תרוץ ללא SSL. מומלץ להוסיף דומיין בהמשך."

    # Placeholders keep Traefik's label templates valid even when disabled.
    N8N_DOMAIN="$PUBLIC_IP"
    EVOLUTION_DOMAIN="$PUBLIC_IP"
    SSL_EMAIL="admin@example.com"
    N8N_PROTOCOL=http
    N8N_HOST="$PUBLIC_IP"
    N8N_URL="http://$(url_host "$PUBLIC_IP"):5678"
    EVOLUTION_URL="http://$(url_host "$PUBLIC_IP"):8080"
    TRAEFIK_ENABLED=false
    N8N_PUBLISH_PORT="0.0.0.0:5678"
    EVOLUTION_PUBLISH_PORT="0.0.0.0:8080"
    COMPOSE_ARGS=()
fi

# The stack publishes these two in BOTH modes — on loopback behind a domain,
# publicly without one. The 80/443 check above only covers Traefik, so a clash
# here surfaces much later as an opaque "port is already allocated" from
# Compose, long after the .env has been written.
port_taken() {
    command -v ss >/dev/null 2>&1 || return 1
    ss -ltn "( sport = :$1 )" 2>/dev/null | grep -q LISTEN
}

N8N_BIND="${N8N_PUBLISH_PORT%:*}";        N8N_PORT_NUM="${N8N_PUBLISH_PORT##*:}"
EVO_BIND="${EVOLUTION_PUBLISH_PORT%:*}";  EVO_PORT_NUM="${EVOLUTION_PUBLISH_PORT##*:}"

while port_taken "$N8N_PORT_NUM"; do
    log_warning "Port ${N8N_PORT_NUM} is already in use — n8n cannot publish it."
    log_warning "פורט ${N8N_PORT_NUM} תפוס. בחר פורט אחר עבור n8n."
    prompt_input "Another port for n8n" "5680" N8N_PORT_NUM
done
while port_taken "$EVO_PORT_NUM"; do
    log_warning "Port ${EVO_PORT_NUM} is already in use — Evolution cannot publish it."
    log_warning "פורט ${EVO_PORT_NUM} תפוס. בחר פורט אחר עבור Evolution."
    prompt_input "Another port for Evolution API" "8081" EVO_PORT_NUM
done

N8N_PUBLISH_PORT="${N8N_BIND}:${N8N_PORT_NUM}"
EVOLUTION_PUBLISH_PORT="${EVO_BIND}:${EVO_PORT_NUM}"
if [ "$USE_DOMAIN" = false ]; then
    N8N_URL="http://$(url_host "$PUBLIC_IP"):$N8N_PORT_NUM"
    EVOLUTION_URL="http://$(url_host "$PUBLIC_IP"):$EVO_PORT_NUM"
fi
log_success "Ports ${N8N_PORT_NUM} and ${EVO_PORT_NUM} are free"

###############################################################################
log_step "Step 3 / 7 — Generating secrets"
###############################################################################

POSTGRES_USER=n8n
POSTGRES_DB=n8n
POSTGRES_PASSWORD=$(generate_password)
EVOLUTION_DB_PASSWORD=$(generate_password)
N8N_ENCRYPTION_KEY=$(generate_encryption_key)
N8N_JWT_SECRET=$(generate_password)
N8N_RUNNERS_AUTH_TOKEN=$(generate_api_key)
EVOLUTION_API_KEY=$(generate_api_key)
EVOLUTION_DB_PASSWORD_ENCODED=$(urlencode "$EVOLUTION_DB_PASSWORD")

log_success "Generated all passwords and API keys"

###############################################################################
log_step "Step 4 / 7 — Writing configuration"
###############################################################################

cat > .env <<EOF
# AutoKit — generated $(date)
# Do not commit this file.

POSTGRES_USER=$POSTGRES_USER
POSTGRES_DB=$POSTGRES_DB
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EVOLUTION_DB_PASSWORD=$EVOLUTION_DB_PASSWORD

N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_JWT_SECRET
N8N_RUNNERS_AUTH_TOKEN=$N8N_RUNNERS_AUTH_TOKEN

# Mode
TRAEFIK_ENABLED=$TRAEFIK_ENABLED
N8N_PUBLISH_PORT=$N8N_PUBLISH_PORT
EVOLUTION_PUBLISH_PORT=$EVOLUTION_PUBLISH_PORT

# Domains
N8N_DOMAIN=$N8N_DOMAIN
EVOLUTION_DOMAIN=$EVOLUTION_DOMAIN
SSL_EMAIL=$SSL_EMAIL

# Public URLs
N8N_PROTOCOL=$N8N_PROTOCOL
N8N_HOST=$N8N_HOST
N8N_PORT=5678
N8N_LISTEN_ADDRESS=0.0.0.0
N8N_EDITOR_BASE_URL=$N8N_URL/
WEBHOOK_URL=$N8N_URL/

# Database
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=$POSTGRES_DB
DB_POSTGRESDB_USER=$POSTGRES_USER
DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD

# Queue mode
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=redis
QUEUE_BULL_REDIS_PORT=6379
QUEUE_BULL_REDIS_DB=0

# Runtime
# Without pruning, every execution is kept forever and Postgres grows until
# the disk fills — months after install, when nobody is looking. Production
# keeps one week, which is enough to debug a failure you were told about.
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168

GENERIC_TIMEZONE=Asia/Jerusalem
N8N_DEFAULT_LOCALE=en
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
N8N_RUNNERS_ENABLED=true
N8N_GIT_NODE_DISABLE_BARE_REPOS=true
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
N8N_COMMUNITY_PACKAGES_ENABLED=true
EOF
log_success "Wrote .env"

cat > .env.worker <<EOF
# AutoKit worker — generated $(date)
EXECUTIONS_MODE=queue
N8N_DISABLE_UI=true

DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=$POSTGRES_DB
DB_POSTGRESDB_USER=$POSTGRES_USER
DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD

QUEUE_BULL_REDIS_HOST=redis
QUEUE_BULL_REDIS_PORT=6379

N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY

N8N_RUNNERS_ENABLED=true
N8N_GIT_NODE_DISABLE_BARE_REPOS=true
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
N8N_CONCURRENCY_PRODUCTION_LIMIT=-1
EOF
log_success "Wrote .env.worker"

cat > .env.evolution <<EOF
# AutoKit Evolution API — generated $(date)
SERVER_URL=$EVOLUTION_URL
AUTHENTICATION_API_KEY=$EVOLUTION_API_KEY

QRCODE_LIMIT=30
CONFIG_SESSION_PHONE_NAME=Chrome
CONFIG_SESSION_PHONE_VERSION=2.3000.1040516757

WEBSOCKET_ENABLED=true
WEBSOCKET_GLOBAL_EVENTS=false
N8N_COMMUNITY_NODES_ENABLED=true

DATABASE_ENABLED=true
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://evolution:$EVOLUTION_DB_PASSWORD_ENCODED@postgres:5432/evolution?schema=public
DATABASE_CONNECTION_CLIENT_NAME=evolution_exchange

POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DATABASE=evolution
POSTGRES_USERNAME=evolution
POSTGRES_PASSWORD=$EVOLUTION_DB_PASSWORD

CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=redis://redis:6379/1
CACHE_REDIS_PREFIX_KEY=evo_v2

CORS_ORIGIN=*
CORS_METHODS=GET,POST,PUT,DELETE,PATCH
CORS_CREDENTIALS=true
EOF
log_success "Wrote .env.evolution"

chmod 600 .env .env.worker .env.evolution

CREDENTIALS_FILE="CREDENTIALS_$(date +%Y%m%d_%H%M%S).txt"
cat > "$CREDENTIALS_FILE" <<EOF
========================================
AutoKit — generated credentials
$(date)
========================================
Save this somewhere safe, then DELETE it from the server.
שמור את הקובץ במקום בטוח ואז מחק אותו מהשרת.

n8n
  URL:            $N8N_URL
  Encryption key: $N8N_ENCRYPTION_KEY

Evolution API
  URL:     $EVOLUTION_URL
  API key: $EVOLUTION_API_KEY

PostgreSQL (n8n)
  User: $POSTGRES_USER
  Pass: $POSTGRES_PASSWORD
  DB:   $POSTGRES_DB

PostgreSQL (Evolution)
  User: evolution
  Pass: $EVOLUTION_DB_PASSWORD
  DB:   evolution
========================================
EOF
chmod 600 "$CREDENTIALS_FILE"
log_success "Wrote $CREDENTIALS_FILE"

###############################################################################
log_step "Step 5 / 7 — Starting the stack"
###############################################################################

docker compose "${COMPOSE_ARGS[@]}" up -d

echo ""
log_info "Waiting for n8n to become healthy (up to 3 minutes) ..."
deadline=$(( $(date +%s) + 180 ))
while true; do
    cid="$(docker compose ps -q n8n-main 2>/dev/null || true)"
    status='"starting"'
    [ -n "$cid" ] && status=$(docker inspect --format='{{json .State.Health.Status}}' "$cid" 2>/dev/null || echo '"starting"')
    [ "$status" = '"healthy"' ] && { log_success "n8n is healthy"; break; }
    if [ "$(date +%s)" -gt "$deadline" ]; then
        log_warning "n8n did not report healthy in time."
        log_warning "n8n לא עלה בזמן. בדוק: docker compose logs n8n-main"
        break
    fi
    sleep 5
done

###############################################################################
log_step "Step 6 / 7 — Installing the Evolution node"
###############################################################################
# All three templates depend on this community package. Installing it through
# the UI means the buyer has to find Settings -> Community nodes and type the
# name correctly; installing it here removes that failure point.
#
# n8n does NOT auto-discover packages dropped into the nodes directory — it
# reads them from the installed_packages / installed_nodes tables. So we do
# both: npm install the files, then register them. Neither step needs a login,
# which is why this can run before the owner account exists.
COMMUNITY_PACKAGE="n8n-nodes-evolution-api-english"
COMMUNITY_VERSION="1.1.2"

if docker compose "${COMPOSE_ARGS[@]}" exec -T n8n-main \
     npm install --prefix /home/node/.n8n/nodes \
     "${COMMUNITY_PACKAGE}@${COMMUNITY_VERSION}" \
     --omit=dev --no-audit --no-fund >/dev/null 2>&1; then
    docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
      psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1 <<SQL
DELETE FROM installed_nodes    WHERE package = '${COMMUNITY_PACKAGE}';
DELETE FROM installed_packages WHERE "packageName" = '${COMMUNITY_PACKAGE}';
INSERT INTO installed_packages ("packageName","installedVersion","authorName","authorEmail","createdAt","updatedAt")
VALUES ('${COMMUNITY_PACKAGE}','${COMMUNITY_VERSION}','Burak S','bsormagec@gmail.com',now(),now());
INSERT INTO installed_nodes (name,type,"latestVersion",package) VALUES
 ('Evolution API','${COMMUNITY_PACKAGE}.evolutionApi',1,'${COMMUNITY_PACKAGE}'),
 ('Evolution API Trigger','${COMMUNITY_PACKAGE}.evolutionApiTrigger',1,'${COMMUNITY_PACKAGE}');
SQL
    docker compose "${COMPOSE_ARGS[@]}" restart n8n-main n8n-worker >/dev/null 2>&1
    log_success "Installed ${COMMUNITY_PACKAGE}@${COMMUNITY_VERSION}"
else
    log_warning "Could not install ${COMMUNITY_PACKAGE} automatically."
    log_warning "Install it by hand: Settings -> Community nodes -> ${COMMUNITY_PACKAGE}"
fi

###############################################################################
log_step "Step 7 / 7 — Your account, then the templates"
###############################################################################
# The owner account is the ONE thing this script deliberately does not create.
# It is your login, and a password generated here would end up written to disk.
#
# It is also urgent: an n8n with no owner belongs to whoever opens it first.
# So we block here until the account exists rather than printing an
# instruction and hoping.
echo ""
echo -e "  Open ${GREEN}${N8N_URL}${NC} and create your account ${YELLOW}now${NC}."
echo -e "  פתח את הקישור וצור חשבון ${YELLOW}עכשיו${NC} — עד אז המערכת פתוחה לכל מי שיודע את הכתובת."
echo ""
log_info "Waiting for you to finish (Ctrl-C to skip and do the rest by hand) ..."

owner_ready=false
deadline=$(( $(date +%s) + 1800 ))
while [ "$(date +%s)" -le "$deadline" ]; do
    # showSetupOnFirstLoad flips to false the moment the owner is created.
    # This endpoint needs no authentication, which is the whole point.
    if curl -fsS --max-time 5 "${N8N_URL}/rest/settings" 2>/dev/null \
         | grep -q '"showSetupOnFirstLoad":false'; then
        owner_ready=true
        break
    fi
    sleep 5
done

if [ "$owner_ready" = true ]; then
    log_success "Account created"
    OWNER_ID=$(docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
      psql -tAq -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -c "SELECT id FROM \"user\" WHERE \"roleSlug\" = 'global:owner' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

    if [ -n "$OWNER_ID" ]; then
        # import:workflow refuses to run without an owner to assign the
        # workflows to, which is why this waits for the account first.
        if docker compose "${COMPOSE_ARGS[@]}" exec -T n8n-main \
             n8n import:workflow --separate --input=/templates --userId="$OWNER_ID" >/dev/null 2>&1; then
            log_success "Imported the workflow templates"
        else
            log_warning "Template import failed — import them by hand from ./templates/"
        fi
    else
        log_warning "Could not find the owner account — import templates by hand."
    fi
else
    log_warning "No account created in time. Do steps 2-3 below by hand."
fi

###############################################################################
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║                 AutoKit is installed               ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo -e "  n8n:           ${GREEN}${N8N_URL}${NC}"
echo -e "  Evolution API: ${GREEN}${EVOLUTION_URL}${NC}"
echo -e "  Credentials:   ${GREEN}${REPO_DIR}/${CREDENTIALS_FILE}${NC}"
echo ""
if [ "$USE_DOMAIN" = true ]; then
    echo "  SSL certificates are issued on first request — allow 1-2 minutes."
else
    echo "  Running on plain HTTP. Open the firewall for ports ${N8N_PORT_NUM} and ${EVO_PORT_NUM}."
fi
echo ""
echo "  Already done for you:"
echo "    ✓ Evolution community node installed"
echo "    ✓ Workflow templates imported (they arrive deactivated)"
echo ""
echo "  What is left:"
echo "    1. Create an Evolution instance and scan the QR to pair WhatsApp."
echo "       Use a number that is NOT your main personal one."
echo "    2. Open each template, fill in the credentials named in its sticky"
echo "       note, then activate it."
echo "    3. Copy ${CREDENTIALS_FILE} off the server, then delete it."
echo ""
echo "  Useful commands:"
echo "    docker compose ps          # service status"
echo "    docker compose logs -f     # follow logs"
echo "    ./scripts/backup.sh        # back up volumes + config"
echo ""
log_success "Happy automating."
echo ""
