# Supervision

Deux niveaux complementaires, qui ne repondent pas a la meme question.

**Disponibilite** : sondes periodiques sur chaque service, avec notification en
cas d'indisponibilite. Repond a « est-ce casse ? ».

**Metrologie** : collecte de metriques systeme et conteneur en series
temporelles, visualisation et alerting. Repond a « pourquoi, et depuis quand ? ».

L'architecture de collecte est en mode *pull* : le collecteur interroge des
exportateurs a intervalle regulier. Avantage pratique, une source injoignable est
immediatement visible comme telle.

## Contenu

| Fichier | Description |
|---|---|
| `dashboard.json` | Tableau de bord de huit panneaux, importable tel quel |
| `alerting.yaml` | Cinq regles d'alerte, avec seuils et durees de persistance |
| `queries.md` | Les requetes commentees, les pieges de metriques, la ligne de base |

Les identifiants de source de donnees et le point de contact de notification sont
propres a l'installation et remplaces par des valeurs generiques.

## Import

Tableau de bord : Dashboards, New, Import, coller le contenu de `dashboard.json`,
puis selectionner la source de donnees.

Regles d'alerte : le fichier suit le format de provisionnement. Le deposer dans
`/etc/grafana/provisioning/alerting/`, ou le reimporter via l'interface.

Le fichier `dashboard.json` est l'export brut de Grafana (Dashboard settings,
JSON Model). Avant publication, deux valeurs sont a verifier : le nom de la
source de donnees, propre a l'installation, et le titre du tableau de bord.
