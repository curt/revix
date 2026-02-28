#!/bin/ash
set -e

echo "-- Waiting for database ..."
while ! pg_isready -U revix -d postgres://db:5432/revix -t 1; do
    sleep 1s
done

echo "-- Running migrations ..."
bin/migrate

echo "-- Starting!"
bin/server
