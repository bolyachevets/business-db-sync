#!/bin/bash
pg_dump -U $PGUSER -h localhost -p 6003 $PGDATABASE -n public --format=p  --file=/data/backup.sql
psql -U $PGUSER -h localhost -p 6003 -d postgres --tuples-only --no-align -c "
  SELECT 'CREATE ROLE IF NOT EXISTS \"' || rolname || '\"' ||
         CASE WHEN rolcanlogin AND rolname IN ('readonly', 'app_user') 
              THEN ' WITH LOGIN' 
              ELSE ' WITH NOLOGIN' 
         END || ';'
  FROM pg_roles 
  WHERE rolname NOT IN ('postgres', 'cloudsqladmin', 'cloudsqlsuperuser')
    AND rolname NOT LIKE 'pg\\_%' ESCAPE '\\'
    AND rolname NOT LIKE 'iam\\_%' ESCAPE '\\'
    AND rolname NOT LIKE 'rds%'
    AND rolname NOT LIKE 'cloudsql%'
" | grep -v "CREATE ROLE IF NOT EXISTS \"\"" > /data/roles.sql
psql -U $REPLICA_ADMIN -h localhost -p 5432 -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$PGDATABASE' AND pid <> pg_backend_pid();"
dropdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE
createdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE
psql -U $REPLICA_ADMIN -h localhost -p 5432 -f /data/roles.sql
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -v ON_ERROR_STOP=0 -x < /data/backup.sql
psql -U $REPLICA_ADMIN -h localhost -p 5432 -c "ALTER USER readonly WITH LOGIN PASSWORD '${READONLY_PASSWORD}';"
