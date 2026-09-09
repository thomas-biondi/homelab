#!/bin/bash
# Sauvegarde quotidienne : exports PostgreSQL puis synchronisation incrementale.
# Declenche par cron. Voir scripts/README.md pour la strategie et les tests.
set -euo pipefail

DEST="/home/<user>/backups"
DATE=$(date +%Y-%m-%d)
RETENTION=7
DUMPDIR="/mnt/data/paperless/export"
NCDUMPDIR="/mnt/data/nextcloud-dump"

# Garde-fou : sans ce controle, une sauvegarde lancee disque absent
# ecraserait l'historique par des dossiers vides.
if ! mountpoint -q /mnt/data; then
    echo "$(date): ERREUR - /mnt/data non monte, sauvegarde annulee"
    exit 1
fi

mkdir -p "$DEST" "$DUMPDIR" "$NCDUMPDIR"

# --- Exports coherents des bases ---------------------------------------
# Copier les fichiers d'une base en cours d'ecriture donne un etat
# incoherent : on passe donc par pg_dump avant la synchronisation.

if docker ps --format '{{.Names}}' | grep -q '^paperless-db$'; then
    docker exec paperless-db pg_dump -U paperless -d paperless \
        > "$DUMPDIR/paperless-db.sql"
    echo "$(date): dump PostgreSQL Paperless OK"
else
    echo "$(date): ATTENTION - conteneur paperless-db absent, dump ignore"
fi

if docker ps --format '{{.Names}}' | grep -q '^nextcloud-db$'; then
    docker exec nextcloud-db pg_dump -U nextcloud -d nextcloud \
        > "$NCDUMPDIR/nextcloud-db.sql"
    echo "$(date): dump PostgreSQL Nextcloud OK"
else
    echo "$(date): ATTENTION - conteneur nextcloud-db absent, dump ignore"
fi

# --- Synchronisation incrementale --------------------------------------
# --link-dest cree des liens durs vers la sauvegarde precedente pour tout
# fichier inchange : 7 jours d'historique tiennent dans ~9 Go au lieu de 30.
mkdir -p "$DEST/$DATE"

rsync -a --delete \
      --link-dest="$DEST/latest/docker" \
      --exclude 'paperless/pgdata' \
      --exclude 'nextcloud/pgdata' \
      /home/<user>/docker/ "$DEST/$DATE/docker/"

rsync -a --delete \
      --link-dest="$DEST/latest/paperless-data" \
      /mnt/data/paperless/ "$DEST/$DATE/paperless-data/"

rsync -a --delete \
      --link-dest="$DEST/latest/nextcloud-data" \
      /mnt/data/nextcloud/ "$DEST/$DATE/nextcloud-data/"

rsync -a --delete \
      --link-dest="$DEST/latest/nextcloud-dump" \
      "$NCDUMPDIR/" "$DEST/$DATE/nextcloud-dump/"

# Raccourci vers la derniere sauvegarde, utilise par --link-dest.
rm -f "$DEST/latest"
ln -s "$DEST/$DATE" "$DEST/latest"

# Rotation
find "$DEST" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION -exec rm -rf {} \;

echo "$(date): Sauvegarde terminee -> $DEST/$DATE"

# Notification de bonne fin vers la supervision. Le jeton est propre a
# l'installation et n'est pas publie.
docker exec npm curl -fsS -m 10 --retry 3 \
  "http://uptime-kuma:3001/api/push/<TOKEN>?status=up&msg=Sauvegarde+OK" > /dev/null
