#!/bin/bash
# Creates the Evolution API role + database on the FIRST boot of the postgres
# volume. Without this, Evolution crash-loops on a fresh install: setup.sh
# generates the connection URI, but nothing ever creates the role it points at.
#
# Runs only when /var/lib/postgresql/data is empty. On an EXISTING install it is
# ignored — to add the role by hand there, run:
#
#   docker compose exec postgres psql -U n8n -d n8n \
#     -c "CREATE USER evolution WITH PASSWORD '<EVOLUTION_DB_PASSWORD from .env>';" \
#     -c "CREATE DATABASE evolution OWNER evolution;"
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER evolution WITH PASSWORD '${EVOLUTION_DB_PASSWORD}';
    CREATE DATABASE evolution OWNER evolution;
    GRANT ALL PRIVILEGES ON DATABASE evolution TO evolution;
EOSQL

echo "[autokit] Evolution database and role created."
