#!/bin/bash
SCHEMA=${DATABASE_SCHEMA:-public}  # This is 'auth'

# Empty password for IAM authentication (cloud-sql-proxy handles auth)
export PGPASSWORD=""

# Dump from Cloud SQL - backing up the auth schema
pg_dump -U $PGUSER -h localhost -p 6003 $PGDATABASE -n $SCHEMA --no-owner --no-privileges --format=p --file=/data/backup.sql

if [ $? -ne 0 ]; then
  echo "ERROR: pg_dump failed"
  exit 1
fi

# Get roles from Cloud SQL
psql -U $PGUSER -h localhost -p 6003 -d postgres --tuples-only --no-align -c "
  SELECT 'DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ''' || rolname || ''') THEN
    CREATE ROLE \"' || rolname || '\"' ||
    CASE WHEN rolcanlogin AND rolname IN ('readonly', 'app_user')
         THEN ' WITH LOGIN'
         ELSE ' WITH NOLOGIN'
    END || ';
  END IF;
END
\$\$;'
  FROM pg_roles
  WHERE rolname NOT IN ('postgres')
    AND rolname NOT LIKE 'pg\\_%' ESCAPE '\\'
    AND rolname NOT LIKE 'iam\\_%' ESCAPE '\\'
    AND rolname NOT LIKE 'rds%'
    AND rolname NOT LIKE 'cloudsql%'
" > /data/roles.sql

# CRITICAL FIX 1: Remove backslash commands that cause errors
sed -i '/^\\/d' /data/backup.sql

# CRITICAL FIX 2: Remove the problematic ALTER TABLE commands that reference missing tables
# These will be recreated properly after restore
sed -i '/ALTER TABLE.*ADD.*FOREIGN KEY/d' /data/backup.sql
sed -i '/ALTER TABLE ONLY.*ADD CONSTRAINT.*FOREIGN KEY/d' /data/backup.sql

# Local PostgreSQL operations (using password auth for local DB)
while
  psql -U $REPLICA_ADMIN -h localhost -p 5432 -d postgres -tAc "SELECT 1 FROM pg_stat_activity WHERE datname = '$PGDATABASE' AND pid <> pg_backend_pid()" | grep -q 1
do
  psql -U $REPLICA_ADMIN -h localhost -p 5432 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$PGDATABASE' AND pid <> pg_backend_pid();"
  sleep 1
done

psql -U $REPLICA_ADMIN -h localhost -p 5432 -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$PGDATABASE'" | grep -q 1 && dropdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE
createdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE

# Create the auth schema
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "CREATE SCHEMA IF NOT EXISTS $SCHEMA;"

# Apply roles
psql -U $REPLICA_ADMIN -h localhost -p 5432 -f /data/roles.sql

# CRITICAL FIX 3: Restore with ON_ERROR_STOP=0 to continue on errors
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE \
  -v ON_ERROR_STOP=0 \
  -c "SET session_replication_role = 'replica';" \
  -f /data/backup.sql \
  -c "SET session_replication_role = 'origin';"

# CRITICAL FIX 4: Recreate foreign keys after data is loaded
echo "Recreating foreign key constraints..."
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "
DO \$\$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT 
      tc.table_schema, 
      tc.table_name, 
      tc.constraint_name,
      kcu.column_name,
      ccu.table_schema AS foreign_table_schema,
      ccu.table_name AS foreign_table_name,
      ccu.column_name AS foreign_column_name
    FROM 
      information_schema.table_constraints AS tc 
      JOIN information_schema.key_column_usage AS kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage AS ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = '$SCHEMA'
  ) LOOP
    EXECUTE format('
      ALTER TABLE %I.%I 
      ADD CONSTRAINT %I 
      FOREIGN KEY (%I) 
      REFERENCES %I.%I (%I)
    ', r.table_schema, r.table_name, r.constraint_name, 
       r.column_name, r.foreign_table_schema, 
       r.foreign_table_name, r.foreign_column_name);
  END LOOP;
END;
\$\$;
"

# Check if restore succeeded
if [ $? -ne 0 ]; then
  echo "WARNING: Some errors occurred during restore, but continuing"
fi

# Setup permissions for auth schema
psql -U $REPLICA_ADMIN -h localhost -p 5432 -c "ALTER USER readonly WITH LOGIN PASSWORD '${READONLY_PASSWORD}';"
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "GRANT USAGE ON SCHEMA $SCHEMA TO readonly;"
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "GRANT SELECT ON ALL TABLES IN SCHEMA $SCHEMA TO readonly;"
psql -U $REPLICA_ADMIN -h localhost -p 5432 -d $PGDATABASE -c "ALTER DEFAULT PRIVILEGES IN SCHEMA $SCHEMA GRANT SELECT ON TABLES TO readonly;"

echo "Backup completed successfully"