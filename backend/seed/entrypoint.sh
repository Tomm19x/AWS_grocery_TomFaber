#!/usr/bin/env bash
set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET not set}"
: "${S3_KEY:?S3_KEY not set}"
: "${POSTGRES_HOST:?POSTGRES_HOST not set}"
: "${POSTGRES_DB:?POSTGRES_DB not set}"
: "${POSTGRES_USER:?POSTGRES_USER not set}"
: "${DB_PASSWORD:?POSTGRES_PASSWORD not set}"

echo "Downloading SQL from s3://${S3_BUCKET}/${S3_KEY} ..."
aws s3 cp "s3://${S3_BUCKET}/${S3_KEY}" /tmp/seed.sql

echo "Seeding database ${POSTGRES_DB} on ${POSTGRES_HOST} ..."
PGPASSWORD="${DB_PASSWORD}" psql \
  -v ON_ERROR_STOP=1 \
  -h "${POSTGRES_HOST}" \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  -f /tmp/seed.sql

echo "Seed complete."
