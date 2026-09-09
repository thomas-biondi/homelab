# Supervision

Deux niveaux complémentaires, qui ne répondent pas à la même question.

**Disponibilité** : sondes périodiques sur chaque service, avec notification en
cas d'indisponibilité. Répond à « est-ce cassé ? ».

**Métrologie** : collecte de métriques système et conteneur en séries
temporelles, visualisation et alerting. Répond à « pourquoi, et depuis quand ? ».

L'architecture de collecte est en mode *pull* : le collecteur interroge des
exportateurs à intervalle régulier. Avantage pratique, une source injoignable est
immédiatement visible comme telle.

## Contenu

| Fichier | Description |
|---|---|
| `dashboard.json` | Tableau de bord de huit panneaux, importable tel quel |
| `alerting.yaml` | Cinq règles d'alerte, avec seuils et durées de persistance |
| `queries.md` | Les requêtes commentées, les pièges de métriques, la ligne de base |

Les identifiants de source de données et le point de contact de notification sont
propres à l'installation et remplacés par des valeurs génériques.

## Import

Tableau de bord : Dashboards, New, Import, coller le contenu de `dashboard.json`,
puis sélectionner la source de données.

Règles d'alerte : le fichier suit le format de provisionnement. Le déposer dans
`/etc/grafana/provisioning/alerting/`, ou le réimporter via l'interface.
