#!/bin/bash
pg_dump -U $PGUSER -h localhost -p 6003 $PGDATABASE -n public --format=p  --file=/data/backup.sql
dropdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE
createdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -v ON_ERROR_STOP=0 -x < /data/backup.sql
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -ac "CREATE USER readonly WITH PASSWORD '${READONLY_PASSWORD}';"
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -ac "GRANT CONNECT ON DATABASE \"${PGDATABASE}\" to readonly;"
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -ac "GRANT USAGE ON SCHEMA public TO readonly;"
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -ac "GRANT SELECT ON ALL TABLES IN SCHEMA public to readonly;"
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -ac "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO readonly;"
