#!/usr/bin/env bash
set -x

DATE_TIME="$(date "+%Y-%m-%dT%H:%M:%S")"
psql -Xc "COPY (select * from pg_stat_activity) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > pg_stat_activity-${DATE_TIME}.csv
psql -Xc "COPY (select * from pg_locks) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > pg_locks-${DATE_TIME}.csv