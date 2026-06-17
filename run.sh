#!/bin/bash
SCHEMA=${DATABASE_SCHEMA:-public}

export PGPASSWORD=""

# Dump schema + data (no roles)
pg_dump -U $PGUSER -h localhost -p 6003 $PGDATABASE \
  -n $SCHEMA \
  --no-owner --no-privileges \
  --format=p --file=/data/backup.sql

if [ $? -ne 0 ]; then
  echo "ERROR: pg_dump failed"
  exit 1
fi

# Extract extensions from source
psql -U $PGUSER -h localhost -p 6003 -d $PGDATABASE --tuples-only --no-align -c "
  SELECT 'CREATE EXTENSION IF NOT EXISTS \"' || e.extname || '\" SCHEMA ' || n.nspname || ';'
  FROM pg_extension e
  JOIN pg_namespace n ON e.extnamespace = n.oid
  WHERE n.nspname = '$SCHEMA'
" > /data/extensions.sql

# Remove backslash metacommands (but keep \. COPY terminators) and transaction blocks
sed -i '/^\\[^.]/ d' /data/backup.sql
sed -i '/^BEGIN;/d' /data/backup.sql
sed -i '/^COMMIT;/d' /data/backup.sql

# Kill connections
while
  psql -U $REPLICA_ADMIN -h localhost -p 5432 -d postgres -tAc "SELECT 1 FROM pg_stat_activity WHERE datname = '$PGDATABASE' AND pid <> pg_backend_pid()" | grep -q 1
do
  psql -U $REPLICA_ADMIN -h localhost -p 5432 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$PGDATABASE' AND pid <> pg_backend_pid();"
  sleep 1
done

# Drop and recreate database
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$PGDATABASE'" | grep -q 1 && dropdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE
createdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE

# Create schema
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "CREATE SCHEMA IF NOT EXISTS $SCHEMA;"

# Create extensions (if any)
[ -s /data/extensions.sql ] && psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -f /data/extensions.sql

# Restore with session_replication_role
{
  echo "SET session_replication_role = 'replica';"
  cat /data/backup.sql
  echo "SET session_replication_role = 'origin';"
} | psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -v ON_ERROR_STOP=0

# Setup readonly user (optional)
psql -U $REPLICA_ADMIN -h localhost -p 5432 -c "ALTER USER readonly WITH LOGIN PASSWORD '${READONLY_PASSWORD}';" 2>/dev/null || true
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "GRANT USAGE ON SCHEMA $SCHEMA TO readonly;" 2>/dev/null || true
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "GRANT SELECT ON ALL TABLES IN SCHEMA $SCHEMA TO readonly;" 2>/dev/null || true
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "ALTER DEFAULT PRIVILEGES IN SCHEMA $SCHEMA GRANT SELECT ON TABLES TO readonly;" 2>/dev/null || true

echo "Restore completed successfully"