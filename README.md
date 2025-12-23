# Apache Guacamole – Install & Upgrade Script

Installations- und Upgrade-Skripte für **Apache Guacamole 1.6.0** auf
Debian-basierten Linux-Systemen (Ubuntu, Debian, Mint, Kali, Raspbian).

Dieses Repository basiert auf dem bekannten `guac-install` Script
(MysticRyuujin) und wurde für eigene Deployments angepasst und dokumentiert.

Repository:  
https://github.com/Riveria-IT/install_guacamole.git

---

## Projektstatus

Dieses Projekt wird **nicht mehr aktiv weiterentwickelt**.

- ❌ Keine aktive Wartung
- ✅ Pull Requests möglich
- ✅ Issues erlaubt
- ❌ Repository ist **nicht** archiviert

⚠️ **Wichtig:**  
Das Script funktioniert weiterhin zuverlässig, erfordert aber bei
neueren Systemen (z. B. Ubuntu 22.04 + Tomcat9) **manuelle Nacharbeit**,
insbesondere bei **MFA / 2FA**.

---

## Unterstützte Systeme

Getestet und lauffähig auf:

- Ubuntu 16.04 oder neuer  
- Debian 10 (Buster)
- Linux Mint 18 / LMDE 4 oder neuer
- Raspbian
- Kali Linux

Nicht offiziell getestet, aber oft erfolgreich:
- Ubuntu 20.04 / 22.04 (siehe MFA-Hinweise unten)

---

## Funktionsumfang

- Apache Guacamole **1.6.0**
- MySQL lokal oder extern
- Automatische Tomcat-Erkennung  
  (tomcat9 → fallback auf tomcat8 / tomcat7)
- Optional MFA / 2FA:
  - **TOTP** (Google Authenticator, Microsoft Authenticator, Authy)
  - Duo Security

---

## RDP Fixes (falls RDP-Verbindungen Probleme machen)

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

## Installation (interaktiv)

```bash
git clone https://github.com/Riveria-IT/install_guacamole.git
cd install_guacamole
chmod +x guac-install.sh
./guac-install.sh
```

Das Script fragt interaktiv nach:
- MySQL Root Passwort
- Guacamole Datenbank Benutzer + Passwort
- Optional: MFA (TOTP oder Duo)

---

## Nicht-interaktive Installation

```bash
./guac-install.sh --mysqlpwd password --guacpwd password --installmysql --nomfa
```

Kurzform:

```bash
./guac-install.sh -r password -gp password -i -o
```

---

## Zugriff nach Installation

```
http://<HOST_ODER_IP>:8080/guacamole/
```

**Standard Login:**

- Benutzer: `guacadmin`
- Passwort: `guacadmin`

⚠️ **Unbedingt nach dem ersten Login ändern oder deaktivieren!**

---

## MFA / 2FA – WICHTIGER HINWEIS (Ubuntu 22.04 + Tomcat9)

### Das Problem (sehr häufig)

Auf neueren Systemen (z. B. Ubuntu 22.04) passiert Folgendes:

- Das Script **installiert das TOTP-Plugin**
- Guacamole **zeigt im Web keine 2FA-Option**
- Logs enthalten **keine Fehlermeldung**

**Ursache:**  
`GUACAMOLE_HOME` wird nicht explizit gesetzt →  
Tomcat lädt Extensions aus einem anderen Pfad als erwartet.

---

## MFA / 2FA – Manuelle Korrektur (Pflicht bei Problemen)

### 1. GUACAMOLE_HOME für Tomcat setzen

```bash
sudo nano /etc/default/tomcat9
```

Am Ende der Datei hinzufügen:

```bash
GUACAMOLE_HOME=/etc/guacamole
```

---

### 2. TOTP-Plugin manuell installieren

```bash
cd /tmp
wget https://downloads.apache.org/guacamole/1.6.0/binary/guacamole-auth-totp-1.6.0.tar.gz
tar -xzf guacamole-auth-totp-1.6.0.tar.gz
```

```bash
sudo mkdir -p /etc/guacamole/extensions
sudo cp guacamole-auth-totp-1.6.0/guacamole-auth-totp-1.6.0.jar \
        /etc/guacamole/extensions/
```

---

### 3. guacamole.properties korrekt verlinken

```bash
sudo mkdir -p /var/lib/tomcat9/.guacamole
sudo ln -sf /etc/guacamole/guacamole.properties \
           /var/lib/tomcat9/.guacamole/guacamole.properties
```

---

### 4. Tomcat vollständig neu starten

```bash
sudo systemctl daemon-reexec
sudo systemctl restart tomcat9
```

---

### 5. Kontrolle (muss Ausgabe liefern)

```bash
journalctl -u tomcat9 | grep -i totp
```

Erwartete Ausgabe:

```
ExtensionModule -- [totp] TOTP Authentication Backend
```

---

## MFA im Web aktivieren

1. Browser **hart neu laden** (CMD + SHIFT + R)
2. In Guacamole einloggen
3. **Rechts oben auf den Benutzer klicken**
4. **Einstellungen**
5. **Zwei-Faktor-Authentifizierung**
6. QR-Code scannen → Code bestätigen

ℹ️ MFA ist **pro Benutzer**, nicht global.

---

## Notfall: MFA deaktivieren

Falls man sich aussperrt:

```bash
sudo rm /etc/guacamole/extensions/guacamole-auth-totp-1.6.0.jar
sudo systemctl restart tomcat9
```

---

## Reverse Proxy (Nginx / Nginx Proxy Manager)

```nginx
location / {
    proxy_pass http://DEINE_IP_ADRESSE:8080/guacamole/;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    proxy_buffering off;
    proxy_read_timeout 3600;
}
```

---

## Upgrade

```bash
chmod +x guac-upgrade.sh
./guac-upgrade.sh
```

⚠️ **Vor jedem Upgrade ein Backup erstellen!**  
Ältere Versionen wurden nicht umfassend getestet.

---

## Empfehlung für Produktivbetrieb

- Reverse Proxy mit HTTPS
- MFA für alle Admin-Accounts aktivieren
- `guacadmin` deaktivieren oder umbenennen
- Optional: Fail2Ban auf `/api/tokens`
- Logs regelmässig prüfen (`journalctl -u tomcat9`)

---

## Haftungsausschluss

Dieses Script wird **ohne Garantie** bereitgestellt.  
Verwendung auf eigene Verantwortung.

---

© Riveria-IT
