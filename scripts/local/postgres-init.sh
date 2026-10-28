#!/bin/sh
# Roda uma vez, na primeira subida do volume do Postgres local: cria os dois
# bancos e aplica o init.sql de cada serviço (os mesmos que os Jobs de
# db-init aplicam no cluster).
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<'SQL'
CREATE DATABASE ngo_db;
CREATE DATABASE donation_db;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname ngo_db -f /sql/ngo.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname donation_db -f /sql/donation.sql
