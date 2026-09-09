# Sauvegarde et restauration

`backup-docker.sh` s'execute chaque nuit par cron :

```
0 3 * * * /home/<user>/backup-docker.sh >> /var/log/backup-docker.log 2>&1
```

## Ce qui est couvert, et ce qui ne l'est pas

Couvert : l'integralite de `~/docker` (configurations et bases SQLite), les
donnees applicatives sur le volume dedie, et les exports PostgreSQL.

Non couvert : la mediatheque, volumineuse et remplacable. Une sauvegarde qui
inclut tout est une sauvegarde qu'on ne restaure jamais.

## Trois decisions de conception

**Exports avant synchronisation.** Copier les fichiers d'une base en cours
d'ecriture produit un etat incoherent qui ne se restaure pas. Le script passe
donc par `pg_dump`, et la synchronisation exclut explicitement les repertoires
de donnees PostgreSQL.

**Rotation par liens durs.** `rsync --link-dest` ne duplique que les fichiers
modifies. Sept rotations occupent environ 9 Go au lieu de 30. Corollaire a
connaitre : ces sauvegardes sont physiquement interdependantes, une corruption
du systeme de fichiers peut en affecter plusieurs a la fois.

**Verification du montage.** Le script s'arrete si le volume de donnees n'est
pas monte, plutot que de synchroniser des dossiers vides par-dessus l'historique.

## Test de restauration

Une sauvegarde jamais restauree est une hypothese. La verification se fait en
trois niveaux, sans jamais toucher a la production.

**1. Integrite de l'export.** Un dump PostgreSQL valide se termine par une ligne
explicite de fin. C'est le controle decisif : il prouve que l'export n'a pas ete
interrompu.

```bash
sudo tail -5 ~/backups/latest/nextcloud-dump/nextcloud-db.sql
sudo grep -c "CREATE TABLE" ~/backups/latest/nextcloud-dump/nextcloud-db.sql
```

**2. Restauration reelle dans une base jetable.**

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

Deux pieges : `psql` sans option `-d` tente de se connecter a une base portant le
nom de l'utilisateur, il faut donc toujours preciser une base d'entree existante.
Et relancer l'import sur une base deja peuplee produit des centaines d'erreurs
`already exists` qui ne signalent pas un export defectueux mais une restauration
en double. Seule une restauration sur base vierge est probante.

**3. Integrite des fichiers.** Une base restauree sans les documents ne sert a
rien. Un controle de structure confirme que le contenu est exploitable, et pas
seulement present avec la bonne taille.

```bash
sudo find ~/backups/latest/nextcloud-data -type f | wc -l
sudo file $(sudo find ~/backups/latest/paperless-data -name "*.pdf" | head -1)
```

## Limite assumee

Les sauvegardes vivent sur le meme serveur que les donnees. Le dispositif protege
contre l'erreur humaine, la corruption logicielle et la panne d'un service ; il ne
protege ni de l'incendie, ni du vol, ni d'un rancongiciel. La regle 3-2-1 n'est
satisfaite qu'a moitie.
