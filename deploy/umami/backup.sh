#!/bin/bash
set -euo pipefail
cd /opt/umami
umask 077
mkdir -p backups
file="backups/umami-$(date -u +%Y%m%d-%H%M%S).sql.gz"
docker compose exec -T db pg_dump -U umami -d umami | gzip > "$file.tmp"
if [ -s "$file.tmp" ]; then mv "$file.tmp" "$file"; fi
find backups -type f -name 'umami-*.sql.gz' -mtime +7 -delete
