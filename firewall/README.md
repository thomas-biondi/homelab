# Filtrage : deux couches distinctes

Un pare-feu applicatif seul ne protege pas un hote Docker. C'est l'enseignement
principal de cette partie, et il se demontre en une commande.

## Le point aveugle

Pare-feu actif, politique par defaut en refus, aucune regle n'autorisant le port
d'un conteneur. Et pourtant, depuis n'importe quelle machine du reseau :

```
$ curl -I http://<serveur>:8096
HTTP/1.1 302 Found
```

Le service repond. Le pare-feu n'a rien bloque, parce qu'il n'a jamais vu passer
le paquet.

**Explication.** Lorsqu'un port est publie, Docker ecrit une regle DNAT dans la
table `nat`, chaine `PREROUTING` :

```
$ sudo iptables -t nat -L DOCKER -n
DNAT  tcp  dpt:8096  to:172.18.0.10:8096
DNAT  tcp  dpt:443   to:172.18.0.7:443
```

Cette table est traversee **avant** la chaine `INPUT` ou le pare-feu applicatif
pose ses regles. Le paquet est reecrit vers l'adresse interne du conteneur puis
poursuit en `FORWARD` : il ne visite jamais `INPUT`.

Le malentendu est dangereux parce qu'il produit une confiance injustifiee. A
verifier systematiquement par un test reel plutot qu'a supposer.

## Les deux couches

| Fichier | Portee |
|---|---|
| `ufw-rules.sh` | Services ecoutant sur l'hote : SSH, DNS, DHCP, tunnel prive |
| `docker-user-rules.service` | Acces aux conteneurs, via la seule chaine que Docker respecte |

Docker cree volontairement `DOCKER-USER` vide, en tete de `FORWARD`, et ne
l'ecrase jamais lors de ses reconfigurations. C'est le point d'accroche prevu
pour les regles utilisateur.

## Persistance

Les paquets de sauvegarde de regles et le pare-feu applicatif sont en conflit sur
Debian : installer l'un desinstalle l'autre. Et une insertion dans les fichiers de
regles du pare-feu casse leur structure, qui contient deja son propre bloc
`*filter` et son `COMMIT`.

D'ou l'unite systemd, ordonnancee apres le demarrage de Docker.

## Verifications

```bash
sudo ufw status verbose
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

L'ordre compte autant que le contenu : la regle de suivi de connexions doit
apparaitre en position 1.

Un dispositif qui ne survit pas a un redemarrage n'existe pas. Le controle complet
(pare-feu actif, chaine peuplee dans le bon ordre, conteneurs demarres) a ete
effectue apres reboot volontaire.
