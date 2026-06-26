#!/bin/bash

#=====================================================================#
#=======================variable update_reader()======================#
#=====================================================================#
#init reader
USERNAME_READER="root"
READER_COHERENT_IP="192.168.1.199"
SSH_READER="$USERNAME_READER@$READER_COHERENT_IP"
PASSWORD_READER="TRAN5act10n+953"

NEW_IP="192.168.1.200/24"
IP_GATEWAY="192.168.1.1"

#=====================================================================#
#=============================download file===========================#
#=====================================================================#
# FW_ZIP ditentukan saat runtime berdasarkan input versi user
SCRIPT_NAME='jellies_scripts'
SCRIPT_ZIP="${SCRIPT_NAME}.zip"
#=====================================================================#
#===========================server source=============================#
#=====================================================================#
PARKEE_FOLDER='/opt/app/agent/parkee-agent'
PARKEE_SSH_PROP="${PARKEE_FOLDER}/server.properties"
PARKEE_SSH_USER='support'
PARKEE_SSH_PASS='support545115'
PARKEE_SSH_IP=$(grep -oP '^dbHost=\K.*' "$PARKEE_SSH_PROP")
PARKEE_SSH_SOURCE='/home/support'
PARKEE_SSH_SERVER="${PARKEE_SSH_USER}@${PARKEE_SSH_IP}"
PARKEE_SSH_OPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
#=====================================================================#
#===========================local file / dir==========================#
#=====================================================================#
DOWNLOAD_DIR="$HOME/Downloads"

SCRIPT_DIR="$DOWNLOAD_DIR/$SCRIPT_NAME/scripts"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
#=====================================================================#
#==========================reader file/folder=========================#
#=====================================================================#
DIR_BIN='/apps/parque/bin'
FILE_FIRMWARE='parque' 
PATH_FILE_FIRMWARE=$DIR_BIN/$FILE_FIRMWARE

FILE_UI='uimedia' 
PATH_FILE_UI=$DIR_BIN/$FILE_UI

DIR_cronjob_reader='/apps/etc/cronjobs'
FILE_SCRIPT_parque_check='parque_check'
PATH_FILE_parque_check=$DIR_cronjob_reader/$FILE_SCRIPT_parque_check

DIR_init_d='/apps/etc/init.d'
FILE_SCRIPT_S40_parque='S40_parque'
PATH_FILE_S40_parque=$DIR_init_d/$FILE_SCRIPT_S40_parque

DIR_debug_config='/apps/ocean/etc'
FILE_debug_config='debug.config'
PATH_FILE_debug_config=$DIR_debug_config/$FILE_debug_config

#=====================================================================#
#===========================PATH PSAM CONFIG==========================#
#=====================================================================#
DIR_PSAM_config="/apps/parque/data"
FILE_PSAM_config="config.ini"
PATH_FILE_PSAM_config=$DIR_PSAM_config/$FILE_PSAM_config
#=====================================================================#

#=====================================================================#
#=========================variable serial_dev=========================#
#=====================================================================#
DIR_PARKEE_AGENT="/opt/app/agent/parkee-agent"
FILE_DEV_PROP="device.properties"
PATH_DEV_PROP=$DIR_PARKEE_AGENT/$FILE_DEV_PROP
service_name="parkee-agent"
#=====================================================================#


# Fungsi menampilkan semua NIC dan IP
cek_ip() {
	clear
	echo -e "======📡SHOWS ALL AVAILABLE NIC/LAN PORTS📡========"
	echo -e "==================================================="

# Loop semua NIC yang ada di sistem
	for nic in $(nmcli -t -f DEVICE device status | cut -d':' -f1); do
	echo -e "🔹 NIC: $nic"
	echo -e "----------------------------------------"

	# Ambil status koneksi
	status=$(nmcli -t -f DEVICE,STATE device status | grep "^$nic:" | cut -d':' -f2)
	printf "🔸 %-12s : %s\n" "Status" "$status"

	# Cek apakah NIC memiliki profil koneksi yang aktif
	connection_name=$(nmcli -t -f DEVICE,CONNECTION device status | grep "^$nic:" | cut -d':' -f2)
	 
	if [[ -z "$connection_name" ||"$connection_name" == "--" ]]; then
		ip_method="-"
	else
		# Ambil metode IP (DHCP atau manual) dari profil koneksi
		ip_method=$(nmcli -t -f ipv4.method connection show "$connection_name" 2>/dev/null | cut -d':' -f2)
		[[ -z "$ip_method" ]] && ip_method="-"
	fi
	printf "🔸 %-12s : %s\n" "Metode IP" "$ip_method"

	# Ambil alamat IP
	ip_address=$(nmcli -t -f IP4.ADDRESS device show "$nic" | cut -d':' -f2)
	[[ -z "$ip_address" ]] && ip_address="-"
	printf "🔸 %-12s : %s\n" "Alamat IP" "$ip_address"

	# Ambil gateway
	gateway=$(nmcli -t -f IP4.GATEWAY device show "$nic" | cut -d':' -f2)
	[[ -z "$gateway" ]] && gateway="-"
	printf "🔸 %-12s : %s\n" "Gateway" "$gateway"
	 
	dns=$(nmcli -t -f IP4.DNS device show "$nic" | cut -d':' -f2 | paste -sd ", ")
	[[ -z "$dns" ]] && dns="-"
	printf "🔸 %-12s : %s\n" "dns" "$dns"

	echo -e ""  # Spasi antar NIC
	done
}

# Fungsi mengubah IP dengan pemilihan otomatis
ubah_ip() {
	clear
	cek_ip
	echo -e "🔧SELECT THE NIC YOU WISH TO CHANGE:"
	select NIC in $(nmcli -t -f DEVICE device status | awk '{print $1}') "Cancel"; do
	[[ "$NIC" == "Cancel" ]] && echo -e "❌ CANCEL CHANGING IP" && clear && return
	[[ -n "$NIC" ]] && break
	done

		# Mencari nama koneksi berdasarkan NIC
	CON_NAME=$(nmcli -t -f NAME,DEVICE con show | grep "^.*:$NIC$" | cut -d: -f1)
	#CON_NAME=$(nmcli -t -f NAME,DEVICE con show | awk -F: -v nic="$NIC" '$2==nic {print $1}')
	if [[ -z "$CON_NAME" ]]; then
	echo -e "❌ FAILED TO FIND CONNECTION FOR NIC $NIC"
	return
	fi

	echo -e "🔧 SELECT IP CONFIGURATION METHOD:"
	select choice in "DHCP (Automatic)" "Statis (Manual)" "Cancel"; do
	case $choice in
		"DHCP (Automatic)")
		clear
		echo -e "===========🛠️DELETE PREVIOUS STATIC IP🛠️============"
		sudo nmcli con mod "$CON_NAME" ipv4.method auto
		sudo nmcli con mod "$CON_NAME" ipv4.addresses ""
		sudo nmcli con mod "$CON_NAME" ipv4.gateway ""
		sudo nmcli con mod "$CON_NAME" ipv4.dns ""
		sudo nmcli con up "$CON_NAME"
		#sudo nmcli networking off && sudo nmcli networking on
		sudo nmcli con mod "$CON_NAME" ipv4.method auto
		sudo nmcli con mod "$CON_NAME" ipv4.addresses ""
		sudo nmcli con mod "$CON_NAME" ipv4.gateway ""
		sudo nmcli con mod "$CON_NAME" ipv4.dns ""
		sudo nmcli con mod "$CON_NAME" ipv4.ignore-auto-dns no
		sudo nmcli con up "$CON_NAME"
		sudo nmcli con down "$CON_NAME" && sudo nmcli con up "$CON_NAME"
		#sudo nmcli networking off && sudo nmcli networking on
		echo -e "✅IP CHANGED TO DHCP ON $NIC ($CON_NAME)"
		echo -e "===========✅DHCP IP SETTINGS COMPLETE✅============"
		break
		;;
		"Statis (Manual)")
		clear
		echo -e "=========🛠️CHANGING DHCP IP TO STATIC IP🛠️=========="
		#sudo nmcli networking off && sudo nmcli networking on
		sudo nmcli con down "$CON_NAME" && sudo nmcli con up "$CON_NAME"

		sudo nmcli con mod "$CON_NAME" ipv4.addresses "$NEW_IP"
		sudo nmcli con mod "$CON_NAME" ipv4.gateway "$IP_GATEWAY"
		#sudo nmcli con mod "$CON_NAME" ipv4.dns "$IP_GATEWAY, 8.8.8.8, 8.8.4.4"
		sudo nmcli con mod "$CON_NAME" ipv4.dns "$IP_GATEWAY,8.8.8.8,8.8.4.4"
		sudo nmcli con mod "$CON_NAME" ipv4.ignore-auto-dns yes
		sudo nmcli con mod "$CON_NAME" ipv4.never-default yes
		sudo nmcli con mod "$CON_NAME" ipv4.method manual
		sudo nmcli con down "$CON_NAME" && sudo nmcli con up "$CON_NAME"
		#sudo nmcli networking off && sudo nmcli networking on
		echo -e "✅ IP $NIC ($CON_NAME) CHANGED TO $NEW_IP"
		echo -e "==========✅STATIC IP SETTINGS COMPLETE✅==========="
		break
		;;
		"Cancel")
		echo -e "❌CANCEL CHANGING IP"
		return
		;;
		*)
		echo -e "❌ INVALID SELECTION!"
		;;
	esac
	done
}

# Fungsi Setup SSH Key
bypass_reader() {
clear
if ! command sshpass &> /dev/null; then
sudo apt update && sudo apt install sshpass -y
fi

sudo chown -R $USER:$GROUP $HOME/.ssh

#cd $HOME/.ssh
#if [ ! -f "$SSH_KEY_PATH" ]; then
#rm -f "$SSH_KEY_PATH" 
#rm -f "$SSH_KEY_PATH.pub"
#fi

ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
sshpass -p "${PASSWORD_READER}" ssh-copy-id -o StrictHostKeyChecking=no "${SSH_READER}"

cd $HOME/
	
}


restart_nic() {
	clear
	cek_ip
	echo -e "🔧SELECT THE NIC YOU WANT TO RESTART:"
	select NIC in $(nmcli -t -f DEVICE device status | awk '{print $1}') "Cancel"; do
	[[ "$NIC" == "Cancel" ]] && echo -e "❌CANCEL RESTART NIC IP" && return
	[[ -n "$NIC" ]] && break
	done

	# Mencari nama koneksi berdasarkan NIC
	CON_NAME=$(nmcli -t -f NAME,DEVICE con show | grep "^.*:$NIC$" | cut -d: -f1)
	if [[ -z "$CON_NAME" ]]; then
	echo -e "❌FAILED TO FIND CONNECTION FOR NIC $NIC"
	return
	fi

	echo -e "🔧SELECT IP CONFIGURATION METHOD:"
	select choice in "Active" "In-Active" "Cancel"; do
	case $choice in
		"Active")
		clear
		echo -e "🛠️ Restart NIC/Port LAN"
		sudo nmcli con down "$NIC" && sudo nmcli con up "$NIC"
		sudo systemctl restart NetworkManager
		echo -e "✅ NIC/Port $NIC ($CON_NAME) Lan sudah Aktif "
		break
		;;
		"In-Active")
		clear
		echo -e "🛠️ In-Active NIC/Port LAN"
		sudo nmcli con down "$CON_NAME"
		echo -e "✅ NIC/Port Lan $NIC ($CON_NAME) sudah In-Active "
		clear
		break
		;;
		"Cancel")
		sudo systemctl restart NetworkManager
		sudo nmcli networking off && sudo nmcli networking on
		return
		;;
		*)
		echo -e "❌ INVALID SELECTION!"
		;;
	esac
	done
}


serial_dev() {
	clear

	# Cek apakah file konfigurasi ada
	if [[ ! -f "$PATH_DEV_PROP" ]]; then
		clear
		echo -e "❌CONFIGURATION FILE $PATH_DEV_PROP NOT FOUND!!!!!!"
		return 1
	fi
	
	echo -e "\n===================================================\n"
	echo -e "🔍SHOWING THE CURRENT CONFIGURATION:"
	cat "$PATH_DEV_PROP" | grep -E "^wuzz.reader.standby.mode="
	cat "$PATH_DEV_PROP" | grep -E "^booster.type="
	cat "$PATH_DEV_PROP" | grep -E "^booster.port="
	cat "$PATH_DEV_PROP" | grep -E "^booster.port.double.loop="

	cat "$PATH_DEV_PROP" | grep -E "^reader.type="
	cat "$PATH_DEV_PROP" | grep -E "^reader.connection="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.type="
	cat "$PATH_DEV_PROP" | grep -E "^multi.reader="
	cat "$PATH_DEV_PROP" | grep -E "^reader.type.02="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.02="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.type.02="

	cat "$PATH_DEV_PROP" | grep -E "^barcode.debounce="
	cat "$PATH_DEV_PROP" | grep -E "^suggestion.debounce="

	cat "$PATH_DEV_PROP" | grep -E "^gate.timeout="
	cat "$PATH_DEV_PROP" | grep -E "^sti.timeout="
	echo -e "\n===================================================\n"
	echo -e "🔎DETECT AVAILABLE SERIAL PORTS"

	serial_ports=$(sudo dmesg | grep 'tty' | grep -o 'tty[A-Za-z0-9]*' | sort -u)
	
	if [[ -z "$serial_ports" ]]; then
		echo -e "⚠️NO SERIAL PORTS FOUND. MAKE SURE PCI-E IS PROPERLY INSTALLED⚠️"
		read -p "DO YOU WANT TO SHUTDOWN NOW? (y/n): " shutdown_confirm
			if [[ $shutdown_confirm == "y" ]]; then
				sudo shutdown now
			else
				return 1
			fi
	else
		echo -e "\n===================================================\n"
		echo -e "===============✅SERIAL PORTS FOUND✅==============="

		# Tambahan numbering (tanpa ubah logic lama)
		i=1
		for port in $serial_ports; do
			echo "$i). $port"
			i=$((i+1))
		done

		echo -e "\n===================================================\n"
	fi
   
	# ===============================
	# OLD INPUT METHOD (DIKOMEN SAJA)
	# ===============================
	# while true; do
	# read -p "ENTER THE SERIAL PORT YOU WANT TO USE (EXAMPLE: ttyUSB0): " port_serial
	# if [[ -n "$port_serial" && "$serial_ports" == *"$port_serial"* ]]; then
	# 	break
	# else
	# 	echo -e "⚠️INVALID SERIAL PORT! PLEASE TRY AGAIN."
	# fi
	# done


	# ===============================
	# NEW INPUT METHOD (PILIH NOMOR)
	# ===============================
	while true; do
		read -p "ENTER NUMBER OF SERIAL PORT YOU WANT TO USE: " port_number

		if [[ "$port_number" =~ ^[0-9]+$ ]]; then
			i=1
			for port in $serial_ports; do
				if [[ "$i" == "$port_number" ]]; then
					port_serial="$port"
					break
				fi
				i=$((i+1))
			done

			if [[ -n "$port_serial" ]]; then
				break
			fi
		fi

		echo -e "⚠️INVALID SERIAL PORT! PLEASE TRY AGAIN."
	done


	# Menampilkan konfigurasi sebelum perubahan
	echo -e "\n==========📌CONFIGURATION BEFORE CHANGES📌==========\n"
	cat "$PATH_DEV_PROP" | grep -E "^wuzz.reader.standby.mode="
	cat "$PATH_DEV_PROP" | grep -E "^booster.type="
	cat "$PATH_DEV_PROP" | grep -E "^booster.port="
	cat "$PATH_DEV_PROP" | grep -E "^booster.port.double.loop="

	cat "$PATH_DEV_PROP" | grep -E "^reader.type="
	cat "$PATH_DEV_PROP" | grep -E "^reader.connection="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.type="
	cat "$PATH_DEV_PROP" | grep -E "^multi.reader="
	cat "$PATH_DEV_PROP" | grep -E "^reader.type.02="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.02="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.type.02="

	cat "$PATH_DEV_PROP" | grep -E "^barcode.debounce="
	cat "$PATH_DEV_PROP" | grep -E "^suggestion.debounce="

	cat "$PATH_DEV_PROP" | grep -E "^gate.timeout="
	cat "$PATH_DEV_PROP" | grep -E "^sti.timeout="

	echo -e "===============📡SELECT READER TYPE📡==============="
	echo "1) COHERENT"
	echo "2) pax"
	echo "3) rfid"
	echo "4) sr200"
	echo ""

	while true; do
		read -p "ENTER NUMBER OF READER TYPE: " pilihan_reader

		case $pilihan_reader in
			1) reader_type="COHERENT" ;;
			2) reader_type="pax" ;;
			3) reader_type="rfid" ;;
			4) reader_type="sr200" ;;
			*)
				echo "⚠️INVALID SELECTION! PLEASE TRY AGAIN."
				continue
				;;
		esac
		break
	done


	echo -e "\n=============🛠️CHANGING CONFIGURATION🛠️=============\n"
	sudo sed -i -E "s|^(reader.type=).*|\1COHERENT|" "$PATH_DEV_PROP"
	sudo sed -i -E "s|^(reader.port=).*|\1/dev/$port_serial|" "$PATH_DEV_PROP"
	sudo sed -i -E "s|^(reader.port.type=).*|\1serial|" "$PATH_DEV_PROP"
	sudo sed -i -E "s|^(reader.connection=).*|\1serial|" "$PATH_DEV_PROP"
	sudo sed -i -E "s|^(wuzz.reader.standby.mode=).*|\1STANDBY_MODE_READER|" "$PATH_DEV_PROP"
	sudo sed -i -E "s|^barcode.debounce=.*|barcode.debounce=600|" "$PATH_DEV_PROP"
	sudo sed -i -E "s|^suggestion.debounce=.*|suggestion.debounce=600|" "$PATH_DEV_PROP"
	
	#echo -e "==========DEPLOY LIVE LOG READER PARKEE==========="
	#if ! grep 'alias parkee-reader-log=' "$HOME/.zshrc"; then
	#	echo 'alias parkee-reader-log="ssh root@192.168.1.199 \"tail -f -n 10000 /media/mmc/\\\$(ls -t /media/mmc/ | head -n 1)\""' | tee -a "$HOME/.zshrc"
	#	source "$HOME/.zshrc"
	#	echo "======LIVE LOG PARKEE READER HAS BEEN DEPLOY======"
	#else
	#	echo "=======LIVE LOG PARKEE READER ALREADY DEPLOY======"
	#fi
	#echo -e "========DEPLOY LIVE LOG READER PARKEE DONE========"

	echo -e "\n==========📌CONFIGURATION AFTER CHANGES📌===========\n"
	cat "$PATH_DEV_PROP" | grep -E "^wuzz.reader.standby.mode="
	cat "$PATH_DEV_PROP" | grep -E "^booster.type="
	cat "$PATH_DEV_PROP" | grep -E "^booster.port="
	cat "$PATH_DEV_PROP" | grep -E "^booster.port.double.loop="

	cat "$PATH_DEV_PROP" | grep -E "^reader.type="
	cat "$PATH_DEV_PROP" | grep -E "^reader.connection="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.type="
	cat "$PATH_DEV_PROP" | grep -E "^multi.reader="
	cat "$PATH_DEV_PROP" | grep -E "^reader.type.02="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.02="
	cat "$PATH_DEV_PROP" | grep -E "^reader.port.type.02="

	cat "$PATH_DEV_PROP" | grep -E "^barcode.debounce="
	cat "$PATH_DEV_PROP" | grep -E "^suggestion.debounce="

	cat "$PATH_DEV_PROP" | grep -E "^gate.timeout="
	cat "$PATH_DEV_PROP" | grep -E "^sti.timeout="
	echo -e "\n===================================================\n"

	read -p "DO YOU WANT TO RESTART THE SERVICE $service_name? (y/n): " restart_confirm
	if [[ $restart_confirm == "y" ]]; then
		sudo systemctl restart "$service_name"
		sleep 2
		systemctl is-active --quiet "$service_name" 
		echo -e "✅SERVICE SUCCESSFULLY RESTARTED" || echo -e "❌FAILED TO RESTART SERVICE" 
		clear
	else
		echo -e "🔙BACK TO MAIN MENU"
	fi
}



update_reader() {
	clear

	# ===================================================================
	# Input versi firmware — full string termasuk hash
	# Contoh: v1.00.14-f577de6e5 → FW_ZIP=v1.00.14-f577de6e5.zip
	# FW_VERSION diekstrak untuk logic crontab (!= 14)
	# ===================================================================
	pilih_versi_fw(){
		clear
		echo -e "====================================================="
		echo -e "===========📦SELECT FIRMWARE VERSION📦=============="
		echo -e "====================================================="
		echo -e "Ketik nama versi lengkap sesuai file di server."
		echo -e "Contoh: v1.00.14-f577de6e5"
		echo -e "        v1.00.17-905e5f60e"
		echo -e "        v1.00.19-625929d22"
		echo -e "====================================================="
		while true; do
			read -p "INPUT versi firmware: " input_versi

			# Validasi format: v1.00.XX atau v1.00.XX-hash
			if [[ "$input_versi" =~ ^v[0-9]+\.[0-9]+\.([0-9]+)(-[a-zA-Z0-9]+)?$ ]]; then
				FW_VERSION="${BASH_REMATCH[1]}"
				FW_ZIP="${input_versi}.zip"
				break
			else
				echo -e "❌ Format tidak valid. Gunakan format: v1.00.14 atau v1.00.14-f577de6e5"
			fi
		done
		echo -e "====================================================="
		echo -e "✅ FIRMWARE : $input_versi"
		echo -e "✅ FILE     : $FW_ZIP"
		echo -e "✅ VERSION  : $FW_VERSION (untuk logic crontab)"
		echo -e "=====================================================\n"
	}

	# ===================================================================
	# Bypass SSH reader (keygen + copy-id)
	# ===================================================================
	bypass_script(){
		if ! command -v sshpass &> /dev/null; then
			sudo apt update && sudo apt install sshpass -y
		fi
		sudo chown -R $USER:$GROUP $HOME/.ssh
		ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
		sshpass -p "${PASSWORD_READER}" ssh-copy-id -o StrictHostKeyChecking=no "${SSH_READER}"
		cd $HOME/
	}

	# ===================================================================
	# Bersihkan known_hosts untuk IP server lalu SCP file
	# ===================================================================
	prepare_server_connection(){
		echo -e "====================================================="
		echo -e "=====🔑CLEARING KNOWN_HOSTS FOR SERVER SOURCE🔑======"
		echo -e "=====================================================\n"
		sudo ssh-keygen -f '/root/.ssh/known_hosts' -R "$PARKEE_SSH_IP"
		echo -e "✅ KNOWN_HOSTS CLEARED FOR $PARKEE_SSH_IP\n"
	}

	# ===================================================================
	# Pastikan FW_ZIP & SCRIPT_ZIP ada di server — kalau tidak, hit API
	# ===================================================================
	ensure_files_on_server(){
		local API_BASE="http://10.70.0.110:9001"

		echo -e "====================================================="
		echo -e "=======🔍CHECKING FILES AVAILABILITY ON SERVER======="
		echo -e "=====================================================\n"

		# --- FIRMWARE ---
		echo -e "🔍 CHECK $FW_ZIP ON SERVER..."
		if sshpass -p "${PARKEE_SSH_PASS}" scp ${PARKEE_SSH_OPT} "${PARKEE_SSH_SERVER}:${PARKEE_SSH_SOURCE}/${FW_ZIP}" /dev/null 2>/dev/null; then
			echo -e "✅ $FW_ZIP ALREADY EXISTS ON SERVER\n"
		else
			echo -e "⚠️  $FW_ZIP NOT FOUND ON SERVER, FETCHING FROM API...\n"
			echo -e "====================================================="
			echo -e "======📥CURL $FW_ZIP FROM API📥====================="
			echo -e "=====================================================\n"
			if (cd "$DOWNLOAD_DIR" && curl -O "${API_BASE}/${FW_ZIP}"); then
				echo -e "====================================================="
				echo -e "======✅CURL $FW_ZIP DONE✅========================="
				echo -e "=====================================================\n"
				echo -e "====================================================="
				echo -e "======📤SCP $FW_ZIP → SERVER📤====================="
				echo -e "=====================================================\n"
				if sshpass -p "${PARKEE_SSH_PASS}" scp ${PARKEE_SSH_OPT} "$DOWNLOAD_DIR/$FW_ZIP" "${PARKEE_SSH_SERVER}:${PARKEE_SSH_SOURCE}/"; then
					echo -e "====================================================="
					echo -e "======✅SCP $FW_ZIP TO SERVER DONE✅==============="
					echo -e "=====================================================\n"
					rm -f "$DOWNLOAD_DIR/$FW_ZIP"
				else
					echo -e "====================================================="
					echo -e "======❌FAILED SCP $FW_ZIP TO SERVER❌============="
					echo -e "=====================================================\n"
					return 1
				fi
			else
				echo -e "====================================================="
				echo -e "======❌FAILED CURL $FW_ZIP❌======================="
				echo -e "=====================================================\n"
				return 1
			fi
		fi

		# --- SCRIPT ---
		echo -e "🔍 CHECK $SCRIPT_ZIP ON SERVER..."
		if sshpass -p "${PARKEE_SSH_PASS}" scp ${PARKEE_SSH_OPT} "${PARKEE_SSH_SERVER}:${PARKEE_SSH_SOURCE}/${SCRIPT_ZIP}" /dev/null 2>/dev/null; then
			echo -e "✅ $SCRIPT_ZIP ALREADY EXISTS ON SERVER\n"
		else
			echo -e "⚠️  $SCRIPT_ZIP NOT FOUND ON SERVER, FETCHING FROM API...\n"
			echo -e "====================================================="
			echo -e "======📥CURL $SCRIPT_ZIP FROM API📥================="
			echo -e "=====================================================\n"
			if (cd "$DOWNLOAD_DIR" && curl -O "${API_BASE}/${SCRIPT_ZIP}"); then
				echo -e "====================================================="
				echo -e "======✅CURL $SCRIPT_ZIP DONE✅===================="
				echo -e "=====================================================\n"
				echo -e "====================================================="
				echo -e "======📤SCP $SCRIPT_ZIP → SERVER📤================="
				echo -e "=====================================================\n"
				if sshpass -p "${PARKEE_SSH_PASS}" scp ${PARKEE_SSH_OPT} "$DOWNLOAD_DIR/$SCRIPT_ZIP" "${PARKEE_SSH_SERVER}:${PARKEE_SSH_SOURCE}/"; then
					echo -e "====================================================="
					echo -e "======✅SCP $SCRIPT_ZIP TO SERVER DONE✅==========="
					echo -e "=====================================================\n"
					rm -f "$DOWNLOAD_DIR/$SCRIPT_ZIP"
				else
					echo -e "====================================================="
					echo -e "======❌FAILED SCP $SCRIPT_ZIP TO SERVER❌========="
					echo -e "=====================================================\n"
					return 1
				fi
			else
				echo -e "====================================================="
				echo -e "======❌FAILED CURL $SCRIPT_ZIP❌==================="
				echo -e "=====================================================\n"
				return 1
			fi
		fi

		echo -e "====================================================="
		echo -e "=====✅ALL FILES READY ON SERVER✅==================="
		echo -e "=====================================================\n"
	}

	# ===================================================================
	# Download firmware via SCP dari server local
	# ===================================================================
	update_firmware(){
		echo -e "====================================================="
		echo -e "======📥SCP FIRMWARE v${FW_VERSION} FROM SERVER📥======="
		echo -e "=====================================================\n"
		if sshpass -p "${PARKEE_SSH_PASS}" scp "${PARKEE_SSH_SERVER}:${PARKEE_SSH_SOURCE}/${FW_ZIP}" "$DOWNLOAD_DIR/$FW_ZIP"; then
			echo -e "====================================================="
			echo -e "=========✅SCP FIRMWARE v${FW_VERSION} DONE✅==========="
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "=========❌FAILED SCP FIRMWARE v${FW_VERSION}❌=========="
			echo -e "=====================================================\n"
			return 1
		fi

		echo -e "====================================================="
		echo -e "======📂EXTRACTING FIRMWARE v${FW_VERSION} FILE📂======="
		echo -e "=====================================================\n"
		if unzip -o "$DOWNLOAD_DIR/$FW_ZIP" -d "$DOWNLOAD_DIR"; then
			echo -e "====================================================="
			echo -e "====✅EXTRACTING FIRMWARE v${FW_VERSION} FILE DONE✅===="
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "=====❌FAILED TO EXTRACT FIRMWARE v${FW_VERSION}❌======"
			echo -e "=====================================================\n"
			return 1
		fi

		echo -e "====================================================="
		echo -e "========🔄REMOVING FIRMWARE PARKEE READER🔄=========="
		echo -e "=====================================================\n"
		if ssh "$SSH_READER" "rm -f $PATH_FILE_FIRMWARE"; then
			echo -e "====================================================="
			echo -e "======✅REMOVING FIRMWARE PARKEE READER DONE✅======="
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "===========❌FAILED TO REMOVE FIRMWARE❌============="
			echo -e "=====================================================\n"
			return 1
		fi

		echo -e "====================================================="
		echo -e "========🔄REMOVING UIMEDIA PARKEE READER🔄==========="
		echo -e "=====================================================\n"
		if ssh "$SSH_READER" "rm -f $PATH_FILE_UI"; then
			echo -e "====================================================="
			echo -e "======✅REMOVING UIMEDIA PARKEE READER DONE✅========"
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "===========❌FAILED TO REMOVE UIMEDIA❌=============="
			echo -e "=====================================================\n"
			return 1
		fi

		echo -e "====================================================="
		echo -e "=========📤UPLOAD $FILE_FIRMWARE TO PARKEE READER📤=========="
		echo -e "=====================================================\n"
		if scp "$DOWNLOAD_DIR/$FILE_FIRMWARE" "$SSH_READER:$DIR_BIN"; then
			echo -e "====================================================="
			echo -e "======✅UPLOAD $FILE_FIRMWARE TO PARKEE READER DONE✅========"
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "======❌FAILED UPLOAD $FILE_FIRMWARE TO PARKEE READER❌======="
			echo -e "=====================================================\n"
			return 1
		fi

		echo -e "====================================================="
		echo -e "=========📤UPLOAD $FILE_UI TO PARKEE READER📤============"
		echo -e "=====================================================\n"
		if scp "$DOWNLOAD_DIR/$FILE_UI" "$SSH_READER:$DIR_BIN"; then
			echo -e "====================================================="
			echo -e "======✅UPLOAD $FILE_UI TO PARKEE READER DONE✅=========="
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "======❌FAILED UPLOAD $FILE_UI TO PARKEE READER❌========"
			echo -e "=====================================================\n"
			return 1
		fi

		echo -e "====================================================="
		echo -e "=======🔧SETTING FIRMWARE FILE PERMISSIONS🔧========="
		echo -e "=====================================================\n"
		if ssh "$SSH_READER" "chmod 775 $PATH_FILE_FIRMWARE"; then
			echo -e "====================================================="
			echo -e "=====✅SETTING FIRMWARE FILE PERMISSIONS DONE✅======"
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "====❌FAILED TO SET FIRMWARE FILE PERMISSIONS❌======"
			echo -e "=====================================================\n"
			return 1
		fi

		echo -e "====================================================="
		echo -e "=======🔧SETTING UIMEDIA FILE PERMISSIONS🔧=========="
		echo -e "=====================================================\n"
		if ssh "$SSH_READER" "chmod +x $PATH_FILE_UI"; then
			echo -e "====================================================="
			echo -e "=====✅SETTING UIMEDIA FILE PERMISSIONS DONE✅======="
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "====❌FAILED TO SET UIMEDIA FILE PERMISSIONS❌======="
			echo -e "=====================================================\n"
			return 1
		fi
	}

	# ===================================================================
	# Download script via SCP dari server local
	# ===================================================================
	update_script(){
		echo -e "====================================================="
		echo -e "==========📥SCP SCRIPT FROM SERVER📥================"
		echo -e "=====================================================\n"
		if sshpass -p "${PARKEE_SSH_PASS}" scp "${PARKEE_SSH_SERVER}:${PARKEE_SSH_SOURCE}/${SCRIPT_ZIP}" "$DOWNLOAD_DIR/$SCRIPT_ZIP"; then
			echo -e "====================================================="
			echo -e "=========✅SCP SCRIPT FROM SERVER DONE✅============="
			echo -e "=====================================================\n"
		else
			echo -e "====================================================="
			echo -e "=========❌FAILED SCP SCRIPT FROM SERVER❌==========="
			echo -e "=====================================================\n"
			return 1
		fi

		echo -e "====================================================="
		echo -e "============📂EXTRACTING SCRIPT FILES📂=============="
		echo -e "=====================================================\n"
		if ! unzip -o "$DOWNLOAD_DIR/$SCRIPT_ZIP" -d "$DOWNLOAD_DIR"; then
			echo -e "====================================================="
			echo -e "=========❌FAILED EXTRACTING SCRIPT FILE❌==========="
			echo -e "=====================================================\n"
			return 1
		else
			echo -e "====================================================="
			echo -e "==========✅EXTRACTING SCRIPT FILES DONE✅==========="
			echo -e "=====================================================\n"
		fi

		echo -e "====================================================="
		echo -e "=======🔄REMOVING ALL SCRIPT PARKEE READER🔄========="
		echo -e "=====================================================\n"

		echo -e "🔄PROCESS REMOVE SCRIPT $FILE_SCRIPT_parque_check🔄"
		if ! ssh "$SSH_READER" "rm -f $PATH_FILE_parque_check"; then
			echo -e "❌FAILED TO REMOVE SCRIPT $FILE_SCRIPT_parque_check❌"
			return 1
		else
			echo -e "✅REMOVE SCRIPT $FILE_SCRIPT_parque_check DONE✅\n"
		fi

		echo -e "🔄PROCESS REMOVE SCRIPT $FILE_SCRIPT_S40_parque🔄"
		if ! ssh "$SSH_READER" "rm -f $PATH_FILE_S40_parque"; then
			echo -e "❌FAILED TO REMOVE SCRIPT $FILE_SCRIPT_S40_parque❌"
			return 1
		else
			echo -e "✅REMOVE SCRIPT $FILE_SCRIPT_S40_parque DONE✅\n"
		fi

		echo -e "🔄PROCESS REMOVE SCRIPT $FILE_debug_config🔄"
		if ! ssh "$SSH_READER" "rm -f $PATH_FILE_debug_config"; then
			echo -e "❌FAILED TO REMOVE SCRIPT $FILE_debug_config❌"
			return 1
		else
			echo -e "✅REMOVE SCRIPT $FILE_debug_config DONE✅\n"
		fi

		echo -e "====================================================="
		echo -e "=====✅REMOVING ALL SCRIPT PARKEE READER DONE✅======"
		echo -e "=====================================================\n"

		echo -e "====================================================="
		echo -e "===📤UPDATE ALL SCRIPT READER TO PARKEE READER📤===="
		echo -e "=====================================================\n"

		echo -e "🔄PROCESS UPDATE SCRIPT $FILE_SCRIPT_parque_check🔄"
		if ! scp "$SCRIPT_DIR/$FILE_SCRIPT_parque_check" "$SSH_READER:$DIR_cronjob_reader"; then
			echo -e "❌FAILED UPDATE SCRIPT $FILE_SCRIPT_parque_check❌\n"
			return 1
		else
			echo -e "✅UPDATE $FILE_SCRIPT_parque_check DONE✅\n"
		fi

		echo -e "🔄PROCESS UPDATE SCRIPT $FILE_SCRIPT_S40_parque🔄"
		if ! scp "$SCRIPT_DIR/$FILE_SCRIPT_S40_parque" "$SSH_READER:$DIR_init_d"; then
			echo -e "❌FAILED UPDATE SCRIPT $FILE_SCRIPT_S40_parque❌\n"
			return 1
		else
			echo -e "✅UPDATE $FILE_SCRIPT_S40_parque DONE✅\n"
		fi

		echo -e "🔄PROCESS UPDATE SCRIPT $FILE_debug_config🔄"
		if ! scp "$SCRIPT_DIR/$FILE_debug_config" "$SSH_READER:$DIR_debug_config"; then
			echo -e "❌FAILED UPDATE SCRIPT $FILE_debug_config❌\n"
			return 1
		else
			echo -e "✅UPDATE $FILE_debug_config DONE✅\n"
		fi

		echo -e "====================================================="
		echo -e "=✅UPDATE ALL SCRIPT READER TO PARKEE READER DONE✅=="
		echo -e "=====================================================\n"

		echo -e "====================================================="
		echo -e "======🔧SETTING ALL SCRIPT FILE PERMISSIONS🔧========"
		echo -e "=====================================================\n"

		echo -e "🔄PROCESS chmod +x $FILE_SCRIPT_parque_check🔄"
		if ! ssh "$SSH_READER" "chmod +x $PATH_FILE_parque_check"; then
			echo -e "❌FAILED CHMOD $FILE_SCRIPT_parque_check❌\n"
			return 1
		else
			echo -e "✅PROCESS chmod +x $FILE_SCRIPT_parque_check DONE✅\n"
		fi

		echo -e "🔄PROCESS chmod +x $FILE_SCRIPT_S40_parque🔄"
		if ! ssh "$SSH_READER" "chmod +x $PATH_FILE_S40_parque"; then
			echo -e "❌FAILED CHMOD $FILE_SCRIPT_S40_parque❌\n"
			return 1
		else
			echo -e "✅PROCESS chmod +x $FILE_SCRIPT_S40_parque DONE✅\n"
		fi

		echo -e "🔄PROCESS chmod +x $FILE_debug_config🔄"
		if ! ssh "$SSH_READER" "chmod +x $PATH_FILE_debug_config"; then
			echo -e "❌FAILED CHMOD $FILE_debug_config❌\n"
			return 1
		else
			echo -e "✅PROCESS chmod +x $FILE_debug_config DONE✅\n"
		fi

		echo -e "====================================================="
		echo -e "====✅SETTING ALL SCRIPT FILE PERMISSIONS DONE✅====="
		echo -e "=====================================================\n"
	}

	# ===================================================================
	# Crontab reader (parque_check) — selalu dijalankan
	# ===================================================================
	crontab_reader(){
		echo -e "=================🚀CRONTAB READER CONFIG🚀============"
		echo -e "=====================📌BEFORE📌======================"
		ssh "$SSH_READER" "cat /apps/etc/crontabs/root | grep parque_check"
		echo -e "====================================================="
		ssh "$SSH_READER" "sed -i 's|^\s*1\s\+\*\s\+\*\s\+\*\s\+\*\s\+/apps/etc/cronjobs/parque_check|*/1  ****/apps/etc/cronjobs/parque_check|' /apps/etc/crontabs/root"
		echo -e "=====================📌AFTER📌======================="
		ssh "$SSH_READER" "cat /apps/etc/crontabs/root | grep parque_check"
		echo -e "=====================================================\n"
	}

	# ===================================================================
	# Crontab client — wajib untuk v17 dan v19 (pkill uimedia)
	# ===================================================================
	crontab_client_uimedia(){
		echo -e "====================================================="
		echo -e "=====🚀CRONTAB CLIENT: PKILL UIMEDIA (v${FW_VERSION})🚀====="
		echo -e "=====================📌BEFORE📌======================"
		crontab -l 2>/dev/null | grep "pkill /apps/parque/bin/uimedia" || echo "(belum ada)"
		echo -e "====================================================="
		(crontab -l 2>/dev/null | grep -v "pkill /apps/parque/bin/uimedia"; echo "*/10 * * * * ssh root@192.168.1.199 'pkill /apps/parque/bin/uimedia'") | crontab -
		echo -e "=====================📌AFTER📌======================="
		crontab -l | grep --color=auto "pkill"
		echo -e "====================================================="
		echo -e "✅CRONTAB CLIENT UIMEDIA PKILL DONE✅"
		echo -e "=====================================================\n"
	}

	# ===================================================================
	# Hapus file firmware & script di server setelah selesai
	# ===================================================================
	erase_server(){
		echo -e "====================================================="
		echo -e "=====🗑️DELETE FIRMWARE & SCRIPT FILES ON SERVER🗑️====="
		echo -e "=====================================================\n"

		echo -e "🔄DELETE $FW_ZIP ON SERVER🔄"
		sshpass -p "${PARKEE_SSH_PASS}" sftp ${PARKEE_SSH_OPT} "${PARKEE_SSH_SERVER}" <<EOF 2>/dev/null
rm ${PARKEE_SSH_SOURCE}/${FW_ZIP}
EOF
		if [ $? -eq 0 ]; then
			echo -e "✅DELETE $FW_ZIP ON SERVER DONE✅\n"
		else
			echo -e "⚠️FAILED DELETE $FW_ZIP ON SERVER, SKIP...⚠️\n"
		fi

		echo -e "🔄DELETE $SCRIPT_ZIP ON SERVER🔄"
		sshpass -p "${PARKEE_SSH_PASS}" sftp ${PARKEE_SSH_OPT} "${PARKEE_SSH_SERVER}" <<EOF 2>/dev/null
rm ${PARKEE_SSH_SOURCE}/${SCRIPT_ZIP}
EOF
		if [ $? -eq 0 ]; then
			echo -e "✅DELETE $SCRIPT_ZIP ON SERVER DONE✅\n"
		else
			echo -e "⚠️FAILED DELETE $SCRIPT_ZIP ON SERVER, SKIP...⚠️\n"
		fi

		echo -e "====================================================="
		echo -e "=====✅DELETE FILES ON SERVER DONE✅================="
		echo -e "=====================================================\n"
	}

	# ===================================================================
	# Hapus file lokal setelah selesai
	# ===================================================================
	erase_local(){
		echo -e "====================================================="
		echo -e "=======🗑️DELETE LOCAL FIRMWARE/SCRIPT FILES🗑️======="
		echo -e "=====================================================\n"

		echo -e "🔄DELETE $FW_ZIP IN DOWNLOADS🔄"
		if [ -e "$DOWNLOAD_DIR/$FW_ZIP" ]; then
			rm -rf "$DOWNLOAD_DIR/$FW_ZIP"
			echo -e "✅DELETE $FW_ZIP DONE✅\n"
		else
			echo -e "⚠️$FW_ZIP NOT FOUND, SKIPPING...⚠️\n"
		fi

		echo -e "🔄DELETE $FILE_FIRMWARE IN DOWNLOADS🔄"
		if [ -e "$DOWNLOAD_DIR/$FILE_FIRMWARE" ]; then
			rm -rf "$DOWNLOAD_DIR/$FILE_FIRMWARE"
			echo -e "✅DELETE $FILE_FIRMWARE DONE✅\n"
		else
			echo -e "⚠️$FILE_FIRMWARE NOT FOUND, SKIPPING...⚠️\n"
		fi

		echo -e "🔄DELETE $FILE_UI IN DOWNLOADS🔄"
		if [ -e "$DOWNLOAD_DIR/$FILE_UI" ]; then
			rm -rf "$DOWNLOAD_DIR/$FILE_UI"
			echo -e "✅DELETE $FILE_UI DONE✅\n"
		else
			echo -e "⚠️$FILE_UI NOT FOUND, SKIPPING...⚠️\n"
		fi

		echo -e "🔄DELETE $SCRIPT_ZIP IN DOWNLOADS🔄"
		if [ -e "$DOWNLOAD_DIR/$SCRIPT_ZIP" ]; then
			rm -rf "$DOWNLOAD_DIR/$SCRIPT_ZIP"
			echo -e "✅DELETE $SCRIPT_ZIP DONE✅\n"
		else
			echo -e "⚠️$SCRIPT_ZIP NOT FOUND, SKIPPING...⚠️\n"
		fi

		echo -e "🔄DELETE FOLDER $SCRIPT_NAME IN DOWNLOADS🔄"
		if [ -d "$DOWNLOAD_DIR/$SCRIPT_NAME" ]; then
			rm -rf "$DOWNLOAD_DIR/$SCRIPT_NAME"
			echo -e "✅DELETE FOLDER $SCRIPT_NAME DONE✅\n"
		else
			echo -e "⚠️FOLDER $SCRIPT_NAME NOT FOUND, SKIPPING...⚠️\n"
		fi

		echo -e "====================================================="
		echo -e "=======✅DELETE LOCAL FIRMWARE/SCRIPT FILES✅========"
		echo -e "=====================================================\n"
	}

	tuning_agent(){
		echo -e "Tuning Re-Open Agent"
		sudo truncate -s 0 /etc/systemd/system/parkee-agent.service
		sudo tee /etc/systemd/system/parkee-agent.service <<EOF
[Unit]
Description=Parkee Agent

[Service]
Type=simple
ExecStart=/opt/app/agent/parkee-agent/parkee-agent-service.sh
Environment="DISPLAY=:0"
Restart=on-failure
TimeoutStopSec=1
RestartSec=1

[Install]
WantedBy=graphical-session.target
Description=Parkee Agent Service
EOF
		sudo systemctl daemon-reload
		echo -e "Tuning Re-Open Agent - Done\n"
	}

	end(){
		echo -e "====================================================="
		echo -e "==============🔄REBOOT PARKEE READER🔄==============="
		echo -e "=====================================================\n"
		if ! ssh "$SSH_READER" "reboot now"; then
			echo -e "====================================================="
			echo "==========❌FAILED REBOOT PARKEE READER❌============"
			echo -e "=====================================================\n"
			return 1
		else
			echo -e "====================================================="
			echo -e "=====🚀PLEASE WAIT, PARKEE READER IS REBOOTING🚀====="
			echo -e "=====================================================\n"
			sleep 30
			echo -e "====================================================="
			echo -e "=========✅PARKEE READER HAS BEEN RUNNING✅=========="
			echo -e "=====================================================\n"
		fi

		echo -e "====================================================="
		echo -e "========🔄RESTARTING PARKEE AGENT SERVICE🔄=========="
		echo -e "=====================================================\n"
		if ! sudo systemctl restart parkee-agent; then
			echo -e "====================================================="
			echo -e "=====❌FAILED RESTARTING PARKEE AGENT SERVICE❌======"
			echo -e "=====================================================\n"
			return 1
		else
			echo -e "====================================================="
			echo -e "=🚀PLEASE WAIT, PARKEE AGENT SERVICE IS RESTARTING🚀="
			echo -e "=====================================================\n"
			echo -e "====================================================="
			echo -e "======✅PARKEE AGENT SERVICE HAS BEEN RUNNING✅======"
			echo -e "=====================================================\n"
		fi
	}

	# ===================================================================
	# MAIN
	# ===================================================================
	main(){
		clear
		echo -e "====================================================="
		echo -e "============🔄UPDATING FIRMWARE READER🔄============="
		echo -e "====================================================="

		pilih_versi_fw
		prepare_server_connection
		ensure_files_on_server || return 1
		bypass_script
		tuning_agent
		update_firmware
		update_script
		crontab_reader

		# Crontab client pkill uimedia — semua versi kecuali v14
		if [[ "$FW_VERSION" != "14" ]]; then
			crontab_client_uimedia
		fi

		erase_server
		erase_local
		end

		echo -e "====================================================="
		echo -e "=========✅UPDATING FIRMWARE READER DONE✅==========="
		echo -e "=====================================================\n"
	}

	main
}


cek_version() {
	clear
	echo -e "====================================================="
	echo -e "=================🔄GET INIT PSAM🔄=================="
	if ssh "$SSH_READER" 'ls /media/mmc/reader-log-*.log 1>/dev/null 2>&1'; then
	if ! ssh "$SSH_READER" "grep -A 2 'SAM Select' \$(ls -t /media/mmc/reader-log-*.log | head -n 1)"; then
		echo -e "==============❌FAILED GET INIT PSAM❌=============="
		echo -e "=====================================================\n"
		return 1
	else
		echo -e "===============✅GET GET INIT PSAM✅================"
		echo -e "=====================================================\n"
	fi
else
echo -e "===========⚠️ LOG FILE READER NOT FOUND⚠️============"
echo -e "=====================================================\n"
	fi
	
	echo -e "====================================================="
	echo -e "===========🔍GET PARKEE READER VERSION🔍============"
	if ssh "$SSH_READER" 'ls /media/mmc/reader-log-*.log 1>/dev/null 2>&1'; then	
	if ! ssh "$SSH_READER" 'head -n 90 "$(ls -t /media/mmc | head -n 1 | sed "s|^|/media/mmc/|")" | tail -n 6'; then
		echo -e "========❌FAILED GET PARKEE READER VERSION❌========"
		echo -e "=====================================================\n"
	else
		echo -e "=========✅GET PARKEE READER VERSION DONE✅========="
		echo -e "=====================================================\n"
	fi
	else
echo -e "===========⚠️ LOG FILE READER NOT FOUND⚠️============"
echo -e "=====================================================\n"
	fi

	echo -e "====================================================="
	echo -e "============🔍GET PARKEE AGENT VERSION🔍============"
	if ! head -n 7 /var/log/agent/parkee-agent/$(ls -t /var/log/agent/parkee-agent | head -n 1); then
		echo -e "========❌FAILED GET PARKEE AGENT VERSION❌========="
		echo -e "=====================================================\n"
	else
		echo -e "=========✅GET PARKEE AGENT VERSION DONE✅=========="
		echo -e "=====================================================\n"
	fi
	
	ssh $SSH_READER "cat $PATH_FILE_PSAM_config"
}

psam_dki(){	
	clear
	# Fungsi untuk menginstal PSAM DKI (menambahkan atau memperbarui konfigurasi DKI)
	install_psam_dki() {
		clear
		# Tampilkan konfigurasi sebelum perubahan
		echo -e "\n\n==========📌CONFIG PSAM [DKI] CURRENTLY📌==========="
		ssh $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "=====================================================\n\n"

		# Minta input dari user
		read -p "INPUT TID DKI: " NEW_TID_DKI
		read -p "INPUT MID DKI: " NEW_MID_DKI
		read -p "INPUT BATCH DKI: " NEW_BATCH_DKI
		read -p "INPUT SLOT DKI: " NEW_SLOT_DKI

		# Update file konfigurasi di server
		if ssh $SSH_READER "grep -q '^\[DKI\]' $PATH_FILE_PSAM_config"; then
		echo -e "📌PSAM [DKI] IS ACTIVE, ONLY UPDATE MID, TID, BATCH, AND SLOT📌"
		ssh $SSH_READER <<EOF
		sed -i '/^\[DKI\]/,/^\[/{ 
		s|^MID=.*|MID=$NEW_MID_DKI|; 
		s|^TID=.*|TID=$NEW_TID_DKI|; 
		s|^BATCH=.*|BATCH=$NEW_BATCH_DKI|; 
		s|^slot=.*|slot=$NEW_SLOT_DKI| 
		}' $PATH_FILE_PSAM_config
EOF
	else
		echo -e "📌PSAM [DKI] IS NOT ACTIVE YET, ACTIVATE IT FIRST📌"
		ssh $SSH_READER <<EOF
		sed -i '/^\#\[DKI\]/,/^\[/{ 
		s|^\#MID=.*|MID=$NEW_MID_DKI|; 
		s|^\#TID=.*|TID=$NEW_TID_DKI|; 
		s|^\#BATCH=.*|BATCH=$NEW_BATCH_DKI|; 
		s|^\#slot=.*|slot=$NEW_SLOT_DKI| 
		}' $PATH_FILE_PSAM_config
		sed -i 's/^\#\[DKI\]/\[DKI\]/' $PATH_FILE_PSAM_config
EOF
	fi


		# Tampilkan konfigurasi setelah perubahan
		echo -e "\n\n==============📌CONFIG PSAM DKI NOW📌==============="
		ssh $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "=====================================================\n\n"

	}

	non_active_psam_dki() {
		clear
		echo -e "\n\n==========📌CONFIG PSAM [DKI] CURRENTLY📌==========="
		ssh $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "=====================================================\n\n"

		echo -e "==============🔄DISABLING PSAM [DKI]🔄=============="
		ssh $SSH_READER << EOF
		sed -i '
		  /^\[DKI\]/,/^slot=/ {
		s/^\(MID=.*\)/#\1/;
		s/^\(TID=.*\)/#\1/;
		s/^\(BATCH=.*\)/#\1/;
		s/^\(slot=.*\)/#\1/;
		  }
		  s/^\(\[DKI\]\)/#\1/;
		' $PATH_FILE_PSAM_config
EOF

		echo -e "\n\n=============📌CONFIG PSAM [DKI] NOW📌=============="
		ssh $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "\n\n====================================================="
		echo -e "===✅PSAM [DKI] CONFIGURATION HAS BEEN DISABLED✅==="
		echo -e "=====================================================\n\n"
	}



	# Fungsi untuk mengaktifkan kembali [DKI]
	active_psam_dki() {
		clear
		echo -e "\n\n==========📌CONFIG PSAM [DKI] CURRENTLY📌==========="
		ssh -t $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "=====================================================\n\n"

		echo -e "==============🔄ENABLING PSAM [DKI]🔄==============="
		ssh -t $SSH_READER << EOF
		sed -i '
		  s/^#\(\[DKI\]\)/\1/;
		  s/^#\(MID=.*\)/\1/;
		  s/^#\(TID=.*\)/\1/;
		  s/^#\(BATCH=.*\)/\1/;
		  s/^#\(slot=.*\)/\1/;
		' $PATH_FILE_PSAM_config
EOF

		echo -e "\n\n=============📌CONFIG PSAM [DKI] NOW📌=============="
		ssh -t $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "\n\n====================================================="
		echo -e "===✅PSAM [DKI] CONFIGURATION HAS BEEN ENABLED✅===="
		echo -e "=====================================================\n\n"
	}

	# Fungsi untuk mengembalikan konfigurasi [DKI] ke default (clear config)
	clear_config_psam_dki() {
		clear
		echo -e "\n\n==========📌CONFIG PSAM [DKI] CURRENTLY📌==========="
		ssh $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "=====================================================\n\n"

		echo -e "==🔄RESTORE PSAM [DKI] CONFIGURATION TO DEFAULT🔄==="
		ssh -t $SSH_READER << EOF
		sed -i '
				# Hanya mencari dan mengubah bagian [DKI]
				/^\[DKI\]/ {
						s/^\[DKI\]/#[DKI]/;
						n; s/^MID=.*/#MID=INAB00000000001/;
						n; s/^TID=.*/#TID=INAPA0001/;
						n; s/^BATCH=.*/#BATCH=33/;
						n; s/^slot=.*/#slot=7/;
				}
		' $PATH_FILE_PSAM_config
EOF

		echo -e "\n\n=============📌CONFIG PSAM [DKI] NOW📌=============="
		ssh $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "\n\n====================================================="
		echo -e "===✅PSAM [DKI] CONFIGURATION HAS BEEN DEFAULT✅===="
		echo -e "=====================================================\n\n"
	}

	cek_psam_dki(){
		clear
		echo -e "\n\n=============📌CONFIG PSAM [DKI] NOW📌=============="
		ssh -t $SSH_READER "cat $PATH_FILE_PSAM_config"
		echo -e "=====================================================\n\n"
		
		echo -e "\n===============🔄INIT PSAM PROCESS🔄================\n"
		if ssh "$SSH_READER" 'ls /media/mmc/reader-log-*.log 1>/dev/null 2>&1'; then
		ssh -t $SSH_READER "grep -A 2 'SAM Select' \$(ls -t /media/mmc/reader-log-*.log | head -n 1)"
		echo -e "\n=================✅INIT PSAM DONE✅=================\n"
		else
		echo -e "===========⚠️ LOG FILE READER NOT FOUND⚠️============"
		echo -e "=====================================================\n"
		fi
	}
	
	reboot_reader_dki(){
		clear
		echo -e "====================================================="
		echo "==============🔄REBOOT PARKEE READER🔄=============="
		if ! ssh "$SSH_READER" "reboot now" ; then 
			echo "==========❌FAILED REBOOT PARKEE READER❌==========="
			echo -e "=====================================================\n"
			return 1
		else
			sleep 60
			echo "===========✅REBOOT PARKEE READER DONE✅============"
			echo -e "=====================================================\n"
		fi

		echo -e "====================================================="
		echo -e "========🔄RESTARTING PARKEE AGENT SERVICE🔄========="
		if ! sudo systemctl restart parkee-agent; then
			echo -e "=====❌FAILED RESTARTING PARKEE AGENT SERVICE❌====="
			echo -e "=====================================================\n"
			return 1
		else
			echo -e "======✅RESTARTING PARKEE AGENT SERVICE DONE✅======"
			echo -e "=====================================================\n"
		fi
		
		echo -e "====================================================="
		echo -e "===============🔄INIT PSAM PROCESS🔄================"
	if ! ssh "$SSH_READER" 'ls /media/mmc/reader-log-*.log 1>/dev/null 2>&1'; then
	echo -e "========❌LOG FILE TIDAK DITEMUKAN DI READER❌========"
	return 1
	fi
		if ! ssh "$SSH_READER" "grep -A 2 'SAM Select' \$(ls -t /media/mmc/reader-log-*.log | head -n 1)"; then
			echo -e "============❌FAILED INIT PSAM PROCESS❌============"
			echo -e "=====================================================\n"
			return 1
		else
			echo -e "=============✅INIT PSAM PROCESS DONE✅============="
			echo -e "=====================================================\n"
		fi

	}
	
		
	# Menu pilihan
	while true; do
echo -e "Gate : $(whoami)\n"
echo -e "IP: $(hostname -I)\n"
echo -e "Device Information : "

if ! command -v sshpass &> /dev/null; then
sudo apt update && sudo apt install sshpass -y
fi

if ! ssh root@192.168.1.199 "cat /apps/parque/data/config.ini | grep 'READER' -A 3"; then
echo -e "Can't Connect Reader"
fi

echo -e "\nPSAM DKI Information : "
if ! ssh root@192.168.1.199 "cat /apps/parque/data/config.ini | grep 'DKI' -A 4"; then
echo -e "Can't Connect Reader"
fi

		echo -e "--------------------------------------"
		echo -e "Pilih opsi:"
		echo -e "1) Install PSAM [DKI]"
		echo -e "2) Nonaktifkan PSAM [DKI]"
		echo -e "3) Aktifkan kembali PSAM [DKI]"
		echo -e "4) Reset PSAM [DKI] ke default"
		echo -e "5) Cek Config PSAM DKI"
		echo -e "6) Reboot Reader"
		echo -e "7) Exit"
		echo -e "--------------------------------------"
		read -p "INPUT pilihan (1-7): " pilihan

		case $pilihan in
		1) install_psam_dki ;;
		2) non_active_psam_dki ;;
		3) active_psam_dki ;;
		4) clear_config_psam_dki ;;
		5) cek_psam_dki ;;
		6) reboot_reader_dki ;;
		7) echo -e "kembali ke menu utama."; clear && return 1  ;;
		*) echo -e "Pilihan tidak valid, coba lagi." ;;
		esac
	done

}

reboot_reader() {
	clear
	echo -e "====================================================="
	echo -e "==============🔄REBOOT PARKEE READER🔄==============="
	echo -e "=====================================================\n"
	if ! ssh "$SSH_READER" "reboot now" ; then 
		echo -e "====================================================="
		echo "==========❌FAILED REBOOT PARKEE READER❌============"
		echo -e "=====================================================\n"
		return 1
	else
		echo -e "====================================================="
		echo -e "=====🚀PLEASE WAIT, PARKEE READER IS REBOOTING🚀====="
		echo -e "=====================================================\n"
		sleep 30
		sudo systemctl restart parkee-agent
		echo -e "====================================================="
		echo -e "=========✅PARKEE READER HAS BEEN RUNNING✅=========="
		echo -e "=====================================================\n"
	fi
	
	echo -e "====================================================="
	echo -e "===============🔄INIT PSAM PROCESS🔄================="
	echo -e "=====================================================\n"
	if ssh "$SSH_READER" 'ls /media/mmc/reader-log-*.log 1>/dev/null 2>&1'; then
	if ! ssh "$SSH_READER" "grep -A 2 'SAM Select' \$(ls -t /media/mmc/reader-log-*.log | head -n 1)"; then
		echo -e "====================================================="
		echo -e "============❌FAILED INIT PSAM PROCESS❌============="
		echo -e "=====================================================\n"
		return 1
	else
		echo -e "====================================================="
		echo -e "=============✅INIT PSAM PROCESS DONE✅=============="
		echo -e "=====================================================\n"
	fi
else
echo -e "===========⚠️ LOG FILE READER NOT FOUND⚠️============"
echo -e "=====================================================\n"
fi
}

# Menu utama
clear
while true; do
echo -e "Gate : $(whoami)"
echo -e "IP: $(hostname -I)\n"
echo -e "Device Information : "

#if ! command -v sshpass &> /dev/null; then
#sudo apt update && sudo apt install sshpass -y
#fi

if ! sshpass -p "$PASSWORD_READER" ssh -o StrictHostKeyChecking=no "$SSH_READER" "cat /apps/parque/data/config.ini | grep 'READER' -A 3"; then
echo -e "Can't Connect Reader"
fi

echo -e "\nPSAM DKI Information : "
if ! sshpass -p "$PASSWORD_READER" ssh -o StrictHostKeyChecking=no "$SSH_READER" "cat /apps/parque/data/config.ini | grep 'DKI' -A 4"; then
echo -e "Can't Connect Reader"
fi

	echo -e ""
	echo -e "====================================================="
	echo -e "==============🔧SETUP READER PARKEE🔧================"
	echo -e "====================================================="
	echo -e "0. Cek IP Semua NIC"
	echo -e "1. Pilih NIC/Port LAN untuk Ubah IP"
	echo -e "2. Setting Serial di Dev.prop"
	echo -e "3. Bypass SSH Reader"
	echo -e "4. Restart NIC/Port LAN"
	echo -e "5. Update Versi Reader"
	echo -e "6. Cek Versi Agent & Reader"
	echo -e "7. PSAM DKI"
	echo -e "8. Reboot Reader"
	echo -e "9. Keluar"
	echo -e "====================================================="
	read -p "INPUT pilihan (0-9): " pilihan

	case $pilihan in
	0) cek_ip ;;
	1) ubah_ip ;;
	2) serial_dev ;;
	3) bypass_reader ;;
	4) restart_nic ;;
	5) update_reader ;;
	6) cek_version ;;
	7) psam_dki ;;
	8) reboot_reader ;;
	9) echo -e "👋 Keluar..."; sleep 1; clear; exit ;;
	*) echo -e "❌ Pilihan tidak valid!";;
	esac
done

