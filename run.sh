#!/bin/bash
data_dir="/data"
cd $data_dir

pg_dump -U $PGUSER -h localhost -p 6003 $PGDATABASE -n public --format=p  --file=legal-backup.sql
psql -U $REPLICA_ADMIN -h localhost -p 5432 -ac "DROP DATABASE \"${PGDATABASE}\";"
psql -U $REPLICA_ADMIN -h localhost -p 5432 -ac "CREATE DATABASE \"${PGDATABASE}\";"
psql -U $PGUSER -h localhost -p 5432 -ac "GRANT ALL ON DATABASE \"${PGDATABASE}\" TO \"${PGUSER}\";"
psql -U $REPLICA_ADMIN -h localhost -p 5432  -d $PGDATABASE -v ON_ERROR_STOP=0 -x < legal-backup.sql
#rm legal-backup.sql
