# Segmentation réseau

Volet réalisé sur un commutateur Cisco Catalyst d'occasion, puis démonté
volontairement : l'équipement, conçu pour une baie technique, est trop bruyant
pour une pièce de vie. La configuration est conservée pour être rejouée.

## Architecture

Montage dit *router-on-a-stick* : le commutateur est un équipement de niveau 2 et
ne fait pas passer le trafic d'un VLAN à l'autre. Le serveur assure ce rôle, en
recevant le trafic étiqueté par un unique lien trunk.

```
Internet
   |
Passerelle ---- Gi0/1 (access, VLAN 1)
                  |
            [ Commutateur ]
                  |
               Gi0/2 (trunk 802.1Q, VLAN natif 1)
                  |
            Serveur Linux
              |-- <interface>        192.168.1.x   VLAN natif, non étiqueté
              |-- <interface>.10     192.168.10.1  passerelle VLAN données
              |-- <interface>.20     192.168.20.1  passerelle VLAN voix
              |-- <interface>.30     192.168.30.1  passerelle VLAN IoT
```

## Côté système

Le serveur ne dispose que d'une carte réseau. Des sous-interfaces virtuelles sont
créées, une par VLAN. Ce ne sont pas des cartes supplémentaires mais des points
d'entrée logiques : le noyau ajoute l'étiquette à l'émission, la retire à la
réception, et présente le trafic comme provenant d'une interface distincte.

```
auto <interface>.10
iface <interface>.10 inet static
    address 192.168.10.1/24
    vlan-raw-device <interface>
```

Aucune sous-interface ne déclare de passerelle : plusieurs routes par défaut
produiraient une table de routage incohérente.

## Routage et traduction d'adresses

Deux mécanismes indépendants qu'il ne faut pas confondre.

```bash
# Le routage entre interfaces est désactivé par défaut sur Linux :
# sans activation, les paquets destinés à un autre réseau sont abandonnés.
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-routing.conf

# La passerelle Internet ne connaît pas les nouveaux sous-réseaux : sans
# réécriture de l'adresse source, les paquets sortent mais les réponses
# n'ont aucun chemin de retour.
sudo iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o <interface> -j MASQUERADE
```

**Triple test de validation**, chaque étape vérifiant une couche différente :

| Test | Ce qu'il valide |
|---|---|
| ping vers la passerelle du VLAN | encapsulation 802.1Q et sous-interface |
| ping vers un autre VLAN | routage (`ip_forward`) |
| ping vers une adresse publique | traduction d'adresses |

## Filtrage inter-VLAN

Segmenter sans filtrer ne produit qu'un plan d'adressage compliqué.

Difficulté propre à un hôte Docker : le moteur de conteneurs gère lui-même des
règles dans `FORWARD`. Modifier sa politique par défaut casserait les conteneurs.
La solution retenue est une chaîne dédiée, insérée en tête, qui ne statue que sur
le trafic inter-VLAN et laisse ressortir le reste.

```bash
iptables -N VLAN-FILTER
iptables -I FORWARD 1 -j VLAN-FILTER

# En premier : rend le filtrage à état. Sans elle, il faudrait une règle
# inverse pour chaque flux autorisé.
iptables -A VLAN-FILTER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

# L'IoT sort sur Internet mais ne parle à personne en interne.
iptables -A VLAN-FILTER -i <interface>.30 -o <interface>.10 -j DROP
iptables -A VLAN-FILTER -i <interface>.30 -o <interface>.20 -j DROP
iptables -A VLAN-FILTER -i <interface>.30 -o <interface>    -j RETURN
```

La cible `RETURN` renvoie vers la chaîne appelante sans décision définitive : le
paquet poursuit son parcours normal, y compris à travers les règles de Docker.

## Notes de configuration

**`spanning-tree portfast`** sur les ports terminaux, jamais vers un autre
commutateur. Sans lui, chaque redémarrage du serveur coûte une trentaine de
secondes de silence réseau, pendant lesquelles le DNS et le DHCP du réseau sont
injoignables. Avec lui sur un lien inter-commutateur, on désactive la protection
contre les boucles.

**`switchport trunk allowed vlan`** limite explicitement les VLAN traversant le
lien. Un trunk qui autorise tout par défaut est une porte ouverte inutile.

**Adresse de management hors plage DHCP**, sans quoi un bail attribué à un poste
entre en conflit avec le commutateur, avec des symptômes intermittents pénibles
à diagnostiquer.
