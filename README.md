# Apache Guacamole – Install & Upgrade Script

Installations- und Upgrade-Skripte für Apache Guacamole auf Debian-basierten
Linux-Systemen (Ubuntu, Debian, Mint, Kali, Raspbian).

Repository:
https://github.com/Riveria-IT/install_guacamole.git

---

## Projektstatus

Dieses Projekt wird nicht mehr aktiv weiterentwickelt.

- Keine aktive Wartung
- Pull Requests möglich
- Issues erlaubt
- Repository ist nicht archiviert

---

## Unterstützte Systeme

- Ubuntu 16.04 oder neuer
- Debian 10 (Buster)
- Linux Mint 18 / LMDE 4 oder neuer
- Raspbian
- Kali Linux

---

## Funktionsumfang

- Apache Guacamole 1.6.0
- MySQL lokal oder extern
- Automatische Tomcat-Erkennung
- Optional MFA / 2FA (TOTP oder Duo)

---

## RDP Fixes

### Ubuntu

```bash
sudo add-apt-repository ppa:remmina-ppa-team/remmina-next
sudo apt update
sudo apt install freerdp2-dev freerdp2-x11
```

### Debian

```bash
sudo bash -c 'echo "deb http://deb.debian.org/debian buster-backports main" >> /etc/apt/sources.list.d/backports.list'
sudo apt update
sudo apt -y -t buster-backports install freerdp2-dev libpulse-dev
```

---

## Installation

```bash
git clone https://github.com/Riveria-IT/install_guacamole.git
cd install_guacamole
chmod +x guac-install.sh
./guac-install.sh
```

---

## Nicht interaktive Installation

```bash
./guac-install.sh --mysqlpwd password --guacpwd password --installmysql --nomfa
```

Kurzform:

```bash
./guac-install.sh -r password -gp password -i -o
```

---

## Zugriff

http://<HOST_ODER_IP>:8080/guacamole/

Benutzer: guacadmin  
Passwort: guacadmin

---

## Upgrade

```bash
chmod +x guac-upgrade.sh
./guac-upgrade.sh
```
