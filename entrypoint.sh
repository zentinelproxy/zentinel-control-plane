#!/bin/sh
set -e

# SECRET_KEY_BASE and ENCRYPTION_KEY must be stable and shared by all instances.
# The release refuses to start without them, so do not generate them here.

# Wait for the database to accept connections (belt-and-suspenders on top of
# Docker healthchecks -- pg_isready can return 0 before the server is fully
# ready to handle queries).
echo "[entrypoint] Running database migrations..."
retries=0
max_retries=30
until /app/bin/zentinel_cp eval "ZentinelCp.Release.migrate()"; do
  retries=$((retries + 1))
  if [ "$retries" -ge "$max_retries" ]; then
    echo "[entrypoint] Migrations failed after ${max_retries} attempts."
    exit 1
  fi
  echo "[entrypoint] Migration attempt ${retries}/${max_retries} failed, retrying in 2s..."
  sleep 2
done
echo "[entrypoint] Database migrations complete."

# Creates the first admin from ADMIN_EMAIL and ADMIN_PASSWORD, if no users exist.
/app/bin/zentinel_cp eval "ZentinelCp.Release.bootstrap_admin()"

echo "[entrypoint] Starting Zentinel Control Plane..."
exec /app/bin/zentinel_cp start
