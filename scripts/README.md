# Sauvegarde et restauration

`backup-docker.sh` s'exécute chaque nuit par cron :

```
0 3 * * * /home/<user>/backup-docker.sh >> /var/log/backup-docker.log 2>&1
```

## Ce qui est couvert, et ce qui ne l'est pas

Couvert : l'intégralité de `~/docker` (configurations et bases SQLite), les
données applicatives sur le volume dédié, et les exports PostgreSQL.

Non couvert : la médiathèque, volumineuse et remplaçable. Une sauvegarde qui
inclut tout est une sauvegarde qu'on ne restaure jamais.

## Trois décisions de conception

**Exports avant synchronisation.** Copier les fichiers d'une base en cours
d'écriture produit un état incohérent qui ne se restaure pas. Le script passe
donc par `pg_dump`, et la synchronisation exclut explicitement les répertoires
de données PostgreSQL.

**Rotation par liens durs.** `rsync --link-dest` ne duplique que les fichiers
modifiés. Sept rotations occupent environ 9 Go au lieu de 30. Corollaire à
connaître : ces sauvegardes sont physiquement interdépendantes, une corruption
du système de fichiers peut en affecter plusieurs à la fois.

**Vérification du montage.** Le script s'arrête si le volume de données n'est
pas monté, plutôt que de synchroniser des dossiers vides par-dessus l'historique.

## Test de restauration

Une sauvegarde jamais restaurée est une hypothèse. La vérification se fait en
trois niveaux, sans jamais toucher à la production.

**1. Intégrité de l'export.** Un dump PostgreSQL valide se termine par une ligne
explicite de fin. C'est le contrôle décisif : il prouve que l'export n'a pas été
interrompu.

```bash
sudo tail -5 ~/backups/latest/nextcloud-dump/nextcloud-db.sql
sudo grep -c "CREATE TABLE" ~/backups/latest/nextcloud-dump/nextcloud-db.sql
```

**2. Restauration réelle dans une base jetable.**

```bash
docker exec -it nextcloud-db psql -U <user> -d postgres \
  -c "CREATE DATABASE test_restore;"

sudo cat ~/backups/latest/nextcloud-dump/nextcloud-db.sql \
  | docker exec -i nextcloud-db psql -U <user> -d test_restore 2>&1 \
  | grep -ci error          # doit renvoyer 0

docker exec -it nextcloud-db psql -U <user> -d test_restore \
  -c "SELECT count(*) FROM public.oc_users;"

docker exec -it nextcloud-db psql -U <user> -d postgres \
  -c "DROP DATABASE test_restore;"
```

Deux pièges : `psql` sans option `-d` tente de se connecter à une base portant le
nom de l'utilisateur, il faut donc toujours préciser une base d'entrée existante.
Et relancer l'import sur une base déjà peuplée produit des centaines d'erreurs
`already exists` qui ne signalent pas un export défectueux mais une restauration
en double. Seule une restauration sur base vierge est probante.

**3. Intégrité des fichiers.** Une base restaurée sans les documents ne sert à
rien. Un contrôle de structure confirme que le contenu est exploitable, et pas
seulement présent avec la bonne taille.

```bash
sudo find ~/backups/latest/nextcloud-data -type f | wc -l
sudo file $(sudo find ~/backups/latest/paperless-data -name "*.pdf" | head -1)
```

## Limite assumée

Les sauvegardes vivent sur le même serveur que les données. Le dispositif protège
contre l'erreur humaine, la corruption logicielle et la panne d'un service ; il ne
protège ni de l'incendie, ni du vol, ni d'un rançongiciel. La règle 3-2-1 n'est
satisfaite qu'à moitié.
