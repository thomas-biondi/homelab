# Homelab auto-hébergé — infrastructure réseau et sécurité

Serveur domestique sous Debian, entièrement conteneurisé, assurant les services
**réellement en production** d'un réseau résidentiel : DNS, DHCP, reverse proxy
avec PKI interne, stockage, sauvegardes, supervision et filtrage réseau.

La contrainte structurante du projet n'est pas technique mais opérationnelle :
le serveur porte le DNS et le DHCP d'un réseau utilisé par d'autres personnes.
Toute erreur est visible immédiatement, tout changement risqué demande un plan
de retour arrière écrit à l'avance, et les sauvegardes comme la supervision
cessent d'être optionnelles.

---

## Périmètre technique

| Domaine | Mise en œuvre |
|---|---|
| Système | Debian stable headless, administration SSH exclusive |
| Conteneurisation | Docker Compose, ~20 conteneurs, réseaux cloisonnés |
| Services réseau | DNS récursif filtrant (DoH amont, bascule de résolveur), DHCP avec réservations |
| Exposition | Reverse proxy TLS, autorité de certification interne, certificat `*.home.arpa` |
| Accès distant | Réseau privé maillé WireGuard, **aucun port ouvert sur Internet** |
| Segmentation | VLAN 802.1Q sur Cisco Catalyst, router-on-a-stick, filtrage inter-VLAN à état |
| Filtrage | netfilter, chaîne dédiée, persistance par unité systemd |
| Détection | IDS comportemental sur journaux SSH et reverse proxy, avec application effective des décisions |
| Supervision | Sondes de disponibilité + métrologie en séries temporelles, 8 panneaux, 5 règles d'alerte |
| Sauvegarde | Dumps PostgreSQL + rsync `--link-dest`, rotation 7 jours, **restauration testée** |

---

## Ce que ce dépôt contient

**[Documentation technique complète](docs/documentation-technique.md)** — architecture,
choix d'implémentation, incidents rencontrés et limites assumées.

Ce n'est pas un tutoriel de déploiement. C'est un retour d'expérience : la
documentation consacre délibérément plus de place aux pièges rencontrés qu'aux
commandes qui ont fonctionné.

---

## Quelques enseignements documentés

Un échantillon des points développés dans la documentation, choisis parce qu'ils
sont contre-intuitifs :

**Docker contourne le pare-feu applicatif.** Une règle DNAT écrite en
`PREROUTING` est traversée avant `INPUT`. Pare-feu actif, politique par défaut
en refus, et pourtant les services conteneurisés répondent depuis tout le
réseau. Le malentendu est dangereux parce qu'il produit une confiance
injustifiée.

**Un IDS qui alerte ne protège pas.** L'agent analyse et décide ; c'est un
composant distinct qui applique les décisions dans le pare-feu. Beaucoup
d'installations s'arrêtent à l'agent et en concluent à tort qu'elles sont
couvertes. Validé ici par auto-bannissement volontaire, avec coupure d'accès
effective.

**IPv6 comme angle mort du filtrage DNS.** Des clients contournaient le
résolveur local en obtenant un DNS par IPv6, distribué indépendamment par la
box.

**Une sauvegarde jamais restaurée est une hypothèse.** Restauration vérifiée en
trois niveaux : intégrité de l'export, restauration réelle sur base jetable,
contrôle de structure des fichiers.

**La valeur d'une métrique vient de l'écart à la ligne de base.** Une attente
disque à 18 % ne signifie rien sans savoir qu'elle est à 0,1 % au repos.

---

## Limites assumées

Documentées dans le détail en section 13, parce qu'une architecture dont on ne
voit aucune faiblesse est une architecture mal comprise : point unique de
défaillance sur le DNS/DHCP, sauvegardes non délocalisées (règle 3-2-1
satisfaite à moitié), stockage de données en USB, et plan de management du
switch limité à des algorithmes cryptographiques obsolètes.

---

## Note sur la publication

Ce dépôt est la version publique d'un journal de bord tenu tout au long du
projet. Les adresses, identifiants, noms d'hôtes et noms de services ont été
remplacés par des valeurs génériques ou désignés par leur rôle.

La configuration héritée trouvée sur le commutateur d'occasion (domaine VTP et
VLAN de production d'un site tiers) est mentionnée uniquement pour décrire la
procédure d'effacement. Aucune de ces données n'est reproduite ici.

---

## Contexte

Projet personnel mené en parallèle d'une formation Bac+3 en réseaux et
télécommunications, spécialité cybersécurité. Orientation cyberdéfense /
blue team.

## Licence

Documentation publiée sous [CC BY-SA 4.0](LICENSE) — Copyright (c) 2026 Thomas Biondi.