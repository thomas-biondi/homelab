# Définitions de services

Un dossier par service, chacun avec son `docker-compose.yml`. Les fichiers sont
expurges : les mots de passe sont remplaces par des références a un fichier
`.env` non versionne, dont un modèle est fourni dans `.env.example`.

Trois exemples représentatifs sont publies plutôt que l'intégralité  de la pile :

| Dossier | Intérêt |
|---|---|
| `vaultwarden/` | Service simple, sans base, expose uniquement via le reverse proxy |
| `nextcloud/` | Service avec base PostgreSQL et cache, données sur volume dédie |
| `monitoring/` | Pile multi-conteneurs avec cloisonnement réseau explicite |

## Choix communs

**Aucun port publie sur l’hôte** pour les services applicatifs. L’accès passe par
le reverse proxy, qui est le seul a exposer 80 et 443. Cela évite la situation ou
un service reste joignable en direct malgré le pare-feu (voir `firewall/`).

**Réseau `proxy` externe.** Il est créé une fois en dehors des fichiers compose et
partage par tous les services qui doivent être publies. Docker Compose crée sinon
un reseau par projet, et deux services de dossiers différents ne se voient pas.

**`restart: unless-stopped` systématique.** Un incident réel a montre qu'un seul
conteneur dépourvu de cette directive ne remonte pas après une coupure de courant,
et que l’écart peut passer inaperçu plusieurs heures. Audit rapide de l'ensemble :

```bash
docker inspect $(docker ps -aq) \
  --format '{{.Name}} {{.HostConfig.RestartPolicy.Name}}' \
  | grep -v unless-stopped
```

**`container_name` explicite.** Sans lui, Docker préfixe le nom par celui du
projet, et les références croisées (requetes PromQL, sondes de disponibilité,
hôtes du reverse proxy) ne désignent plus les mêmes identifiants.
