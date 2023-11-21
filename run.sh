#!/bin/bash
pg_dump -U $PGUSER -h localhost -p 6003 $PGDATABASE -n public --format=p  --file=/data/legal-backup.sql
dropdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE
createdb -U $REPLICA_ADMIN -h localhost -p 5432 $PGDATABASE
# psql -U $PGUSER -h localhost -p 5432 -ac "GRANT ALL ON DATABASE \"${PGDATABASE}\" TO \"${PGUSER}\";"
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -v ON_ERROR_STOP=0 -x < /data/legal-backup.sql
#rm /data/legal-backup.sql
