#!/bin/sh
set -e

# Generate a random SECRET_KEY_BASE if not set
if [ -z "$SECRET_KEY_BASE" ]; then
  export SECRET_KEY_BASE=$(openssl rand -base64 48)
  echo "[entrypoint] Generated random SECRET_KEY_BASE"
fi

# Wait for the database to accept connections (belt-and-suspenders on top of
# Docker healthchecks — pg_isready can return 0 before the server is fully
# ready to handle queries).
if [ -n "$DATABASE_URL" ]; then
  echo "[entrypoint] Waiting for database..."
  retries=0
  max_retries=30
  until /app/bin/zentinel_cp eval "ZentinelCp.Release.migrate()" 2>/dev/null; do
    retries=$((retries + 1))
    if [ "$retries" -ge "$max_retries" ]; then
      echo "[entrypoint] Database not ready after ${max_retries} attempts, running migration anyway..."
      /app/bin/zentinel_cp eval "ZentinelCp.Release.migrate()"
      break
    fi
    echo "[entrypoint] Database not ready (attempt ${retries}/${max_retries}), retrying in 2s..."
    sleep 2
  done
  echo "[entrypoint] Database migrations complete."
else
  echo "[entrypoint] Running database migrations..."
  /app/bin/zentinel_cp eval "ZentinelCp.Release.migrate()"
fi

# Seed default data
echo "[entrypoint] Seeding database..."
/app/bin/zentinel_cp eval "ZentinelCp.Release.seed()"

# Start the application
echo "[entrypoint] Starting Zentinel Control Plane..."
exec /app/bin/zentinel_cp start
