# Homelab auto-hébergé : documentation technique

> Serveur domestique auto-hébergé sous Debian, entièrement conteneurisé, assurant
> des services de production pour un réseau résidentiel : DNS, DHCP, reverse proxy,
> stockage, supervision et filtrage réseau.
>
> Ce document est la version publique d'un journal de bord tenu tout au long du
> projet. Les adresses, identifiants et noms d'hôtes ont été remplacés par des
> valeurs génériques.

---

## Sommaire

1. [Contexte et objectifs](#1-contexte-et-objectifs)
2. [Architecture générale](#2-architecture-générale)
3. [Socle : Debian et Docker](#3-socle--debian-et-docker)
4. [DNS et DHCP](#4-dns-et-dhcp)
5. [Reverse proxy et PKI interne](#5-reverse-proxy-et-pki-interne)
6. [Stockage et sauvegardes](#6-stockage-et-sauvegardes)
7. [Services applicatifs](#7-services-applicatifs)
8. [Accès distant](#8-accès-distant)
9. [Supervision et alerting](#9-supervision-et-alerting)
10. [Segmentation réseau (VLAN)](#10-segmentation-réseau-vlan)
11. [Pare-feu et détection d'intrusion](#11-pare-feu-et-détection-dintrusion)
12. [Incidents notables](#12-incidents-notables)
13. [Limites connues](#13-limites-connues)

---

## 1. Contexte et objectifs

Projet personnel mené en parallèle d'une formation en réseaux et
télécommunications, spécialité cybersécurité. L'objectif n'était pas d'accumuler
des services, mais de mettre en place une infrastructure **réellement en
production** : le serveur assure le DNS et le DHCP d'un réseau résidentiel
complet, ce qui impose des contraintes d'exploitation absentes d'un simple
laboratoire.

Cette contrainte a structuré tout le projet :

- toute erreur affecte des utilisateurs qui n'ont pas choisi d'être là ;
- chaque changement risqué doit avoir un plan de retour arrière écrit avant l'intervention ;
- les sauvegardes, la supervision et les alertes ne sont pas optionnelles.

**Compétences couvertes** : administration Linux, conteneurisation, services
réseau (DNS, DHCP, reverse proxy, TLS), commutation et VLAN 802.1Q, routage
inter-VLAN, filtrage netfilter, supervision et métrologie, sauvegarde et
restauration.

---

## 2. Architecture générale

### Matériel

| Élément | Caractéristiques |
|---|---|
| Serveur | Mini-PC x86 basse consommation, 6 cœurs / 8 threads, 15 W, 32 Go DDR5 |
| Stockage système | SSD NVMe 256 Go |
| Stockage données | SSD SATA 1 To en boîtier USB, monté sur `/mnt/data` |
| Commutation | Switch Cisco Catalyst 2960 (24 ports FastEthernet, 2 Gigabit) |
| Accès Internet | Box opérateur fibre (~940/800 Mbit/s mesurés) |

Consommation de l'ensemble en fonctionnement : environ 40 W en continu.

### Logique de déploiement

Un dossier par service dans `~/docker/`, chacun avec son `docker-compose.yml`.
Environ vingt conteneurs en fonctionnement permanent, répartis sur plusieurs
réseaux Docker cloisonnés.

```
Internet
   │
Box opérateur ─── Switch ─── Serveur (Debian, Docker)
                                │
                                ├── DNS / DHCP
                                ├── Reverse proxy (TLS)
                                ├── Services applicatifs
                                └── Supervision
```

---

## 3. Socle : Debian et Docker

Debian stable en installation *headless*, administrée exclusivement en SSH.

**Docker** apporte l'isolation des systèmes de fichiers, du réseau et des
processus. Il faut noter que cette isolation ne porte **pas** sur les ressources :
tous les conteneurs partagent le même processeur et la même mémoire, ce qui s'est
vérifié lors d'opérations lourdes.

Un point de vocabulaire souvent mal posé : un fichier `docker-compose.yml` n'est
pas un script mais une **déclaration d'état**. On décrit la cible, l'outil se
charge d'y converger, d'où le fait qu'un `docker compose up -d` sur une pile
inchangée ne produise aucun effet.

> **Point de vigilance.** La colonne `PORTS` de `docker ps` affiche les ports
> *déclarés dans l'image*, pas ceux réellement en écoute. Une variable
> d'environnement peut changer le port effectif sans que cela apparaisse. La seule
> vérification fiable est un test de connectivité depuis un autre conteneur.

### Diagnostic inter-conteneurs

Le réflexe le plus rentable du projet, qui distingue immédiatement un problème
réseau d'un problème d'authentification :

```bash
docker exec <conteneur_a> curl -I http://<conteneur_b>:<port>
```

| Réponse | Interprétation |
|---|---|
| `200 OK` | tout fonctionne |
| `401` / `403` | le réseau fonctionne, l'authentification bloque |
| `Could not connect` | mauvais port, ou service non démarré |
| aucune réponse | conteneur arrêté, ou réseaux Docker distincts |

---

## 4. DNS et DHCP

### Résolution DNS

Le serveur assure la résolution de noms pour l'ensemble du réseau, avec filtrage
publicitaire par listes de blocage et résolveurs amont interrogés en
**DNS-over-HTTPS**. Deux résolveurs distincts sont déclarés : en cas de
non-réponse du premier, le service bascule automatiquement sur le second. La
configuration initiale, avec un résolveur unique, constituait un point de
fragilité.

Contrainte d'installation : le résolveur système occupe le port 53 sur l'adresse
de bouclage. Le conteneur DNS est donc publié sur l'adresse du réseau local, ce
qui a une conséquence pratique à retenir : il faut l'interroger sur cette adresse
et non sur `127.0.0.1`.

### Bascule du DHCP

Le serveur DHCP a été retiré de la box opérateur au profit du serveur, afin de
maîtriser les baux, les réservations et l'annonce du DNS.

Le conteneur concerné fonctionne en `network_mode: host`. Ce n'est pas un
raccourci : le DHCP repose sur des trames de **diffusion**, qui ne traversent pas
la traduction d'adresses du réseau Docker par défaut.

> **Incident structurant : l'option DHCP 125**
>
> Après la bascule, les décodeurs TV de l'opérateur ont cessé de fonctionner.
> Analyse : ces équipements attendent une option DHCP propriétaire (option 125,
> *Vendor-Identifying Vendor-Specific Information*) pour valider qu'ils se
> trouvent bien sur le réseau de leur opérateur. Sans elle, ils refusent de
> démarrer le flux vidéo.
>
> La solution a consisté à reconstruire manuellement la structure TLV attendue,
> à partir de travaux de rétro-ingénierie publiés par la communauté, et à
> l'injecter dans la configuration du serveur DHCP.
>
> **Précaution durable** : l'interface web du service réécrit son fichier de
> configuration à chaque modification DHCP. La présence de l'option forgée doit
> donc être revérifiée après toute intervention.

### IPv6 : un angle mort

Des tests ont montré que certains équipements contournaient le filtrage DNS en
obtenant un résolveur par IPv6, distribué indépendamment par la box. IPv6 a été
désactivé au niveau de la passerelle pour rétablir un chemin de résolution unique
et maîtrisé.

> **Méthode de détection.** Comparer, depuis un poste client, le résultat d'une
> résolution forcée vers le serveur local et celui d'une résolution utilisant la
> configuration par défaut. Un écart trahit un contournement.

---

## 5. Reverse proxy et PKI interne

Les services sont exposés derrière un reverse proxy écoutant sur les ports 80 et
443, sous des noms en `.home.arpa` (espace de nommage réservé aux réseaux privés,
RFC 8375). Une réécriture DNS interne fait pointer l'ensemble de ces noms vers le
serveur.

Le proxy **relaie** les connexions, il ne se contente pas de rediriger : le client
dialogue uniquement avec lui, et c'est lui qui ouvre une seconde connexion vers le
service. C'est ce qui permet de terminer TLS d'un côté et de parler en clair de
l'autre, à l'intérieur du réseau Docker.

Le routage s'effectue sur l'**en-tête HTTP `Host`** de la requête, et non sur un
fichier de correspondance. Ce point explique l'incident récurrent décrit
ci-dessous.

### Autorité de certification interne

Une autorité de certification locale a été créée pour émettre un certificat
générique couvrant `*.home.arpa`. Le certificat racine est installé dans le
magasin de confiance des postes et terminaux mobiles, ce qui supprime les
avertissements de sécurité sur l'ensemble des services.

> **Piège rencontré quatre fois : la validation d'en-tête `Host`**
>
> Symptôme : un service refuse les connexions internes (erreur 400, 401 ou
> *Unauthorized*) alors que la connectivité réseau est établie.
>
> Cause : le service est légitimement joignable sous plusieurs noms : le nom de
> domaine interne depuis un navigateur, le nom du conteneur depuis un autre
> service. Beaucoup d'applications refusent par défaut tout nom non déclaré, pour
> se protéger des attaques par en-tête `Host`.
>
> Chaque application nomme ce réglage différemment (`trusted_domains`,
> `ALLOWED_HOSTS`, *Server domains*…), ce qui explique qu'il faille quatre
> rencontres pour reconnaître le motif.

---

## 6. Stockage et sauvegardes

### Montage persistant

Le volume de données est déclaré dans `/etc/fstab` par **UUID** et non par nom de
périphérique : l'ordre d'énumération des disques n'est pas garanti au démarrage,
et un montage par `/dev/sdX` finit par pointer sur le mauvais volume.

L'option `nofail` évite qu'un disque absent bloque le démarrage du système. Sur
un serveur sans écran, un démarrage interrompu en mode secours est une panne
sérieuse.

### Stratégie de sauvegarde

Sauvegarde automatisée quotidienne, déclenchée par `cron`, comportant :

- un export cohérent des bases de données (dumps PostgreSQL) ;
- une synchronisation `rsync` des configurations et des données applicatives ;
- une rotation sur sept jours ;
- une notification de fin de traitement vers la supervision.

La rotation utilise `rsync --link-dest`, qui crée des **liens durs** vers la
sauvegarde précédente pour tout fichier inchangé. Sept jours d'historique
occupent ainsi environ 9 Go au lieu de 30.

> **Corollaire à connaître** : ces sauvegardes sont physiquement interdépendantes.
> Une corruption du système de fichiers peut en affecter plusieurs simultanément.

Le script vérifie que le volume de données est effectivement monté avant de
commencer. Sans ce contrôle, une sauvegarde lancée disque absent écraserait
l'historique par des dossiers vides.

### Test de restauration

Une sauvegarde jamais restaurée est une hypothèse, pas une sauvegarde. La
vérification a été menée en trois niveaux :

**1. Intégrité des exports.** Un dump PostgreSQL valide se termine par une ligne
explicite de fin de sauvegarde. C'est le contrôle décisif : il prouve que
l'export n'a pas été interrompu.

**2. Restauration réelle** dans une base jetable, jamais par-dessus la
production, suivie d'un comptage des enregistrements pour vérifier la cohérence
des données restaurées.

**3. Intégrité des fichiers.** Un contrôle de structure (`file`) sur un document
archivé confirme que le contenu est exploitable, et pas seulement présent avec la
bonne taille.

> **Deux pièges.** `psql` sans option `-d` tente de se connecter à une base
> portant le nom de l'utilisateur ; il faut toujours préciser une base d'entrée
> existante. Et relancer un import sur une base déjà peuplée produit des centaines
> d'erreurs *already exists* : ce n'est pas un export défectueux, c'est une
> restauration en double. Seule une restauration sur base vierge est probante.

---

## 7. Services applicatifs

| Service | Rôle |
|---|---|
| Portail d'accueil | page unique regroupant l'accès à tous les services, avec état en direct |
| Gestion de conteneurs | interface graphique de supervision et de redémarrage |
| Coffre-fort de mots de passe | stockage chiffré auto-hébergé, clients navigateur et mobile |
| Gestion documentaire | archivage de documents avec OCR, indexation plein texte et classement automatique |
| Cloud personnel | synchronisation de fichiers, sauvegarde photo, calendrier et contacts |
| Serveur multimédia | diffusion de la bibliothèque personnelle, transcodage matériel via l'iGPU |

### Points techniques notables

**Accélération matérielle.** Le transcodage vidéo s'appuie sur le GPU intégré, ce
qui suppose d'exposer les périphériques `/dev/dri` au conteneur et d'ajouter
l'utilisateur au groupe propriétaire de ces périphériques. La vérification se
fait dans les journaux applicatifs : le codec employé doit porter le suffixe
matériel, et non correspondre à un encodeur logiciel.

**Limite d'inotify.** Les services qui surveillent des arborescences de fichiers
consomment des *watches* noyau. Le plafond par défaut est vite atteint sur de
grandes bibliothèques, avec pour symptôme une détection de fichiers qui cesse
silencieusement, sans erreur explicite.

**Bases de données.** Plusieurs services s'appuient sur PostgreSQL en conteneur
dédié. Beaucoup de variables d'environnement de ces images ne servent **qu'à
l'initialisation** : une fois la base créée, elles sont ignorées, et toute
modification passe par l'outil d'administration de l'application.

---

## 8. Accès distant

L'accès depuis l'extérieur repose sur un **réseau privé maillé** (WireGuard),
sans aucune ouverture de port sur la box. C'est un choix structurant : la surface
d'exposition sur Internet est nulle.

Le serveur DNS local est déclaré dans la configuration du réseau maillé, ce qui
permet de continuer à utiliser les noms internes depuis l'extérieur.

> Cette architecture s'est révélée précieuse lors d'un incident : un
> auto-bannissement par le système de détection d'intrusion a coupé l'accès SSH
> depuis le réseau local, mais le réseau maillé restait joignable, le trafic
> arrivant par une interface différente, non visée par les règles de filtrage. Un
> chemin d'accès de secours indépendant du chemin filtré n'est pas un luxe.

---

## 9. Supervision et alerting

### Deux niveaux complémentaires

**Supervision de disponibilité.** Sondes périodiques sur chaque service
(requête DNS, requête HTTP, ping), avec notification par messagerie instantanée
en cas d'indisponibilité. Répond à la question « est-ce cassé ? ».

**Métrologie.** Collecte de métriques système et conteneur par un système de
séries temporelles, visualisation et alerting. Répond à la question « pourquoi,
et depuis quand ? ».

L'architecture de collecte est en **mode *pull*** : le collecteur interroge des
exportateurs à intervalle régulier. Un avantage pratique : une source injoignable
est immédiatement visible comme telle, sans configuration supplémentaire.

### Tableau de bord et ligne de base

Plutôt que d'utiliser les tableaux de bord communautaires, exhaustifs mais
conçus pour n'importe quel serveur, un tableau dédié de huit panneaux a été
construit : température processeur, espace disque sur les deux volumes, mémoire
disponible, mémoire des bases de données, charge processeur, attente disque, et
nombre de conteneurs actifs.

**La valeur d'une métrique vient de l'écart à l'état habituel**, pas du chiffre
lui-même. Une ligne de base a donc été relevée en fonctionnement normal, puis
comparée sous charge :

| Métrique | Repos | Sous charge soutenue |
|---|---|---|
| Température processeur | 46 °C | 53–74 °C |
| Charge processeur | 2–3 % | 25–72 % |
| Attente disque (iowait) | 0,1 % | 9–18 % |
| Mémoire disponible | 77–85 % | inchangée |

> **Pièges de métriques à connaître**
>
> - `avail` ≠ `free` sur un système de fichiers : ext4 réserve 5 % à root, seul
>   `avail` reflète l'espace réellement utilisable.
> - `MemAvailable` ≠ `MemFree` : Linux utilise toute la mémoire libre comme cache
>   disque, `MemFree` est donc presque toujours proche de zéro sur un serveur sain.
> - Certaines zones thermiques déclarées par le firmware ne sont reliées à aucun
>   capteur et renvoient une valeur plancher aberrante. Toute agrégation de
>   températures doit être filtrée sur la puce concernée.

### Alerting

Cinq règles d'alerte, chacune assortie d'une **durée de persistance** avant
déclenchement. C'est le mécanisme équivalent aux tentatives multiples d'une sonde de
disponibilité, et qui distingue un pic ponctuel d'une saturation réelle.

Deux principes appliqués :

- les états *NoData* et *Error* ne sont pas ramenés à *OK* : une métrique qui
  disparaît est un incident en soi ;
- le message d'alerte contient le **premier geste à effectuer** et la valeur de
  référence. Six mois plus tard, le contexte n'est plus présent à l'esprit.

> **Limite identifiée** : l'exportateur système, exécuté en conteneur, lit les
> statistiques réseau dans son propre espace de noms. Les métriques réseau
> remontées ne sont donc pas celles de l'hôte. Correction possible : exécuter cet
> exportateur en mode `host` et adapter la cible de collecte.

---

## 10. Segmentation réseau (VLAN)

Volet réalisé sur un switch Cisco Catalyst d'occasion, puis démonté
volontairement : l'équipement, conçu pour une baie technique, est trop bruyant
pour une pièce de vie. La configuration et les enseignements sont conservés.

### Remise à zéro d'un équipement d'occasion

L'équipement contenait encore la configuration complète de son site précédent :
un domaine VTP et une vingtaine de VLAN de production nommés. Ces informations
décrivent une architecture réseau tierce et ne doivent être ni conservées, ni
diffusées.

> **Piège classique** : effacer la configuration de démarrage n'efface **pas** les
> VLAN, stockés séparément dans un fichier dédié de la mémoire flash. Sans
> suppression explicite de ce fichier, l'intégralité des VLAN réapparaît après
> redémarrage, ce qui donne l'impression d'une remise à zéro qui a échoué.

Deux réglages hérités à neutraliser après reset : le protocole de propagation de
VLAN, qui repasse en mode serveur par défaut et peut écraser la base locale si un
autre équipement est branché ; et les serveurs web d'administration, actifs par
défaut et inutiles dès lors que l'on administre en ligne de commande.

### Notions mises en œuvre

**VLAN.** Découpage d'un équipement physique en plusieurs domaines de diffusion
indépendants. Deux machines sur le même switch mais dans des VLAN distincts ne se
voient pas plus que si elles étaient sur deux équipements séparés.

**Mode *access* et mode *trunk*.** Un port d'accès appartient à un seul VLAN et
transporte des trames non marquées ; un port trunk transporte plusieurs VLAN sur
un seul câble, en insérant dans chaque trame une étiquette de 4 octets définie
par la norme **IEEE 802.1Q**, contenant l'identifiant du VLAN et un champ de
priorité.

**VLAN natif.** Le VLAN dont les trames circulent sur le trunk **sans**
étiquette. Utilisé ici comme filet de sécurité opérationnel : l'interface
physique du serveur continue de recevoir le réseau existant sans configuration
particulière, ce qui rend la bascule réversible même en cas d'erreur sur les
sous-interfaces.

**Router-on-a-stick.** Un commutateur de niveau 2 ne fait pas passer le trafic
d'un VLAN à l'autre. Le serveur assure ce rôle : il reçoit le trafic étiqueté par
un unique lien trunk, route, et renvoie par le même câble.

**Spanning Tree.** Une boucle de niveau 2 n'a aucun mécanisme d'arrêt comparable
au TTL des paquets IP : une trame de diffusion tourne indéfiniment et sature le
réseau en quelques secondes. STP bloque volontairement les liens redondants pour
ne laisser qu'un chemin actif. Conséquence pratique : un port met une trentaine
de secondes à devenir opérationnel, d'où l'activation de `portfast` sur les ports
terminaux, mais **jamais** sur un port relié à un autre commutateur.

### Côté système : sous-interfaces 802.1Q

Le serveur ne dispose que d'une carte réseau. Des sous-interfaces virtuelles sont
créées, une par VLAN, nommées `<interface>.<vlan>`. Ce ne sont pas des cartes
supplémentaires mais des points d'entrée logiques : le noyau ajoute l'étiquette à
l'émission, la retire à la réception, et présente le trafic comme provenant d'une
interface distincte.

L'interface physique conserve sa propre adresse, correspondant au VLAN natif.
Chaque sous-interface porte l'adresse de passerelle de son VLAN. Aucune ne
déclare de route par défaut : plusieurs passerelles par défaut produiraient une
table de routage incohérente.

### Routage et traduction d'adresses

Deux mécanismes indépendants, qu'il ne faut pas confondre :

- **Le routage entre interfaces** est désactivé par défaut sur Linux
  (`net.ipv4.ip_forward`). Sans activation, les paquets destinés à un autre
  réseau sont silencieusement abandonnés.
- **La traduction d'adresses** est nécessaire parce que la passerelle Internet ne
  connaît pas les nouveaux sous-réseaux : sans réécriture de l'adresse source, les
  paquets sortent mais les réponses n'ont aucun chemin de retour.

> **Triple test de validation**, chaque étape vérifiant une couche différente :
> un ping vers la passerelle du VLAN teste l'encapsulation ; un ping vers une
> machine d'un autre VLAN teste le routage ; un ping vers une adresse publique
> teste la traduction d'adresses. Le diagnostic est immédiat.

### Filtrage inter-VLAN

Segmenter sans filtrer ne produit qu'un plan d'adressage compliqué. Le trafic
inter-VLAN transitant par le serveur sans lui être destiné, il relève de la
chaîne `FORWARD` de netfilter.

Difficulté propre à un hôte Docker : le moteur de conteneurs gère lui-même des
règles dans cette chaîne. Modifier sa politique par défaut casserait les
conteneurs. La solution retenue est une **chaîne dédiée**, insérée en tête, qui ne
statue que sur le trafic inter-VLAN et laisse ressortir le reste.

La première règle de cette chaîne autorise les connexions déjà établies. C'est
elle qui rend le filtrage **à état** : une réponse à une requête autorisée est
reconnue comme appartenant à une session existante. Sans elle, il faudrait une
règle inverse pour chaque flux. C'est la différence de fond entre un pare-feu
moderne et une simple liste de contrôle d'accès.

---

## 11. Pare-feu et détection d'intrusion

### Inventorier avant de filtrer

Écrire des règles à partir de suppositions est le meilleur moyen de couper un
service vital. La première étape est un inventaire des ports réellement en écoute
sur l'hôte, en excluant les redirections de conteneurs.

Un enseignement immédiat : les services liés à l'adresse de bouclage sont déjà
inaccessibles depuis le réseau. Aucune règle n'est nécessaire, et surtout aucune
ouverture ne doit être faite.

> **Piège du DHCP.** Une requête DHCP est émise depuis `0.0.0.0` vers
> `255.255.255.255`, puisque le client n'a pas encore d'adresse. Une règle
> restreinte au sous-réseau local ne l'attrape donc **jamais**. Il faut filtrer
> sur l'interface, pas sur l'adresse source. Une erreur ici coupe le réseau de
> tous les utilisateurs sans que la cause soit évidente.

> **Conteneurs et services en mode `host`.** Pour un conteneur, un service
> exécuté en `network_mode: host` est un service *externe*, joint depuis une
> adresse du réseau Docker et non depuis le réseau local. Sans ouverture
> explicite vers les sous-réseaux de conteneurs, ce service devient injoignable
> depuis le reverse proxy et les sondes de supervision.

### Le point aveugle : le moteur de conteneurs contourne le pare-feu

C'est l'enseignement principal de cette partie, et il se démontre en une commande.
Pare-feu actif, politique par défaut en refus, aucune règle n'autorisant un port
de conteneur, et pourtant le service répond depuis n'importe quelle machine du
réseau.

**Explication** : lorsqu'un port est publié, le moteur de conteneurs écrit une
règle DNAT dans la table `nat`, chaîne `PREROUTING`. Cette table est traversée
**avant** la chaîne `INPUT` où le pare-feu applicatif pose ses règles. Le paquet
est réécrit vers l'adresse interne du conteneur puis poursuit en `FORWARD` : il
ne visite jamais `INPUT`.

Autrement dit, un pare-feu applicatif classique protège les services de l'hôte,
et **uniquement** ceux-là.

> C'est le malentendu le plus répandu sur cette combinaison, et il est dangereux
> parce qu'il produit une confiance injustifiée : on croit avoir fermé le serveur
> alors que la totalité des services conteneurisés reste accessible. À vérifier
> systématiquement par un test réel plutôt qu'à supposer.

La solution consiste à écrire dans la chaîne que le moteur de conteneurs crée
volontairement vide et n'écrase jamais lors de ses reconfigurations. La règle de
suivi de connexions doit impérativement y figurer en première position : placée
après une règle de rejet, elle couperait tout le trafic sortant des conteneurs.

**Persistance** : les paquets de sauvegarde de règles et le pare-feu applicatif
sont en conflit sur Debian : installer l'un désinstalle l'autre. Une insertion
dans les fichiers de règles du pare-feu casse leur structure. La solution retenue
est une **unité systemd ordonnancée après le démarrage du moteur de conteneurs**,
la chaîne cible n'existant pas avant.

### Détection comportementale

Un système de détection d'intrusion analyse les journaux (authentification SSH,
accès du reverse proxy), reconnaît des comportements malveillants au moyen de
scénarios, et produit des décisions de bannissement.

> **Distinction essentielle** : l'agent analyse et décide, mais ne bloque rien.
> C'est un composant séparé, le *bouncer*, qui applique les décisions dans le
> pare-feu. Beaucoup d'installations s'arrêtent à l'agent, voient des alertes
> apparaître, et en concluent à tort qu'elles sont protégées.

Quatre obstacles ont dû être levés pour l'acquisition des journaux, tous
instructifs :

1. **Montage impossible.** On ne peut pas créer un point de montage à
   l'intérieur d'un volume monté en lecture seule.
2. **Binaire absent de l'image.** La lecture du journal système structuré
   n'était pas disponible ; il a fallu rétablir un journal texte classique sur
   l'hôte.
3. **Droits de lecture.** Le fichier d'authentification appartient à un groupe
   système spécifique ; l'identifiant de groupe du conteneur doit correspondre,
   faute de quoi le fichier est ouvert sans erreur mais rien n'en est lu.
4. **Format d'horodatage.** Les versions récentes du service de journalisation
   écrivent en ISO 8601 avec microsecondes, alors que les analyseurs attendent le
   format syslog traditionnel. Aucune ligne n'était reconnue.

> **Lecture des métriques d'acquisition.** Un taux élevé de lignes non analysées
> n'est pas nécessairement une anomalie : les analyseurs essaient plusieurs motifs
> et échouent sur ceux qui ne correspondent pas. Ce qui compte est que les lignes
> pertinentes soient, elles, correctement reconnues.

### Validation par bannissement volontaire

Un dispositif de détection ne peut être considéré comme fonctionnel qu'après
l'avoir vu se déclencher. La liste blanche intégrée écartant les plages d'adresses
privées, comportement souhaitable en production, elle a été temporairement
désactivée pour le test, puis rétablie.

Résultat : deux scénarios déclenchés sur des tentatives d'authentification
répétées, décision de bannissement produite, et **coupure effective de l'accès**
une fois le composant d'application actif. La chaîne complète (acquisition,
analyse, scénario, décision, application) est vérifiée.

> **Filet de sécurité systématique** avant toute manipulation de pare-feu à
> distance : programmer à l'avance l'arrêt du dispositif (`at`). C'est ce qui a
> permis de récupérer l'accès après l'auto-bannissement. Penser à supprimer la
> tâche ensuite : une tâche oubliée a désactivé le pare-feu silencieusement
> quelques minutes plus tard.

### Vérification après redémarrage

Un dispositif de sécurité qui ne survit pas à un redémarrage n'existe pas. Le
contrôle complet (pare-feu actif, chaîne de filtrage peuplée dans le bon ordre,
composants de détection en fonctionnement, conteneurs démarrés) a été effectué
après reboot volontaire.

> **Effet de bord à anticiper** : l'ajout d'un conteneur modifie le nombre total
> de conteneurs attendus. L'alerte reposant sur un seuil en dur devait être
> ajustée, faute de quoi elle ne se serait plus jamais déclenchée. Le rappel avait
> été inscrit dans le message de l'alerte elle-même, ce qui a permis d'y penser.

---

## 12. Incidents notables

### Coupure de courant

Une coupure nocturne a arrêté le serveur, qui n'est pas reparti automatiquement :
l'option de redémarrage sur retour du secteur n'était pas activée dans le firmware.

Au redémarrage manuel, l'alerte de supervision sur le nombre de conteneurs s'est
déclenchée : un conteneur manquait. Diagnostic : ce service, créé initialement
pour un test puis intégré à la production, était le **seul** sans politique de
redémarrage automatique.

Conséquence concrète : le service en question synchronisait un paramètre réseau
renouvelé périodiquement. Vingt heures d'écart s'étaient accumulées sans que rien
ne le signale, avec un impact mesurable sur les performances.

> **Enseignements.** Activer le redémarrage automatique sur retour du secteur ;
> auditer les politiques de redémarrage de tous les conteneurs d'un seul coup
> plutôt qu'au cas par cas ; et constater qu'une alerte sur un simple compteur,
> apparemment triviale, est ce qui a permis de détecter l'incident.

### Contention disque

Des artefacts d'image sont apparus lors de la lecture d'un fichier vidéo à très
haut débit. Le tableau de bord a immédiatement orienté le diagnostic : l'attente
disque était passée de 0,1 % à 18 %, avec une charge processeur multipliée par
vingt.

Cause : le stockage de données, relié en USB, devait simultanément servir une
lecture à haut débit et une vérification d'intégrité lancée en parallèle. Ni le
fichier, ni le réseau, ni le client n'étaient en cause. C'était un **conflit
d'accès au stockage**.

> C'est précisément le scénario que la métrique d'attente disque était censée
> détecter, et l'utilité de la ligne de base : sans point de comparaison, 18 %
> n'aurait rien signifié.

---

## 13. Limites connues

Énoncées explicitement, parce qu'une architecture dont on ne voit aucune faiblesse
est une architecture mal comprise.

**Point unique de défaillance.** Le serveur porte le DNS et le DHCP de tout le
réseau. Son indisponibilité prive l'ensemble des utilisateurs de résolution de
noms. Une procédure de retour arrière documentée permet de rebasculer sur la box
en quelques minutes, mais elle est manuelle.

**Sauvegardes non délocalisées.** Le dispositif protège contre l'erreur humaine,
la corruption logicielle et la panne d'un service. Il ne protège ni de
l'incendie, ni du vol, ni d'un rançongiciel qui chiffrerait le serveur dans son
ensemble. La règle 3-2-1 n'est satisfaite qu'à moitié, et c'est le prochain
chantier prioritaire.

**Stockage.** Le volume de données est relié en USB, ce qui constitue le maillon
faible mesuré en conditions réelles.

**Plan de management du matériel réseau.** Le commutateur ne négocie que des
algorithmes cryptographiques obsolètes pour son administration à distance, et ne
reçoit plus de correctifs depuis plus d'une décennie. Rétablir la compatibilité
suppose de réactiver des mécanismes considérés comme cassés : illustration
concrète du coût, en sécurité, du maintien de matériel amorti.

**Exposition réelle.** Aucun port n'est ouvert sur Internet et l'accès distant
passe exclusivement par un réseau privé maillé. Les dispositifs de détection
d'intrusion mis en place protègent principalement contre des attaques venues
d'Internet, que cette installation ne subit pas. Leur valeur ici est
essentiellement pédagogique, mais les mécanismes appris sont directement
transposables à une infrastructure exposée.

---

## Méthode de travail

Trois principes se sont dégagés au fil du projet, et ils valent plus que la liste
des services déployés :

**Documenter les échecs autant que les succès.** Le journal de bord d'origine
consacre plus de place aux pièges rencontrés qu'aux commandes qui ont fonctionné.
C'est ce qui permet de reconnaître un motif à la quatrième occurrence plutôt que
de rechercher la même solution quatre fois.

**Écrire le plan de retour arrière avant l'intervention.** Systématiquement, pour
tout changement affectant un service en production.

**Tester les dispositifs de sécurité en les faisant échouer.** Une sauvegarde
jamais restaurée, une alerte jamais déclenchée, un filtrage jamais vu bloquer :
ce sont trois hypothèses, pas trois protections.

---

*Documentation rédigée à partir d'un journal de bord tenu tout au long du projet.
Adresses, identifiants et noms d'hôtes remplacés par des valeurs génériques.*
