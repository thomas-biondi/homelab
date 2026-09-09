# Requetes PromQL du tableau de bord

Huit panneaux, choisis pour repondre en dix secondes a la question « est-ce que
tout va bien ? ». Les tableaux de bord communautaires importes restent
disponibles pour l'investigation, mais ils sont concus pour n'importe quel
serveur : on y cherche, on n'y surveille pas.

| Panneau | Requete |
|---|---|
| Temperature CPU | `max(node_hwmon_temp_celsius{chip=~".*coretemp.*"})` |
| Disque systeme libre | `100 * node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}` |
| Volume de donnees libre | idem avec `mountpoint="/mnt/data"` |
| Memoire disponible | `100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` |
| Memoire des bases | `container_memory_working_set_bytes{name=~"..."}` |
| Conteneurs actifs | `count(container_last_seen{name!=""})` |
| Charge CPU | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Attente disque | `avg(rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100` |

## Le motif `rate` sur un compteur

`node_cpu_seconds_total` est un compteur : un nombre de secondes passees dans
chaque mode depuis le demarrage, qui ne fait qu'augmenter. Sa valeur brute ne
signifie rien. `rate(...[5m])` calcule sa pente moyenne sur cinq minutes, soit
« combien de secondes d'inactivite par seconde ecoulee », un nombre entre 0 et 1
par coeur. `avg()` moyenne les threads, et l'on retranche de 100 pour convertir
l'inactivite en occupation.

## Pieges de metriques

**`avail` n'est pas `free`.** Ext4 reserve 5 % du volume a root pour qu'un disque
sature reste reparable. Seul `avail` reflete l'espace reellement utilisable.

**`MemAvailable` n'est pas `MemFree`.** Linux emploie toute la memoire inoccupee
comme cache disque : `MemFree` est presque toujours proche de zero sur un serveur
en bonne sante, ce qui inquiete pour rien.

**`working_set_bytes` n'est pas `usage_bytes`.** Le second inclut le cache de
fichiers, que le noyau libere sans difficulte sous pression.

**Capteurs fantomes.** Certaines zones thermiques declarees par le firmware ne
sont reliees a aucun capteur et renvoient une valeur plancher aberrante, de
l'ordre de -263 C. Toute agregation de temperatures doit filtrer sur la puce
concernee, faute de quoi on surveille un capteur inexistant qui ne montera jamais.

## Ligne de base

La valeur d'une metrique vient de l'ecart a l'etat habituel, pas du chiffre
lui-meme. Releve en fonctionnement normal, puis compare sous charge soutenue :

| Metrique | Repos | Sous charge |
|---|---|---|
| Temperature processeur | 46 C | 53 a 74 C |
| Charge processeur | 2 a 3 % | 25 a 72 % |
| Attente disque (iowait) | 0,1 % | 9 a 18 % |
| Memoire disponible | 77 a 85 % | inchangee |

Ces chiffres ont servi une fois en conditions reelles : des artefacts d'image en
lecture video ont ete diagnostiques en quelques secondes comme un conflit d'acces
au stockage, l'attente disque etant passee de 0,1 % a 18 %. Sans point de
comparaison, 18 % n'aurait rien signifie.

## Alerting

Cinq regles, chacune assortie d'une duree de persistance avant declenchement.
Deux principes :

- les etats *NoData* et *Error* ne sont pas ramenes a *OK* : une metrique qui
  disparait est un incident en soi ;
- le message contient le premier geste a effectuer et la valeur de reference.
  Six mois plus tard, le contexte n'est plus present a l'esprit.
