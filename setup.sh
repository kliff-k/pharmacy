#!/bin/bash
# shellcheck disable=SC2005,SC2046,SC2086
# SC2005 = Useless echo
# SC2046 = Double quote to prevent word splitting
# SC2086 = Double quote to prevent globbing and word splitting

# --------- VARIABLES ---------

pharmacy_m="\033[1;34m[Pharmacy]\033[0m"

# --------- FUNCTIONS ---------

### Interactive

# Greetings!
do_greeting()
{
	whiptail --title "REMEDy" --msgbox "Welcome to the Raspberry pi Excellent MEDia Center Script\nLet's get started." 8 78
}

# Checks for previous interactive setup values
do_interactive_config_check()
{
	if [ -f "./config/interactive.conf" ]
	then
		if (whiptail --title "REMEDy" --yesno "Partial setup file found.\nDo you want to load the previous values?" 8 78)
		then
			echo "Using previous interactive setup values"
		else
			rm "./config/interactive.config"
		fi
	fi
}

### Setup

# Initial environment setup through raspi-config
do_raspi_config()
{
	if [ "$(config_get enable_ssh)" = "true" ]
	then
		echo -e "${pharmacy_m} Enabling ssh"
		sudo raspi-config nonint do_ssh 0 1> /dev/null
	fi

	if [ -n "$(config_get country_code)" ]
	then
		echo -e "${pharmacy_m} Changing country code ($(config_get country_code))"
		sudo raspi-config nonint do_wifi_country "$(config_get country_code)" 1> /dev/null
	fi

	if [ -n "$(config_get timezone)" ]
	then
		echo -e "${pharmacy_m} Changing timezone ($(config_get timezone))"
		sudo raspi-config nonint do_change_timezone "$(config_get timezone)" 1> /dev/null
	fi

	if [ -n "$(config_get locale)" ]
	then
		echo -e "${pharmacy_m} Changing locale ($(config_get locale))"
		sudo raspi-config nonint do_change_locale "$(config_get locale)" 1> /dev/null
	fi

	if [ -n "$(config_get keyboard)" ]
	then
		echo -e "${pharmacy_m} Changing keyboard layout ($(config_get keyboard))"
		sudo raspi-config nonint do_configure_keyboard "$(config_get keyboard)" 1> /dev/null
	fi

	if [ -n "$(config_get pi_password)" ]
	then
		echo -e "${pharmacy_m} Changing pi user password"
		echo "pi:$(config_get pi_password)" | sudo chpasswd 1> /dev/null
	fi

	if [ -n "$(config_get change_swap_size)" ]
	then
		echo -e "${pharmacy_m} Changing Swap Size"
		sudo dphys-swapfile swapoff 1> /dev/null
		sudo sed -i "s/CONF_SWAPSIZE=100/CONF_SWAPSIZE=$(config_get change_swap_size)/g" /etc/dphys-swapfile
		sudo dphys-swapfile setup 1> /dev/null
		sudo dphys-swapfile swapon 1> /dev/null
	fi

	if [ -n "$(config_get avoid_warnings)" ]
	then
		echo -e "${pharmacy_m} Disabling warnings"
		printf "\n# Disable Under voltage warnings\n"           | sudo tee -a /boot/config.txt 1> /dev/null
		printf "avoid_warnings=%s" $(config_get avoid_warnings) | sudo tee -a /boot/config.txt 1> /dev/null
	fi

	if [ "$(config_get expand_rootfs)" = "true" ]
	then
		echo -e "${pharmacy_m} Expanding rootfs"
		sudo raspi-config nonint do_expand_rootfs 1> /dev/null
	fi

	if [ -n "$(config_get hostname)" ]
	then
		echo -e "${pharmacy_m} Changing hostname ($(config_get hostname))"
		sudo raspi-config nonint do_hostname "$(config_get hostname)" 1> /dev/null
	fi

	if (whiptail --title "REMEDy" --yesno "It is recommended to reboot your Pi after changing raspi-config values.\nRestart now?" 8 78)
	then
		echo -e "${pharmacy_m} Rebooting"
		sudo reboot
	fi
}

# Manage additional users
do_manage_users()
{
	if [ -n "$(config_get users)" ]
	then 
		echo -e "${pharmacy_m} Setting up users"
		for users in $(echo "$(config_get users)" | tr "," "\n")
		do
			IFS=':'
			read -ra user <<< "${users}"
			unset IFS
			sudo adduser --disabled-password --gecos "" "${user[0]}" 
			sudo chpasswd <<< "${user[0]}:${user[1]}"
		done
	fi

	if [ -n "$(config_get sudo_users)" ]
	then 
		echo -e "${pharmacy_m} Setting up sudoers"
		for sudoers in $(echo "$(config_get sudo_users)" | tr "," "\n")
		do
			IFS=':'
			read -ra sudoer <<< "${sudoers}"
			unset IFS
			echo "${sudoer[0]} ALL=(ALL) ${sudoer[1]/nopasswd/NOPASSWD:}ALL" | sudo tee -a "/etc/sudoers.d/010_${sudoer[0]}" 1> /dev/null
		done
	fi
}

# Include keys, sources, updates, upgrades and installs packages
do_manage_packages()
{
	echo -e "${pharmacy_m} Setting up packages"
	for package in $(echo "$(config_get packages)" | tr "," "\n")
	do
		packages="${packages} ${package}"
	done

	echo -e "${pharmacy_m} Setting up repos"
	for package in $(echo "$(config_get add_repo)" | tr "," "\n")
	do
		curl -sSL "$(config_get ${package}_key)" | sudo apt-key add 
		echo "$(config_get ${package}_repo)"     | sudo tee "/etc/apt/sources.list.d/${package}.list"
	done

	echo -e "${pharmacy_m} Setting up selections"
	IFS=$'\n'
	for selection in $(echo "$(config_get apt_selections)" | tr "," "\n")
	do
		unset IFS
		sudo debconf-set-selections <<< "${selection}"
	done

	echo -e "${pharmacy_m} Updating package list"
	sudo apt update -y

	echo -e "${pharmacy_m} Upgrading packages"
	sudo apt upgrade -y

	echo -e "${pharmacy_m} Installing new packages"
	DEBIAN_FRONTEND=noninteractive sudo apt install -y ${packages}

	echo -e "${pharmacy_m} Running auto remove"
	sudo apt autoremove -y

	echo -e "${pharmacy_m} Running auto clean"
	sudo apt autoclean -y
}

# Run the service installers
do_manage_installers()
{
	for installer in $(echo "$(config_get installers)" | tr "," "\n")
	do
		if [ "${installer}" = "pihole" ]
		then
			echo -e "${pharmacy_m} Installing PiHole"
			if [ -z "${configPath}" ]
			then
				curl -sSL "$(config_get pihole_url)" | bash
			else
				sudo mkdir /etc/pihole && sudo install -o root -g root -m 644 "$(config_get pihole_setup_vars)" /etc/pihole/setupVars.conf
				curl -sSL "$(config_get pihole_url)" | sudo bash /dev/stdin --unattended
			fi
		fi

		if [ "${installer}" = "pivpn" ]
		then
			echo -e "${pharmacy_m} Installing PiVpn"
			if [ -z "${configPath}" ]
			then
				curl -sSL "$(config_get pivpn_url)" | bash 
			else
				curl -sSL "$(config_get pivpn_url)" | sudo bash /dev/stdin --unattended "$(config_get pivpn_setup_vars)"
			fi
		fi
	done
}

# Fetches, decompress and move every non-packaged application to it's destination
do_manage_archives()
{
	echo -e "${pharmacy_m} Setting up archives"
	for archive in $(echo "$(config_get archives)" | tr "," "\n")
	do
		# shellcheck disable=SC2001 # I need sed here
		echo -e "${pharmacy_m} $(echo "${archive}" | sed 's/.*/\u&/')"
		curl -sL "$(config_get ${archive}_url)" -o "/tmp/${archive}_compressed"
		if [ "${archive}" = "bazarr" ]
		then
			# shellcheck disable=SC2001 # I need sed here
			sudo unzip -qq "/tmp/${archive}_compressed" -d "/tmp/$(echo "${archive}" | sed 's/.*/\u&/')"
		else
			sudo tar -xzf "/tmp/${archive}_compressed" -C "/tmp/"
		fi
		# shellcheck disable=SC2001 # I need sed here
		sudo mv "/tmp/$(echo "${archive}" | sed 's/.*/\u&/')" "$(config_get archive_install_path)/${archive}"
		sudo chown -R "$(config_get admin)":"$(config_get admin)" "$(config_get archive_install_path)/${archive}"
	done
}

# Create unit files for each installed service
do_manage_units()
{
	echo -e "${pharmacy_m} Managing unit files"
	for downloader in $(echo "$(config_get downloaders)" | tr "," "\n")
	do
		downloaders="${downloaders}${downloader}.service "
	done

	for collector in $(echo "$(config_get collectors)" | tr "," "\n")
	do
		collectors="${collectors}${collector}.service "
	done

	for unit in $(echo "$(config_get unit)" | tr "," "\n")
	do
		sudo install -o root -g root -m 644 "./etc/systemd/system/${unit}.service" "/etc/systemd/system/${unit}.service"
		sudo sed -i "s/{admin}/$(config_get admin)/g" "/etc/systemd/system/${unit}.service"
		sudo sed -i "s/{downloaders}/${downloaders}/g" "/etc/systemd/system/${unit}.service"
		sudo sed -i "s/{collectors}/${collectors}/g" "/etc/systemd/system/${unit}.service"
		sudo sed -i "s|{download_path}|$(config_get download_path)|g" "/etc/systemd/system/${unit}.service"
	done
}

# Setup every configuration file for the installed services
do_manage_configs()
{
	echo -e "${pharmacy_m} Configuring packages"
	for package in $(echo "$(config_get packages)" | tr "," "\n")
	do
		if [ "${package}" = 'unbound' ]
		then
			echo -e "${pharmacy_m} ${package}"
			if [ "$(config_get set_unbound_pihole)" = "true" ]
			then
				sudo install -o root -g root -m 644 "./etc/unbound/unbound.conf.d/pi-hole.conf" "/etc/unbound/unbound.conf.d/pi-hole.conf"
				sudo sed -i -e 's/PIHOLE_DNS_1=.*/PIHOLE_DNS_1=127.0.0.1#5335/g' -e 's/PIHOLE_DNS_2=.*/PIHOLE_DNS_2=/g' -e 's/PIHOLE_DNS_3=.*/PIHOLE_DNS_3=::1#5335/g' -e 's/PIHOLE_DNS_4=.*/PIHOLE_DNS_4=/g' /etc/pihole/setupVars.conf
			fi
			if [ "$(config_get disable_unbound_resolv)" = "true" ]
			then
				sudo systemctl disable unbound-resolvconf.service
			fi
		fi	

		if [ "${package}" = 'minidlna' ]
		then
			echo -e "${pharmacy_m} ${package}"
			sudo sed -i "s#media_dir=/var/lib/minidlna#media_dir=PVA,$(config_get media_path)#g" /etc/minidlna.conf
			sudo sed -i "s/#friendly_name=/friendly_name=$(config_get hostname)/g" /etc/minidlna.conf
		fi

		if [ "${package}" = 'neofetch' ]
		then
			echo -e "${pharmacy_m} ${package}"
			for user in $(echo "$(config_get neofetch_users)" | tr "," "\n")
			do
				sudo su ${user} -c neofetch 1> /dev/null
				for info in $(echo "$(config_get neofetch_show)" | tr "," "\n")
				do
					sudo sed -i "/info \".*\" ${info}/s/^#//g" "/home/${user}/.config/neofetch/config.conf"
				done

				for info in $(echo "$(config_get neofetch_hide)" | tr "," "\n")
				do
					sudo sed -i "/info \".*\" ${info}/s/^/#/g" "/home/${user}/.config/neofetch/config.conf"
				done
			done
		fi

		if [ "${package}" = 'zsh' ]
		then
			echo -e "${pharmacy_m} ${package}"
			for user in $(echo "$(config_get zsh_users)" | tr "," "\n")
			do
				sudo chsh -s /bin/zsh "${user}"
			done

			for user in $(echo "$(config_get ohmyzsh_users)" | tr "," "\n")
			do
				ZSH_home="/home/${user}/.oh-my-zsh"
				sudo -u ${user} sh -c "$(curl -fsSL $(config_get ohmyzsh_url))" "" --unattended
				for plugin in $(echo "$(config_get ohmyzsh_plugins)" | tr "," "\n")
				do
					sudo -u $(config_get ohmyzsh_users) git clone --depth=1 "${plugin}" "${ZSH_home}/custom/plugins/$(echo "${plugin}" | sed -e 's#.*/##' -e 's#.git##')"
					sudo sed -i "/plugins=(/s/)$/ $(echo ${theme} | sed -e 's#.*/##' -e 's#.git##'))/g" "/home/${user}/.zshrc"
				done

				for theme in $(echo "$(config_get ohmyzsh_themes)" | tr "," "\n")
				do
					sudo -u $(config_get ohmyzsh_users) git clone --depth=1 "${theme}" "${ZSH_home}/custom/themes/$(echo ${theme} | sed -e 's#.*/##' -e 's#.git##')"
				done

				if [ -n "$(config_get ohmyzsh_active_theme)" ]
				then
					sudo sed -i "s|ZSH_THEME=\".*$|ZSH_THEME=\"$(config_get ohmyzsh_active_theme)\"|g" "/home/${user}/.zshrc"
				fi

				if [ -f "$(config_get copy_zshrc)" ]
				then
					sudo mv "/home/${user}/.zshrc" "/home/${user}/.zshrc_backup"
					sudo install -o "${user}" -g "${user}" -m 644 "$(config_get copy_zshrc)" "/home/${user}/.zshrc"
				fi

				if [ -f "$(config_get copy_p10k)" ]
				then
					sudo mv "/home/${user}/.p10k.zsh" "/home/${user}/.p10k.zsh_backup"
					sudo install -o "${user}" -g "${user}" -m 644 "$(config_get copy_p10k)" "/home/${user}/.p10k.zsh"
				fi
				unset ZSH_home
			done
		fi

		if [ "${package}" = 'fail2ban' ]
		then
			echo -e "${pharmacy_m} ${package}"
			sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
			echo "[ssh]"                                        | sudo tee -a /etc/fail2ban/jail.local 1> /dev/null
			echo "	enabled  = true"                            | sudo tee -a /etc/fail2ban/jail.local 1> /dev/null
			echo "	port     = ssh"                             | sudo tee -a /etc/fail2ban/jail.local 1> /dev/null
			echo "	filter   = sshd"                            | sudo tee -a /etc/fail2ban/jail.local 1> /dev/null
			echo "	logpath  = /var/log/auth.log"               | sudo tee -a /etc/fail2ban/jail.local 1> /dev/null
			echo "	maxretry = $(config_get fail2ban_maxretry)" | sudo tee -a /etc/fail2ban/jail.local 1> /dev/null
			echo "	bantime  = $(config_get fail2ban_bantime)"  | sudo tee -a /etc/fail2ban/jail.local 1> /dev/null
		fi

		if [ "${package}" = 'ufw' ]
		then
			echo -e "${pharmacy_m} ${package}"
			sudo install -o root -g root -m 644 ./etc/ufw/applications.d/* /etc/ufw/applications.d/
			sudo ufw app update PROFILE
			IFS=$'\n'
			for rule in $(echo "$(config_get ufw_allow)" | tr "," "\n")
			do
				unset IFS
				sudo ufw allow "${rule}"
			done
			echo "y" | sudo ufw enable
		fi

		if [ "${package}" = 'jellyfin' ]
		then
			echo -e "${pharmacy_m} ${package}"
			if [ "$(config_get jellyfin_hardware_transcoding)" = "true" ]
			then
				sudo usermod -aG video jellyfin
				printf "\n# More GPU memory for Video Hardware Transcoding (Jellyfin)\n" | sudo tee -a /boot/config.txt 1> /dev/null
				echo "gpu_mem=256"                                                       | sudo tee -a /boot/config.txt 1> /dev/null
				sudo sed -i 's#  <HardwareAccelerationType />#  <HardwareAccelerationType>omx</HardwareAccelerationType>#g' /etc/jellyfin/encoding.xml
			fi
		fi

		if [ "${package}" = 'mdadm' ]
		then
			echo -e "${pharmacy_m} ${package}"
			for device in $(echo "$(config_get mdadm_raid_devices)" | tr "," "\n")
			do
				((DEVICES++))
				DEVICE_NAMES="${DEVICE_NAMES} ${device}"
			done
			sudo mdadm --create --verbose "$(config_get mdadm_md_device)" --level="$(config_get mdadm_level)" --raid-devices="${DEVICES}" "${DEVICE_NAMES}"
			sudo sed -i "/MAILADDR/s/root/$(config_get mdadm_mail_user)/g" /etc/mdadm/mdadm.conf
			sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
			sudo update-initramfs -u
			sudo mkfs.$(config_get mdadm_fs) -v -m .1 -b 4096 -E stride=32,stripe-width=64 $(config_get mdadm_md_device)
			sudo mkdir -p "$(config_get mdadm_path)"
			sudo mount "$(config_get mdadm_md_device)" "$(config_get mdadm_path)"

			DEVICE_UUID=$(sudo blkid | grep $(config_get mdadm_md_device) | cut -d ' ' -f 2 | sed -rn 's/^UUID="(.*)"$/\1/p')

			if [ -z "${DEVICE_UUID}" ] && [ $(config_get mdadm_try_md127) = "true" ]
			then
				DEVICE_UUID=$(sudo blkid | grep /dev/md127 | cut -d ' ' -f 2 | sed -rn 's/^UUID="(.*)"$/\1/p')
			fi

			if [ -z "$DEVICE_UUID" ]
			then
				echo "Device UUID not found"
				exit 1
			fi

			printf "\n# %s Mount\n" $(config_get mdadm_name)                                        | sudo tee -a /etc/fstab
			echo "UUID=${DEVICE_UUID} $(config_get mdadm_path) $(config_get mdadm_fs) defaults 0 0" | sudo tee -a /etc/fstab
			sudo chown -R $(config_get admin):$(config_get admin) "$(config_get mdadm_path)"
			#sudo chmod -R 644 $(config_get mdadm_path) -- Debian defaults should work OK here
		fi

		if [ "${package}" = 'samba' ]
		then
			echo -e "${pharmacy_m} ${package}"
			for samba_user in $(echo "$(config_get samba_users)" | tr "," "\n")
			do
				IFS=':'
				read -ra user <<< "${samba_user}"
				unset IFS
				echo -ne "${user[1]}\n${user[1]}\n" | sudo smbpasswd -a -s "${user[0]}"
				SMB_VALID_USERS="${user[0]},"
			done
			SMB_VALID_USERS=${SMB_VALID_USERS: : -1}
			printf "# %s Share\n" "$(config_get samba_share_name)"   | sudo tee -a /etc/samba/smb.conf 1> /dev/null
			printf "[NAS]\n"                                         | sudo tee -a /etc/samba/smb.conf 1> /dev/null
			printf "path = %s\n" "$(config_get samba_share_path)"    | sudo tee -a /etc/samba/smb.conf 1> /dev/null
			printf "comment = %s\n" "$(config_get samba_share_name)" | sudo tee -a /etc/samba/smb.conf 1> /dev/null
			printf "valid users = %s\n" " ${SMB_VALID_USERS}"        | sudo tee -a /etc/samba/smb.conf 1> /dev/null
			printf "writable = yes\n"                                | sudo tee -a /etc/samba/smb.conf 1> /dev/null
			printf "browsable = yes\n"                               | sudo tee -a /etc/samba/smb.conf 1> /dev/null
			#echo "create mask = 0644\n"                              | sudo tee -a /etc/samba/smb.conf
			#echo "directory mask = 0644"                             | sudo tee -a /etc/samba/smb.conf
		fi

		if [ "${package}" = 'nginx' ]
		then
			echo -e "${pharmacy_m} ${package}"
			if [ -n "$(config_get nginx_proxied_services)" ]
			then
				for service in $(echo "$(config_get nginx_proxied_services)" | tr "," "\n")
				do
					sudo install -o root -g root -m 644 "./etc/nginx/sites-available/${service}" /etc/nginx/sites-available
					sudo sed -i "s/{host_ip}/$(hostname -I | awk '{print $1}')/g" "/etc/nginx/sites-available/${service}"
					sudo sed -i "s/{domain}/$(config_get domain_name)/g" "/etc/nginx/sites-available/${service}"
					echo "$(hostname -I | awk '{print $1}') ${service}.$(config_get domain_name)" | sudo tee -a /etc/pihole/custom.list 1> /dev/null
				done

				sudo install -o root -g root -m 644 "./etc/nginx/snippets/ssl.conf" /etc/nginx/snippets
				sudo install -o root -g root -m 644 "./etc/nginx/snippets/performance.conf" /etc/nginx/snippets
				sudo sed -i "s/{domain}/$(config_get domain_name)/g" /etc/nginx/snippets/ssl.conf
				sudo sed -i "s/# server_names_hash_bucket_size 64;/server_names_hash_bucket_size 64;/g" /etc/nginx/nginx.conf
			fi

			if [ "$(config_get nginx_serve_pihole)" = "true" ]
			then
				sudo chown -R www-data:www-data /var/www/html
				sudo chmod -R 755 /var/www/html
				sudo usermod -aG pihole www-data
			fi

			sudo rm /etc/nginx/sites-enabled/default
			sudo ln -s /etc/nginx/sites-available/* /etc/nginx/sites-enabled
		fi

		if [ "${package}" = "nzbget" ]
		then
			echo -e "${pharmacy_m} ${package}"
			sudo -u "$(config_get admin)" mkdir -p "/home/$(config_get admin)/.config/nzbget"
			sudo install -o "$(config_get admin)" -g "$(config_get admin)" -m 644 /etc/nzbget.conf "/home/$(config_get admin)/.config/nzbget/nzbget.conf"
			sudo sed -i "s|MainDir=.*|MainDir=~/.config/nzbget|g" "/home/$(config_get admin)/.config/nzbget/nzbget.conf"

			sudo sed -i "s|ControlUsername=.*|ControlUsername=$(config_get nzbget_control_user)|g" "/home/$(config_get admin)/.config/nzbget/nzbget.conf"
			sudo sed -i "s|ControlPassword=.*|ControlPassword=$(config_get nzbget_control_password)|g" "/home/$(config_get admin)/.config/nzbget/nzbget.conf"

			if [ -n "$(config_get downloading_path)" ]
			then
				sudo sed -i "s|DestDir=.*|DestDir=$(config_get downloaded_path)|g" "/home/$(config_get admin)/.config/nzbget/nzbget.conf"
				sudo sed -i "s|InterDir=.*|InterDir=$(config_get downloading_path)|g" "/home/$(config_get admin)/.config/nzbget/nzbget.conf"
			else
				sudo sed -i "s|DestDir=.*|DestDir=$(config_get download_path)|g" "/home/$(config_get admin)/.config/nzbget/nzbget.conf"
				sudo sed -i "s|InterDir=.*|InterDir=|g" "/home/$(config_get admin)/.config/nzbget/nzbget.conf"
			fi
		fi

		if [ "${package}" = "deluged" ]
		then
			echo -e "${pharmacy_m} ${package}"
			sudo mkdir -p "/home/$(config_get admin)/.config/deluge/torrentfiles"
			sudo -u "$(config_get admin)" deluge-console plugin -e Label
			sudo -u "$(config_get admin)" deluge-console config --set torrentfiles_location "/home/$(config_get admin)/.config/deluge/torrentfiles"
			sudo -u "$(config_get admin)" deluge-console config --set copy_torrent_file true
			if [ -n "$(config_get downloading_path)" ]
			then
				sudo -u "$(config_get admin)" deluge-console config --set move_completed_path "$(config_get downloaded_path)"
				sudo -u "$(config_get admin)" deluge-console config --set download_location "$(config_get downloading_path)"
				sudo -u "$(config_get admin)" deluge-console config --set move_completed true
			else
				sudo -u "$(config_get admin)" deluge-console config --set download_location "$(config_get download_path)"
			fi
		fi
	done

	for archive in $(echo "$(config_get archives)" | tr "," "\n")
	do
		# Bazarr python requirements 
		if [ "${archive}" = 'bazarr' ]
		then
			echo -e "${pharmacy_m} Setting up aditional ${archive} dependencies"
			sudo python3 -m pip install -q -r "$(config_get archive_install_path)/${archive}/requirements.txt"
		fi
	done

	if [ "$(config_get pihole_dns_local_domain)" = "true" ]
	then
		echo -e "${pharmacy_m} Setting up pihole as local dns"
		echo "$(hostname -I | awk '{print $1}') $(config_get domain_name)" | sudo tee -a /etc/pihole/custom.list 1> /dev/null
	fi

	if [ "$(config_get use_pihole_pivpn)" = "true" ]
	then
		echo -e "${pharmacy_m} Configuring pihole on pivpn"
		if [ -d "/etc/pivpn/wireguard" ]
		then
			pivpn_vpn="wireguard"
			pivpn_dns="10.6.0.1"
		else
			pivpn_vpn="openvpn"
			pivpn_dns="10.8.0.1"
		fi
		echo "addn-hosts=/etc/pivpn/hosts.${pivpn_vpn}" | sudo tee /etc/dnsmasq.d/02-pivpn.conf 1> /dev/null
		sudo bash -c "> /etc/pivpn/hosts.${pivpn_vpn}"
		sudo pihole -a -i local
		sudo sed -i "s/pivpnDNS1=.*/pivpnDNS1=${pivpn_dns}/g" "/etc/pivpn/${pivpn_vpn}/setupVars.conf"
		sudo sed -i "s/pivpnDNS2=.*/pivpnDNS2=/g" "/etc/pivpn/${pivpn_vpn}/setupVars.conf"
	fi

	if [ $(config_get disable_ssh_greetings) = "true" ]
	then
		echo -e "${pharmacy_m} Disabling ssh greetings"
		echo '' | sudo tee /etc/motd 1> /dev/null
		sudo sed -i 's/.*PrintMotd.*$/PrintMotd no/g' /etc/ssh/sshd_config
		sudo sed -i 's/.*PrintLastLog.*$/PrintLastLog no/g' /etc/ssh/sshd_config
		sudo sed -i 's/.*uname.*$/# uname -snrvm/g' /etc/update-motd.d/10-uname
	fi

	if [ -n "$(config_get restore_user_crontab)" ]
	then
		echo -e "${pharmacy_m} Restoring user crontab"
		for user_crontab in $(echo "$(config_get restore_user_crontab)" | tr "," "\n")
		do
			IFS=':'
			read -ra user <<< "${user_crontab}"
			unset IFS
			# shellcheck disable=SC2024 # sudo is not being use in the redirect here.
			sudo -u ${user[0]} crontab -l > /tmp/tempcron
			cat "${user[1]}" | sudo tee -a /tmp/tempcron 1> /dev/null
			sudo -u ${user[0]} crontab /tmp/tempcron
			rm /tmp/tempcron
		done
	fi

	if [ "$(config_get create_selfsigned_cert)" = "true" ]
	then
		echo -e "${pharmacy_m} Creating self signed certificates/keys"
		sudo mkdir /etc/ssl/local/
		sudo openssl dhparam $(config_get dhparam_size) -out /etc/ssl/local/dhparam.pem
		sudo openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout "/etc/ssl/local/$(config_get domain_name).key" -out "/etc/ssl/local/$(config_get domain_name).fullchain.crt" -subj "/CN=$(config_get domain_name)" \ -addext "subjectAltName=DNS:$(config_get domain_name),DNS:www.$(config_get domain),$(hostname -I | awk '{print $1}')"
		sudo chmod 644 /etc/ssl/local/*
		sudo chown root:root /etc/ssl/local/*
	fi

	if [ -n "$(config_get restore_ssl_files)" ]
	then
		echo -e "${pharmacy_m} Restoring ssl files"
		sudo mkdir -p /etc/ssl/local
		for file in $(echo "$(config_get restore_ssl_files)" | tr "," "\n")
		do
			sudo install -o root -g root -m 644 "$(config_get ${file})" /etc/ssl/local/
		done
	fi

	if [ -n "$(config_get create_media_folders)" ]
	then
		echo -e "${pharmacy_m} Creating media folders"
		for folder in $(echo "$(config_get create_media_folders)" | tr "," "\n")
		do
			sudo install -d -o "$(config_get admin)" -g "$(config_get admin)" -m 644 "$(config_get ${folder})"
		done
	fi
}

### Actions

# Manipulate files before the installation step
do_actions_pre_install()
{
	if [ -n "$(config_get git_clone_repos)" ]
	then
		echo -e "${pharmacy_m} Cloning repos"
		for repo in $(echo "$(config_get git_clone_repos)" | tr "," "\n")
		do
			git clone --depth=1 "${repo}" "/tmp/$(echo ${repo} | sed -e 's#.*/##' -e 's#.git##')"
		done
	fi
}

# Manipulate files before the configuration step
do_actions_pre_config()
{
	if [ -n "$(config_get make_dir)" ]
	then
		echo -e "${pharmacy_m} Creating directories"
		for dir in $(echo "$(config_get make_dir)" | tr "," "\n")
		do
			sudo mkdir "${dir}"
		done
	fi

	if [ -n "$(config_get move)" ]
	then
		echo -e "${pharmacy_m} Moving files/folders"
		for targets in $(echo "$(config_get move)" | tr "," "\n")
		do
			IFS=':'
			read -ra target <<< "${targets}"
			unset IFS
			sudo mv "${target[0]}" "${target[1]}"
		done
	fi

	if [ -n "$(config_get change_owner)" ]
	then
		echo -e "${pharmacy_m} Changing owners"
		for targets in $(echo "$(config_get change_owner)" | tr "," "\n")
		do
			IFS=':'
			read -ra target <<< "${targets}"
			unset IFS
			sudo chown -R ${target[0]}:${target[0]} "${target[1]}"
		done
	fi

	if [ -n "$(config_get change_mod)" ]
	then
		echo -e "${pharmacy_m} Changing permissions"
		for targets in $(echo "$(config_get change_mod)" | tr "," "\n")
		do
			IFS=':'
			read -ra target <<< "${targets}"
			unset IFS
			sudo chmod -R ${target[0]} ${target[1]}
		done
	fi

	if [ -n "$(config_get append)" ]
	then
		echo -e "${pharmacy_m} Appending text to files"
		IFS=$'\n'
		for targets in $(echo "$(config_get append)" | tr "," "\n")
		do
			unset IFS
			IFS=':'
			read -ra target <<< "${targets}"
			unset IFS
			# shellcheck disable=SC2001 # I need sed here
			target[0]="$(echo ${target[0]} | sed -e 's/+++/,/g')"
			echo "${target[0]}" | sudo tee -a "${target[1]}" 1> /dev/null
		done
	fi
}

### Custom Actions

# Execute specific actions
do_custom_actions()
{
	if [ -n "$(config_get admin_git_name)" ] && [ -n "$(config_get admin_git_email)" ]
	then
		echo -e "${pharmacy_m} Setting admin git credentials"
		sudo -u $(config_get admin) git config --global user.name "$(config_get admin_git_name)"
		sudo -u $(config_get admin) git config --global user.email "$(config_get admin_git_email)"
	fi
	
	if [ -n "$(config_get nginx_proxied_services)" ]
	then
		echo -e "${pharmacy_m} Removing default nginx server"
		sudo rm /etc/nginx/sites-enabled/default
	fi

	if [ -n "$(config_get tm_key)" ]
	then
		echo -e "${pharmacy_m} Setting up Telegram Mailgate"

		sudo pip3 install python-telegram-bot
		sudo cp /tmp/telegram-mailgate/telegram-mailgate.py /usr/local/bin/
		sudo chown $(config_get admin) /usr/local/bin/telegram-mailgate.py
		sudo chmod 700 /usr/local/bin/telegram-mailgate.py
		sudo mkdir /etc/telegram-mailgate
		sudo cp /tmp/telegram-mailgate/{main.cf,logging.cf,aliases} /etc/telegram-mailgate/

		sudo sed -i "s/key=$/key=$(config_get tm_key)/g" /etc/telegram-mailgate/main.cf 1> /dev/null
		sudo sed -i "s/nobody 0123456789/$(config_get tm_alias)/g" /etc/telegram-mailgate/aliases 1> /dev/null
		echo "content_filter = telegram-mailgate" | sudo tee -a /etc/postfix/main.cf 1> /dev/null

		echo "# =======================================================================" | sudo tee -a /etc/postfix/master.cf 1> /dev/null
		echo "# telegram-mailgate"                                                       | sudo tee -a /etc/postfix/master.cf 1> /dev/null
		echo "telegram-mailgate unix -     n       n       -        -      pipe"         | sudo tee -a /etc/postfix/master.cf 1> /dev/null
		echo "  flags= user=$(config_get admin) argv=/usr/local/bin/telegram-mailgate.py --simple-header --queue-id \$queue_id \$recipient" | sudo tee -a /etc/postfix/master.cf 1> /dev/null
	fi
}

### Checks

# Checks for valid non-interactive options
do_non_interactive_check()
{
	if [ -n "${configPath}" ]
	then
		if [ ! -f "${configPath}" ]
		then
			echo "Config file path invalid"
			exit 1
		fi
	fi
}

# Check if there is enough free space on the SD card
do_disk_check()
{
	echo -e "${pharmacy_m} Checking disk space"
	freeSpace=$(df | grep '/dev/root' | tail -n1 | awk '{print $4}' | sed 's/[^0-9]//')
	if [ $freeSpace -lt 3000000 ]
	then
	    echo "Insuficient space on disk"
		exit 1
	fi
}

# Enable services to restart at boot
do_enable_services()
{
	echo -e "${pharmacy_m} Enabling services"
	for service in $(echo "$(config_get enable)" | tr "," "\n")
	do
		services="${services} ${service}"
	done

	sudo systemctl daemon-reload
	sudo systemctl enable ${services}
}

### Tools

do_remedy_backup()
{
	echo -e "${pharmacy_m} Backing up REMEDy config/db"

	sudo mkdir -p "/home/$(config_get admin)/backups/remedy/jellyfin"
	#sudo mkdir -p "/home/$(config_get admin)/backups/remedy/plex"
	sudo mkdir -p "/home/$(config_get admin)/backups/remedy/Radarr"
	sudo mkdir -p "/home/$(config_get admin)/backups/remedy/Sonarr"
	sudo mkdir -p "/home/$(config_get admin)/backups/remedy/Readarr"
	sudo mkdir -p "/home/$(config_get admin)/backups/remedy/Lidarr"
	sudo mkdir -p "/home/$(config_get admin)/backups/remedy/Prowlarr"
	sudo mkdir -p "/home/$(config_get admin)/backups/remedy/Bazarr"

	#sudo cp -r "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml" "/home/$(config_get admin)/backups/remedy/plex"

	sudo cp -r "/opt/bazarr/data/config/config.ini" "/home/$(config_get admin)/backups/remedy/Bazarr"
	sudo cp -r "/opt/bazarr/data/db/bazarr.db" "/home/$(config_get admin)/backups/remedy/Bazarr"

	sudo cp -r "/var/lib/jellyfin/data/authentication.db" "/home/$(config_get admin)/backups/remedy/jellyfin"
	sudo cp -r "/var/lib/jellyfin/data/jellyfin.db" "/home/$(config_get admin)/backups/remedy/jellyfin"
	sudo cp -r "/var/lib/jellyfin/data/library.db" "/home/$(config_get admin)/backups/remedy/jellyfin"
	sudo cp -r "/var/lib/jellyfin/data/device.txt" "/home/$(config_get admin)/backups/remedy/jellyfin"

	sudo cp -r "/home/$(config_get admin)/.config/Radarr/radarr.db" "/home/$(config_get admin)/backups/remedy/Radarr"
	sudo cp -r "/home/$(config_get admin)/.config/Radarr/config.xml" "/home/$(config_get admin)/backups/remedy/Radarr"
	sudo cp -r "/home/$(config_get admin)/.config/Sonarr/sonarr.db" "/home/$(config_get admin)/backups/remedy/Sonarr"
	sudo cp -r "/home/$(config_get admin)/.config/Sonarr/config.xml" "/home/$(config_get admin)/backups/remedy/Sonarr"
	sudo cp -r "/home/$(config_get admin)/.config/Lidarr/lidarr.db" "/home/$(config_get admin)/backups/remedy/Lidarr"
	sudo cp -r "/home/$(config_get admin)/.config/Lidarr/config.xml" "/home/$(config_get admin)/backups/remedy/Lidarr"
	sudo cp -r "/home/$(config_get admin)/.config/Readarr/readarr.db" "/home/$(config_get admin)/backups/remedy/Readarr"
	sudo cp -r "/home/$(config_get admin)/.config/Readarr/config.xml" "/home/$(config_get admin)/backups/remedy/Readarr"
	sudo cp -r "/home/$(config_get admin)/.config/Prowlarr/prowlarr.db" "/home/$(config_get admin)/backups/remedy/Prowlarr"
	sudo cp -r "/home/$(config_get admin)/.config/Prowlarr/config.xml" "/home/$(config_get admin)/backups/remedy/Prowlarr"
}

do_remedy_restore()
{
	echo -e "${pharmacy_m} Restoring REMEDy config/db"
	
	sudo -u $(config_get admin) mkdir -p "/opt/bazarr/data/db"
	sudo -u $(config_get admin) mkdir -p "/opt/bazarr/data/config"
	sudo -u $(config_get admin) mkdir -p "/home/$(config_get admin)/.config/Radarr"
	sudo -u $(config_get admin) mkdir -p "/home/$(config_get admin)/.config/Sonarr"
	sudo -u $(config_get admin) mkdir -p "/home/$(config_get admin)/.config/Lidarr"
	sudo -u $(config_get admin) mkdir -p "/home/$(config_get admin)/.config/Readarr"
	sudo -u $(config_get admin) mkdir -p "/home/$(config_get admin)/.config/Prowlarr"

	#sudo cp -r "/home/$(config_get admin)/backups/remedy/plex/Preferences.xml" "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml" 

	sudo cp -r "/home/$(config_get admin)/backups/remedy/Bazarr/config.ini" "/opt/bazarr/data/config/config.ini" 
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Bazarr/bazarr.db" "/opt/bazarr/data/db/bazarr.db" 

	sudo cp -r "/home/$(config_get admin)/backups/remedy/jellyfin/authentication.db" "/var/lib/jellyfin/data/authentication.db" 
	sudo cp -r "/home/$(config_get admin)/backups/remedy/jellyfin/jellyfin.db" "/var/lib/jellyfin/data/jellyfin.db"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/jellyfin/library.db" "/var/lib/jellyfin/data/library.db"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/jellyfin/device.txt" "/var/lib/jellyfin/data/device.txt"

	sudo cp -r "/home/$(config_get admin)/backups/remedy/Radarr/radarr.db" "/home/$(config_get admin)/.config/Radarr/radarr.db"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Radarr/config.xml" "/home/$(config_get admin)/.config/Radarr/config.xml"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Sonarr/sonarr.db" "/home/$(config_get admin)/.config/Sonarr/sonarr.db"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Sonarr/config.xml" "/home/$(config_get admin)/.config/Sonarr/config.xml"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Lidarr/lidarr.db" "/home/$(config_get admin)/.config/Lidarr/lidarr.db"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Lidarr/config.xml" "/home/$(config_get admin)/.config/Lidarr/config.xml"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Readarr/readarr.db" "/home/$(config_get admin)/.config/Readarr/readarr.db"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Readarr/config.xml" "/home/$(config_get admin)/.config/Readarr/config.xml"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Prowlarr/prowlarr.db" "/home/$(config_get admin)/.config/Prowlarr/prowlarr.db"
	sudo cp -r "/home/$(config_get admin)/backups/remedy/Prowlarr/config.xml" "/home/$(config_get admin)/.config/Prowlarr/config.xml"
}

### Utility

# Read config from file
config_read_file()
{
    sed -e 's/\(\".*\"\)|\s*/\1/g' -e 's/\"//g' -e 's/#.*$//g' -e '/^$/d' "${1}" | (grep -E "^${2}=" -m 1  2>/dev/null || echo "VAR=") | head -n 1 | cut -d '=' -f 2-;
}

# Read config section from file
config_read_section()
{
	sed -e '/^\[services]$/,/^\[.*]$/{//!b};d' "${1}"
}

# Return config variable value
config_get()
{
	if [ -f "${configPath}" ]
	then
		val="$(config_read_file "${configPath}" "${1}")";
	else
		val="$(config_read_file "./interactive.conf" "${1}")";
	fi
	printf -- "%s" "${val}";
}

cd_to_script_dir()
{
	scriptDir="$(dirname "$(readlink -f "$0")")"
	cd "${scriptDir}" || exit 1
}

# --------- CHECKS ---------

do_non_interactive_check
do_disk_check

# --------- SETUP ---------

# Capture options
while getopts cisbrp: flag
do
	case "${flag}" in
		p) configPath=${OPTARG};;
		c) raspiConfig="true";;
		i) pharmacyInstall="true";;
		s) pharmacySetup="true";;
		b) remedyBackup="true";;
		r) remedyRestore="true";;
		*) ;;
	esac
done

# Starts interactive setup
if [ ! -f "${configPath}" ]
then
	do_interactive_config_check
	do_greeting
fi

# --------- DO THE MAGIC ---------

cd_to_script_dir
if [ -n "${raspiConfig}" ]; then do_raspi_config; echo -e "${pharmacy_m} Config complete"; exit 0; fi
if [ -n "${remedyBackup}" ]; then do_remedy_backup; echo -e "${pharmacy_m} Backup complete"; exit 0; fi
if [ -n "${remedyRestore}" ]; then do_remedy_restore; echo -e "${pharmacy_m} Restore complete"; exit 0; fi
if [ -n "${pharmacyInstall}" ]; then do_manage_packages; echo -e "${pharmacy_m} Install complete"; exit 0; fi
if [ -n "${pharmacySetup}" ]
then
	do_manage_users
	do_actions_pre_install
	do_manage_installers
	do_manage_archives
	do_manage_units
	do_actions_pre_config
	do_manage_configs
	do_custom_actions
	do_enable_services
	echo -e "${pharmacy_m} Setup complete"
	exit 0;
fi

# --------- DONE THE MAGIC ---------

echo -e "${pharmacy_m} Script finalized"
