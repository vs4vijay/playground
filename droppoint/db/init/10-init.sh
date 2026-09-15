#!/bin/sh
# Runs once on first init of the postgres data dir.
set -e
if [ -z "$JWT_SECRET" ]; then
  echo "FATAL: JWT_SECRET env var is not set (see .env.example)" >&2
  exit 1
fi
# schema.sql lives outside initdb.d so the postgres entrypoint does not
# auto-run it a second time after this script.
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v ON_ERROR_STOP=1 -v jwt_secret="$JWT_SECRET" \
  -f /schema.sql
