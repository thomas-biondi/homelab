# Filtrage : deux couches distinctes

Un pare-feu applicatif seul ne protège pas un hôte Docker. C'est l'enseignement
principal de cette partie, et il se démontre en une commande.

## Le point aveugle

Pare-feu actif, politique par défaut en refus, aucune règle n'autorisant le port
d'un conteneur. Et pourtant, depuis n'importe quelle machine du réseau :

```
$ curl -I http://<serveur>:8096
HTTP/1.1 302 Found
```

Le service répond. Le pare-feu n'a rien bloqué, parce qu'il n'a jamais vu passer
le paquet.

**Explication.** Lorsqu'un port est publié, Docker écrit une règle DNAT dans la
table `nat`, chaîne `PREROUTING` :

```
$ sudo iptables -t nat -L DOCKER -n
DNAT  tcp  dpt:8096  to:172.18.0.10:8096
DNAT  tcp  dpt:443   to:172.18.0.7:443
```

Cette table est traversée **avant** la chaîne `INPUT` où le pare-feu applicatif
pose ses règles. Le paquet est réécrit vers l'adresse interne du conteneur puis
poursuit en `FORWARD` : il ne visite jamais `INPUT`.

Le malentendu est dangereux parce qu'il produit une confiance injustifiée. À
vérifier systématiquement par un test réel plutôt qu'à supposer.

## Les deux couches

| Fichier | Portée |
|---|---|
| `ufw-rules.sh` | Services écoutant sur l'hôte : SSH, DNS, DHCP, tunnel privé |
| `docker-user-rules.service` | Accès aux conteneurs, via la seule chaîne que Docker respecte |

Docker crée volontairement `DOCKER-USER` vide, en tête de `FORWARD`, et ne
l'écrase jamais lors de ses reconfigurations. C'est le point d'accroche prévu
pour les règles utilisateur.

## Persistance

Les paquets de sauvegarde de règles et le pare-feu applicatif sont en conflit sur
Debian : installer l'un désinstalle l'autre. Et une insertion dans les fichiers de
règles du pare-feu casse leur structure, qui contient déjà son propre bloc
`*filter` et son `COMMIT`.

D'où l'unité systemd, ordonnancée après le démarrage de Docker.

## Vérifications

```bash
sudo ufw status verbose
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

L'ordre compte autant que le contenu : la règle de suivi de connexions doit
apparaître en position 1.

Un dispositif qui ne survit pas à un redémarrage n'existe pas. Le contrôle complet
(pare-feu actif, chaîne peuplée dans le bon ordre, conteneurs démarrés) a été
effectué après reboot volontaire.
