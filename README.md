# PHARMACy

Crude script. It will be re-writen soon with json config parsing and interactive options.

This script will automate the setup of a Raspberry Pi to serve as:
* Adblocker (Pihole)
* VPN (PiVPN)
* NAS (SAMBA)
* Media Center (MiniDLNA + Plex + Jellyfin)
* Media Agregator (Radarr + Sonarr + Lidarr + Readarr + Bazarr + Jackett)
* Media Downloader (NZBGet + Deluge)

Adititionally:
* Nginx will be set up to serve every service through local domain names (Using Pihole DNS).
* Since we have Nginx available, it will be set up to serve Pihole web dashboard as well.
* PHP will be needed for Pihole web dashboard, so we will also set it up with Nginx serve private web pages.
* UFW and Fail2Ban will be installed for security hardening
* Some quality of life changes will be made (Zsh, Neofetch, Vim)