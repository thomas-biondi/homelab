# Segmentation reseau

Volet realise sur un commutateur Cisco Catalyst d'occasion, puis demonte
volontairement : l'equipement, concu pour une baie technique, est trop bruyant
pour une piece de vie. La configuration est conservee pour etre rejouee.

## Architecture

Montage dit *router-on-a-stick* : le commutateur est un equipement de niveau 2 et
ne fait pas passer le trafic d'un VLAN a l'autre. Le serveur assure ce role, en
recevant le trafic etiquete par un unique lien trunk.

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
              |-- <interface>        192.168.1.x   VLAN natif, non etiquete
              |-- <interface>.10     192.168.10.1  passerelle VLAN donnees
              |-- <interface>.20     192.168.20.1  passerelle VLAN voix
              |-- <interface>.30     192.168.30.1  passerelle VLAN IoT
```

## Cote systeme

Le serveur ne dispose que d'une carte reseau. Des sous-interfaces virtuelles sont
creees, une par VLAN. Ce ne sont pas des cartes supplementaires mais des points
d'entree logiques : le noyau ajoute l'etiquette a l'emission, la retire a la
reception, et presente le trafic comme provenant d'une interface distincte.

```
auto <interface>.10
iface <interface>.10 inet static
    address 192.168.10.1/24
    vlan-raw-device <interface>
```

Aucune sous-interface ne declare de passerelle : plusieurs routes par defaut
produiraient une table de routage incoherente.

## Routage et traduction d'adresses

Deux mecanismes independants qu'il ne faut pas confondre.

```bash
# Le routage entre interfaces est desactive par defaut sur Linux :
# sans activation, les paquets destines a un autre reseau sont abandonnes.
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-routing.conf

# La passerelle Internet ne connait pas les nouveaux sous-reseaux : sans
# reecriture de l'adresse source, les paquets sortent mais les reponses
# n'ont aucun chemin de retour.
sudo iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o <interface> -j MASQUERADE
```

**Triple test de validation**, chaque etape verifiant une couche differente :

| Test | Ce qu'il valide |
|---|---|
| ping vers la passerelle du VLAN | encapsulation 802.1Q et sous-interface |
| ping vers un autre VLAN | routage (`ip_forward`) |
| ping vers une adresse publique | traduction d'adresses |

## Filtrage inter-VLAN

Segmenter sans filtrer ne produit qu'un plan d'adressage complique.

Difficulte propre a un hote Docker : le moteur de conteneurs gere lui-meme des
regles dans `FORWARD`. Modifier sa politique par defaut casserait les conteneurs.
La solution retenue est une chaine dediee, inseree en tete, qui ne statue que sur
le trafic inter-VLAN et laisse ressortir le reste.

```bash
iptables -N VLAN-FILTER
iptables -I FORWARD 1 -j VLAN-FILTER

# En premier : rend le filtrage a etat. Sans elle, il faudrait une regle
# inverse pour chaque flux autorise.
iptables -A VLAN-FILTER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

# L'IoT sort sur Internet mais ne parle a personne en interne.
iptables -A VLAN-FILTER -i <interface>.30 -o <interface>.10 -j DROP
iptables -A VLAN-FILTER -i <interface>.30 -o <interface>.20 -j DROP
iptables -A VLAN-FILTER -i <interface>.30 -o <interface>    -j RETURN
```

La cible `RETURN` renvoie vers la chaine appelante sans decision definitive : le
paquet poursuit son parcours normal, y compris a travers les regles de Docker.

## Notes de configuration

**`spanning-tree portfast`** sur les ports terminaux, jamais vers un autre
commutateur. Sans lui, chaque redemarrage du serveur coute une trentaine de
secondes de silence reseau, pendant lesquelles le DNS et le DHCP du reseau sont
injoignables. Avec lui sur un lien inter-commutateur, on desactive la protection
contre les boucles.

**`switchport trunk allowed vlan`** limite explicitement les VLAN traversant le
lien. Un trunk qui autorise tout par defaut est une porte ouverte inutile.

**Adresse de management hors plage DHCP**, sans quoi un bail attribue a un poste
entre en conflit avec le commutateur, avec des symptomes intermittents penibles
a diagnostiquer.
