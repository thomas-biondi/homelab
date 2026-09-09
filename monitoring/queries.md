# Requêtes PromQL du tableau de bord

Huit panneaux, choisis pour répondre en dix secondes à la question « est-ce que
tout va bien ? ». Les tableaux de bord communautaires importés restent
disponibles pour l'investigation, mais ils sont conçus pour n'importe quel
serveur : on y cherche, on n'y surveille pas.

| Panneau | Requête |
|---|---|
| Température CPU | `max(node_hwmon_temp_celsius{chip=~".*coretemp.*"})` |
| Disque système libre | `100 * node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}` |
| Volume de données libre | idem avec `mountpoint="/mnt/data"` |
| Mémoire disponible | `100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` |
| Mémoire des bases | `container_memory_working_set_bytes{name=~"..."}` |
| Conteneurs actifs | `count(container_last_seen{name!=""})` |
| Charge CPU | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Attente disque | `avg(rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100` |

## Le motif `rate` sur un compteur

`node_cpu_seconds_total` est un compteur : un nombre de secondes passées dans
chaque mode depuis le démarrage, qui ne fait qu'augmenter. Sa valeur brute ne
signifie rien. `rate(...[5m])` calcule sa pente moyenne sur cinq minutes, soit
« combien de secondes d'inactivité par seconde écoulée », un nombre entre 0 et 1
par cœur. `avg()` moyenne les threads, et l'on retranche de 100 pour convertir
l'inactivité en occupation.

## Pièges de métriques

**`avail` n'est pas `free`.** Ext4 réserve 5 % du volume à root pour qu'un disque
saturé reste réparable. Seul `avail` reflète l'espace réellement utilisable.

**`MemAvailable` n'est pas `MemFree`.** Linux emploie toute la mémoire inoccupée
comme cache disque : `MemFree` est presque toujours proche de zéro sur un serveur
en bonne santé, ce qui inquiète pour rien.

**`working_set_bytes` n'est pas `usage_bytes`.** Le second inclut le cache de
fichiers, que le noyau libère sans difficulté sous pression.

**Capteurs fantômes.** Certaines zones thermiques déclarées par le firmware ne
sont reliées à aucun capteur et renvoient une valeur plancher aberrante, de
l'ordre de -263 °C. Toute agrégation de températures doit filtrer sur la puce
concernée, faute de quoi on surveille un capteur inexistant qui ne montera jamais.

## Ligne de base

La valeur d'une métrique vient de l'écart à l'état habituel, pas du chiffre
lui-même. Relevé en fonctionnement normal, puis comparé sous charge soutenue :

| Métrique | Repos | Sous charge |
|---|---|---|
| Température processeur | 46 °C | 53 à 74 °C |
| Charge processeur | 2 à 3 % | 25 à 72 % |
| Attente disque (iowait) | 0,1 % | 9 à 18 % |
| Mémoire disponible | 77 à 85 % | inchangée |

Ces chiffres ont servi une fois en conditions réelles : des artefacts d'image en
lecture vidéo ont été diagnostiqués en quelques secondes comme un conflit d'accès
au stockage, l'attente disque étant passée de 0,1 % à 18 %. Sans point de
comparaison, 18 % n'aurait rien signifié.

## Alerting

Cinq règles, chacune assortie d'une durée de persistance avant déclenchement.
Deux principes :

- les états *NoData* et *Error* ne sont pas ramenés à *OK* : une métrique qui
  disparaît est un incident en soi ;
- le message contient le premier geste à effectuer et la valeur de référence.
  Six mois plus tard, le contexte n'est plus présent à l'esprit.
