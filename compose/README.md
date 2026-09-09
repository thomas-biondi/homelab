# Definitions de services

Un dossier par service, chacun avec son `docker-compose.yml`. Les fichiers sont
expurges : les mots de passe sont remplaces par des references a un fichier
`.env` non versionne, dont un modele est fourni dans `.env.example`.

Trois exemples representatifs sont publies plutot que l'integralite de la pile :

| Dossier | Interet |
|---|---|
| `vaultwarden/` | Service simple, sans base, expose uniquement via le reverse proxy |
| `nextcloud/` | Service avec base PostgreSQL et cache, donnees sur volume dedie |
| `monitoring/` | Pile multi-conteneurs avec cloisonnement reseau explicite |

## Choix communs

**Aucun port publie sur l'hote** pour les services applicatifs. L'acces passe par
le reverse proxy, qui est le seul a exposer 80 et 443. Cela evite la situation ou
un service reste joignable en direct malgre le pare-feu (voir `firewall/`).

**Reseau `proxy` externe.** Il est cree une fois en dehors des fichiers compose et
partage par tous les services qui doivent etre publies. Docker Compose cree sinon
un reseau par projet, et deux services de dossiers differents ne se voient pas.

**`restart: unless-stopped` systematique.** Un incident reel a montre qu'un seul
conteneur depourvu de cette directive ne remonte pas apres une coupure de courant,
et que l'ecart peut passer inapercu plusieurs heures. Audit rapide de l'ensemble :

```bash
docker inspect $(docker ps -aq) \
  --format '{{.Name}} {{.HostConfig.RestartPolicy.Name}}' \
  | grep -v unless-stopped
```

**`container_name` explicite.** Sans lui, Docker prefixe le nom par celui du
projet, et les references croisees (requetes PromQL, sondes de disponibilite,
hotes du reverse proxy) ne designent plus les memes identifiants.
