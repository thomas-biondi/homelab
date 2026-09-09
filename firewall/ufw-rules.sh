#!/bin/bash
# Regles du pare-feu applicatif, portant uniquement sur les services de l'hote.
# Les regles sont ecrites avant activation : "ufw show added" permet de tout
# relire sans rien appliquer.

# Politique par defaut. Le trafic sortant reste autorise, sans quoi les
# conteneurs ne peuvent plus rien joindre.
ufw default deny incoming
ufw default allow outgoing

# Le tunnel prive est considere de confiance dans son ensemble : c'est ce qui
# preserve l'acces distant a tous les services, y compris en cas de blocage
# sur l'adresse locale.
ufw allow in on <interface_vpn>

ufw allow from 192.168.1.0/24 to any port 22 proto tcp
ufw allow from 192.168.1.0/24 to any port 53
ufw allow from 192.168.1.0/24 to any port 8080 proto tcp
ufw allow <port_vpn>/udp

# DHCP : une requete est emise depuis 0.0.0.0 vers 255.255.255.255, le client
# n'ayant pas encore d'adresse. Une regle restreinte au sous-reseau ne
# l'attrape jamais. Il faut filtrer sur l'interface, pas sur la source.
ufw allow in on <interface> to any port 67 proto udp

# Pour un conteneur, un service en network_mode: host est un service externe,
# joint depuis une adresse du reseau Docker. Sans ces deux regles, le service
# DNS devient injoignable depuis le reverse proxy et les sondes de supervision.
ufw allow from 172.16.0.0/12 to any port 8080 proto tcp
ufw allow from 172.16.0.0/12 to any port 53

ufw enable
