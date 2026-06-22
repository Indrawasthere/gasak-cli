USERNAME_READER="${USERNAME_READER:-root}"
IP_READER="${IP_READER:-}"
PASSWORD_READER="${PASSWORD_READER:-}"
SSH_READER="$USERNAME_READER@$IP_READER"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

DIR_PSAM_config="/apps/parque/data"
FILE_PSAM_config="config.ini"
PATH_FILE_PSAM_config=$DIR_PSAM_config/$FILE_PSAM_config

DIR_FILE_READER="$HOME/Documents/PARKEE-READER"
DIR_FILE_READER_FW_8="$DIR_FILE_READER/Setup/v8"
DIR_FILE_READER_FW_12="$DIR_FILE_READER/Setup/v12"
DIR_FILE_READER_FW_13="$DIR_FILE_READER/Setup/v13"
DIR_FILE_READER_FW_14="$DIR_FILE_READER/Setup/v14"
DIR_FILE_READER_FW_17="$DIR_FILE_READER/Setup/v17"
DIR_FILE_READER_FW_19="$DIR_FILE_READER/Setup/v19"
DIR_FILE_READER_UPDATE_SCRIPT="$DIR_FILE_READER/Setup/jellies_scripts/scripts"

DIR_PARQUE="/apps/parque"
DIR_PARQUE_BIN="${DIR_PARQUE}/bin"
DIR_PARQUE_DATA="${DIR_PARQUE}/data"
FILE_FIRMWARE="parque"
FILE_UI="uimedia"
PATH_FILE_FIRMWARE="${DIR_PARQUE_BIN}/${FILE_FIRMWARE}"
PATH_FILE_UI="${DIR_PARQUE_BIN}/${FILE_UI}"

DIR_init_d="/apps/etc/init.d"
FILE_S33="S33_4g-signal"
FILE_S97="S97_4gjv2"
FILE_S41="S41_ocean"
FILE_S40="S40_parque"
PATH_FILE_S33="${DIR_init_d}/${FILE_S33}"
PATH_FILE_S97="${DIR_init_d}/${FILE_S97}"
PATH_FILE_S41="${DIR_init_d}/${FILE_S41}"
PATH_FILE_S40="${DIR_init_d}/${FILE_S40}"

DIR_OCEAN="/apps/ocean/etc"
FILE_H2CORE="h2core.ini"
FILE_DEBUG_CONFIG="debug.config"
PATH_FILE_H2CORE="${DIR_OCEAN}/${FILE_H2CORE}"
PATH_FILE_DEBUG_CONFIG="${DIR_OCEAN}/${FILE_DEBUG_CONFIG}"

DIR_CRONTAB="/apps/etc/crontabs"
FILE_ROOT="root"
PATH_FILE_ROOT="${DIR_CRONTAB}/${FILE_ROOT}"

DIR_CRONJOB="/apps/etc/cronjobs"
FILE_PARQUE_CHECK="parque_check"
PATH_FILE_PARQUE_CHECK="${DIR_CRONJOB}/${FILE_PARQUE_CHECK}"

bypass_reader(){
   if ! command -v sshpass &> /dev/null; then
      sudo apt update && sudo apt install sshpass -y
   fi

   sudo chown -R $USER:$GROUP $HOME/.ssh

   ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
   sshpass -p "${PASSWORD_READER}" ssh-copy-id -o StrictHostKeyChecking=no "${SSH_READER}"

   cd $HOME/
}


reboot_reader(){
   echo -e "Preparing For Reboot Reader"
   ssh "${SSH_READER}" "reboot now"
   sleep 30
   echo -e "Reboot Success\n"
}

mkdir_fw(){
   if ssh "${SSH_READER}" "[ ! -d '${DIR_PARQUE_BIN}' ]"; then
      echo -e "Process Create Folder ${DIR_PARQUE_BIN}"
      ssh "${SSH_READER}" "mkdir -p ${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Create Folder ${DIR_PARQUE_BIN} Success\n"
      else
         echo -e "Error Creating Folder ${DIR_PARQUE_BIN} on ${SSH_READER}"
      fi
   else
      echo -e "Folder ${DIR_PARQUE_BIN} Already Created"
   fi


   if ssh "${SSH_READER}" "[ ! -d '${DIR_PARQUE_DATA}' ]"; then

      echo -e "Process Create Folder ${DIR_PARQUE_DATA}"
      ssh "${SSH_READER}" "mkdir -p ${DIR_PARQUE_DATA}"

      if [ $? -eq 0 ]; then
         echo -e "Create Folder ${DIR_PARQUE_DATA} Success\n"
      else
         echo -e "Error Creating Folder ${DIR_PARQUE_DATA} on ${SSH_READER}"
      fi

   else
      echo -e "Folder ${DIR_PARQUE_DATA} Already Created\n"
   fi
}

disable_service(){
   if ssh "${SSH_READER}" "[ ! -f '${DIR_init_d}/_${FILE_S33}' ]"; then
      echo -e "Process Rename ${FILE_S33} to _${FILE_S33}"
      ssh "${SSH_READER}" "mv ${PATH_FILE_S33} ${DIR_init_d}/_${FILE_S33}"
      if [ $? -eq 0 ]; then
         echo -e "Rename File ${FILE_S33} to _${FILE_S33} Success\n"
      else
         echo -e "Error Renaming File ${FILE_S33} on ${SSH_READER}"
      fi
   else
      echo -e "File ${DIR_init_d}/_${FILE_S33} Already Exists, Skipping Rename of ${FILE_S33}"
   fi

   if ssh "${SSH_READER}" "[ ! -f '${DIR_init_d}/_${FILE_S97}' ]"; then
      echo -e "Process Rename ${FILE_S97} to _${FILE_S97}"
      ssh "${SSH_READER}" "mv ${PATH_FILE_S97} ${DIR_init_d}/_${FILE_S97}"
      if [ $? -eq 0 ]; then
         echo -e "Rename File ${FILE_S97} to _${FILE_S97} Success\n"
      else
         echo -e "Error Renaming File ${FILE_S97} on ${SSH_READER} "
      fi
   else
      echo -e "File ${DIR_init_d}/_${FILE_S97} Already Exists, Skipping Rename of ${FILE_S97}"
   fi

   if ssh "${SSH_READER}" "[ ! -f '${DIR_init_d}/_${FILE_S41}' ]"; then
      echo -e "Process Rename ${FILE_S41} to _${FILE_S41}"
      ssh "${SSH_READER}" "mv ${PATH_FILE_S41} ${DIR_init_d}/_${FILE_S41}"
      if [ $? -eq 0 ]; then
         echo -e "Rename File ${FILE_S41} to _${FILE_S41} Success\n"
      else
         echo -e "Error Renaming File ${FILE_S41} on ${SSH_READER} "
      fi
   else
      echo -e "File ${DIR_init_d}/_${FILE_S41} Already Exists, Skipping Rename of ${FILE_S41}\n"
   fi
}

fw_v8(){
   echo -e "Process Copy File ${FILE_FIRMWARE}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_FIRMWARE' ]"; then
      echo -e "File ${FILE_FIRMWARE} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_8}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_FIRMWARE} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_FIRMWARE} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_FIRMWARE}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_8}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   fi

   echo -e "Process Copy File ${FILE_UI}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_UI' ]"; then
      echo -e "File ${FILE_UI} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_8}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_UI} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_UI} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_UI}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_8}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   fi
}

copy_script_v8(){

   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG"
   ssh "${SSH_READER}" "rm ${PATH_FILE_DEBUG_CONFIG}"
   scp "${DIR_FILE_READER_FW_8}/${FILE_DEBUG_CONFIG}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG Success \n"

   echo -e "Process Delete & Copy File $FILE_H2CORE"
   ssh "${SSH_READER}" "rm ${PATH_FILE_H2CORE}"
   scp "${DIR_FILE_READER_FW_8}/${FILE_H2CORE}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_H2CORE Success \n"

   echo -e "Process Delete & Copy File $FILE_S40"
   ssh "${SSH_READER}" "rm ${PATH_FILE_S40}"
   scp "${DIR_FILE_READER_FW_8}/${FILE_S40}" "${SSH_READER}:${DIR_init_d}"
   echo -e "Process Delete & Copy File $FILE_S40 Success \n"

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_PARQUE_CHECK}' ]"; then
      echo -e "Delete & Copy File ${FILE_PARQUE_CHECK}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_PARQUE_CHECK}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_PARQUE_CHECK} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_8}/${FILE_PARQUE_CHECK}" "${SSH_READER}:${DIR_CRONJOB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_PARQUE_CHECK} Success\n"
         else
            echo -e "Error copying file ${FILE_PARQUE_CHECK} to ${SSH_READER}:${DIR_CRONJOB}\n"
         fi
      fi
   fi

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_ROOT}' ]"; then
      echo -e "Process Delete & Copy File ${FILE_ROOT}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_ROOT}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_ROOT} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_8}/${FILE_ROOT}" "${SSH_READER}:${DIR_CRONTAB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_ROOT} Success\n"
         else
            echo -e "Error copying file ${FILE_ROOT} to ${SSH_READER}:${DIR_CRONTAB}\n"
         fi
      fi
   fi
}

fw_v12(){
   echo -e "Process Copy File ${FILE_FIRMWARE}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_FIRMWARE' ]"; then
      echo -e "File ${FILE_FIRMWARE} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_12}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_FIRMWARE} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_FIRMWARE} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_FIRMWARE}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_12}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   fi

   echo -e "Process Copy File ${FILE_UI}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_UI' ]"; then
      echo -e "File ${FILE_UI} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_12}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_UI} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_UI} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_UI}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_12}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   fi
}

copy_script_v12(){

   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG"
   ssh "${SSH_READER}" "rm ${PATH_FILE_DEBUG_CONFIG}"
   scp "${DIR_FILE_READER_FW_12}/${FILE_DEBUG_CONFIG}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG Success \n"

   echo -e "Process Delete & Copy File $FILE_H2CORE"
   ssh "${SSH_READER}" "rm ${PATH_FILE_H2CORE}"
   scp "${DIR_FILE_READER_FW_12}/${FILE_H2CORE}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_H2CORE Success \n"

   echo -e "Process Delete & Copy File $FILE_S40"
   ssh "${SSH_READER}" "rm ${PATH_FILE_S40}"
   scp "${DIR_FILE_READER_FW_12}/${FILE_S40}" "${SSH_READER}:${DIR_init_d}"
   echo -e "Process Delete & Copy File $FILE_S40 Success \n"

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_PARQUE_CHECK}' ]"; then
      echo -e "Delete & Copy File ${FILE_PARQUE_CHECK}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_PARQUE_CHECK}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_PARQUE_CHECK} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_12}/${FILE_PARQUE_CHECK}" "${SSH_READER}:${DIR_CRONJOB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_PARQUE_CHECK} Success\n"
         else
            echo -e "Error copying file ${FILE_PARQUE_CHECK} to ${SSH_READER}:${DIR_CRONJOB}\n"
         fi
      fi
   fi

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_ROOT}' ]"; then
      echo -e "Process Delete & Copy File ${FILE_ROOT}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_ROOT}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_ROOT} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_12}/${FILE_ROOT}" "${SSH_READER}:${DIR_CRONTAB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_ROOT} Success\n"
         else
            echo -e "Error copying file ${FILE_ROOT} to ${SSH_READER}:${DIR_CRONTAB}\n"
         fi
      fi
   fi
}

chmod_file(){
   echo -e "Process Set Permission chmod 777 in ${PATH_FILE_FIRMWARE}"
   if ! ssh "${SSH_READER}" "chmod 777 ${PATH_FILE_FIRMWARE}"; then
      echo -e "Error Set Permission chmod 777 in ${PATH_FILE_FIRMWARE}\n"
   else
      echo -e "Set Permission chmod 777 in ${PATH_FILE_FIRMWARE} Success\n"
   fi

   echo -e "Process Set Permission chmod 777 in ${PATH_FILE_UI}"
   if ! ssh "${SSH_READER}" "chmod 777 ${PATH_FILE_UI}"; then
      echo -e "Error Set Permission chmod 777 in ${PATH_FILE_UI}\n"
   else
      echo -e "Set Permission chmod 777 in ${PATH_FILE_UI} Success\n"
   fi

   echo -e "Process Set Permission chmod 777 in ${PATH_FILE_DEBUG_CONFIG}"
   if ! ssh "${SSH_READER}" "chmod 777 ${PATH_FILE_DEBUG_CONFIG}"; then
      echo -e "Error Set Permission chmod 777 in ${PATH_FILE_DEBUG_CONFIG}\n"
   else
      echo -e "Set Permission chmod 777 in ${PATH_FILE_DEBUG_CONFIG} Success\n"
   fi

   echo -e "Process Set Permission chmod 777 in ${PATH_FILE_H2CORE}"
   if ! ssh "${SSH_READER}" "chmod 777 ${PATH_FILE_H2CORE}"; then
      echo -e "Error Set Permission chmod 777 in ${PATH_FILE_H2CORE}\n"
   else
      echo -e "Set Permission chmod 777 in ${PATH_FILE_H2CORE} Success\n"
   fi

   echo -e "Process Set Permission chmod 777 in ${PATH_FILE_S40}"
   if ! ssh "${SSH_READER}" "chmod 777 ${PATH_FILE_S40}"; then
      echo -e "Error Set Permission chmod 777 in ${PATH_FILE_S40}\n"
   else
      echo -e "Set Permission chmod 777 in ${PATH_FILE_S40} Success\n"
   fi

   echo -e "Process Set Permission chmod 777 in ${PATH_FILE_ROOT}"
   if ! ssh "${SSH_READER}" "chmod 777 ${PATH_FILE_ROOT}"; then
      echo -e "Error Set Permission chmod 777 in ${PATH_FILE_ROOT}\n"
   else
      echo -e "Set Permission chmod 777 in ${PATH_FILE_ROOT} Success\n"
   fi

   echo -e "Process Set Permission chmod 777 in ${PATH_FILE_PARQUE_CHECK}"
   if ! ssh "${SSH_READER}" "chmod 777 ${PATH_FILE_PARQUE_CHECK}"; then
      echo -e "Error Set Permission chmod 777 in ${PATH_FILE_PARQUE_CHECK}\n"
   else
      echo -e "Set Permission chmod 777 in ${PATH_FILE_PARQUE_CHECK} Success\n"
   fi
}

crontab(){
   echo -e "Before:"
   ssh "$SSH_READER" "cat $PATH_FILE_ROOT | grep $FILE_PARQUE_CHECK"
   ssh "$SSH_READER" "sed -i 's|^\s*1\s\+\*\s\+\*\s\+\*\s\+\*\s\+/apps/etc/cronjobs/parque_check|   */1  *   *   *   *   /apps/etc/cronjobs/parque_check|' /apps/etc/crontabs/root"
   echo -e "After:"
   ssh "$SSH_READER" "cat $PATH_FILE_ROOT | grep $FILE_PARQUE_CHECK"
}


update_script(){
	echo -e "Process Remove Script $FILE_PARQUE_CHECK To Parkee Reader"
	if ! ssh "$SSH_READER" "rm -f $PATH_FILE_PARQUE_CHECK" ; then
		echo -e "Failed to Remove Script $FILE_PARQUE_CHECK.\n"
		return 1
	else
		echo -e "Remove Script $FILE_PARQUE_CHECK To Parkee Reader Done\n"
	fi

	echo -e "Process Remove Script $FILE_S40 To Parkee Reader"
	if ! ssh "$SSH_READER" "rm -f $PATH_FILE_S40" ; then
		echo -e "Failed to Remove Script $FILE_S40.\n"
		return 1
	else
		echo -e "Remove Script $FILE_S40 To Parkee Reader Done\n"
	fi

	echo -e "Process Remove Script $FILE_DEBUG_CONFIG To Parkee Reader"
	if ! ssh "$SSH_READER" "rm -f $PATH_FILE_DEBUG_CONFIG" ; then
		echo -e "Failed to Remove Script $FILE_DEBUG_CONFIG.\n"
		return 1
	else
		echo -e "Remove Script $FILE_DEBUG_CONFIG To Parkee Reader Done\n"
	fi

	echo -e "Proccess Copy File ${FILE_PARQUE_CHECK} to Reader Parkee"
	if ! scp ${DIR_FILE_READER_UPDATE_SCRIPT}/${FILE_PARQUE_CHECK} ${SSH_READER}:${DIR_CRONJOB}; then
	   echo -e "Failed Copy File ${FILE_PARQUE_CHECK} to Parkee Reader\n"
	else
	   echo -e "Copy File ${FILE_PARQUE_CHECK} to Reader Parkee Done\n"
	fi

	echo -e "Proccess Copy File ${FILE_DEBUG_CONFIG} to Reader Parkee"
	if ! scp ${DIR_FILE_READER_UPDATE_SCRIPT}/${FILE_DEBUG_CONFIG} ${SSH_READER}:${DIR_OCEAN}; then
	   echo -e "Failed Copy File ${FILE_DEBUG_CONFIG} to Parkee Reader\n"
	else
	   echo -e "Copy File ${FILE_DEBUG_CONFIG} to Reader Parkee Done\n"
	fi

	echo -e "Proccess Copy File ${FILE_S40} to Reader Parkee"
	if ! scp ${DIR_FILE_READER_UPDATE_SCRIPT}/${FILE_S40} ${SSH_READER}:${DIR_init_d}; then
	   echo -e "Failed Copy File ${FILE_S40} to Parkee Reader\n"
	else
	   echo -e "Copy File ${FILE_S40} to Reader Parkee Done\n"
	fi

	echo -e "Process Set Permission ${FILE_PARQUE_CHECK} in ${PATH_FILE_PARQUE_CHECK}"
	if ! ssh ${SSH_READER} "chmod 775 ${PATH_FILE_PARQUE_CHECK}"; then
	   echo -e "Set Permission ${FILE_PARQUE_CHECK} in ${PATH_FILE_PARQUE_CHECK} Failed\n"
	   return 1
	else
	   echo -e "Set Permission ${FILE_PARQUE_CHECK} in ${PATH_FILE_PARQUE_CHECK} Success\n"
	fi

	echo -e "Process Set Permission ${FILE_S40} in ${PATH_FILE_S40}"
	if ! ssh ${SSH_READER} "chmod 775 ${PATH_FILE_S40}"; then
	   echo -e "Set Permission ${FILE_S40} in ${PATH_FILE_S40} Failed\n"
	   return 1
	else
	   echo -e "Set Permission ${FILE_S40} in ${PATH_FILE_S40} Success\n"
	fi

	echo -e "Process Set Permission ${FILE_DEBUG_CONFIG} in ${PATH_FILE_DEBUG_CONFIG}"
	if ! ssh ${SSH_READER} "chmod 775 ${PATH_FILE_DEBUG_CONFIG}";then
	   echo -e "Set Permission ${FILE_DEBUG_CONFIG} in ${PATH_FILE_DEBUG_CONFIG} Failed\n"
	   return 1
	else
	   echo -e "Set Permission ${FILE_DEBUG_CONFIG} in ${PATH_FILE_DEBUG_CONFIG} Success\n"
	fi

	crontab
}


fw_v13(){
   echo -e "Process Copy File ${FILE_FIRMWARE}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_FIRMWARE' ]"; then
      echo -e "File ${FILE_FIRMWARE} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_13}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_FIRMWARE} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_FIRMWARE} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_FIRMWARE}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_13}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   fi

   echo -e "Process Copy File ${FILE_UI}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_UI' ]"; then
      echo -e "File ${FILE_UI} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_13}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_UI} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_UI} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_UI}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_13}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   fi
}

copy_script_v13(){

   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG"
   ssh "${SSH_READER}" "rm ${PATH_FILE_DEBUG_CONFIG}"
   scp "${DIR_FILE_READER_FW_13}/${FILE_DEBUG_CONFIG}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG Success \n"

   echo -e "Process Delete & Copy File $FILE_H2CORE"
   ssh "${SSH_READER}" "rm ${PATH_FILE_H2CORE}"
   scp "${DIR_FILE_READER_FW_13}/${FILE_H2CORE}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_H2CORE Success \n"

   echo -e "Process Delete & Copy File $FILE_S40"
   ssh "${SSH_READER}" "rm ${PATH_FILE_S40}"
   scp "${DIR_FILE_READER_FW_13}/${FILE_S40}" "${SSH_READER}:${DIR_init_d}"
   echo -e "Process Delete & Copy File $FILE_S40 Success \n"

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_PARQUE_CHECK}' ]"; then
      echo -e "Delete & Copy File ${FILE_PARQUE_CHECK}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_PARQUE_CHECK}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_PARQUE_CHECK} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_13}/${FILE_PARQUE_CHECK}" "${SSH_READER}:${DIR_CRONJOB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_PARQUE_CHECK} Success\n"
         else
            echo -e "Error copying file ${FILE_PARQUE_CHECK} to ${SSH_READER}:${DIR_CRONJOB}\n"
         fi
      fi
   fi

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_ROOT}' ]"; then
      echo -e "Process Delete & Copy File ${FILE_ROOT}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_ROOT}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_ROOT} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_13}/${FILE_ROOT}" "${SSH_READER}:${DIR_CRONTAB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_ROOT} Success\n"
         else
            echo -e "Error copying file ${FILE_ROOT} to ${SSH_READER}:${DIR_CRONTAB}\n"
         fi
      fi
   fi
}

fw_v14(){
   echo -e "Process Copy File ${FILE_FIRMWARE}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_FIRMWARE' ]"; then
      echo -e "File ${FILE_FIRMWARE} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_14}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_FIRMWARE} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_FIRMWARE} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_FIRMWARE}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_14}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   fi

   echo -e "Process Copy File ${FILE_UI}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_UI' ]"; then
      echo -e "File ${FILE_UI} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_14}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_UI} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_UI} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_UI}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_14}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   fi
}

copy_script_v14(){

   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG"
   ssh "${SSH_READER}" "rm ${PATH_FILE_DEBUG_CONFIG}"
   scp "${DIR_FILE_READER_FW_14}/${FILE_DEBUG_CONFIG}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG Success \n"

   echo -e "Process Delete & Copy File $FILE_H2CORE"
   ssh "${SSH_READER}" "rm ${PATH_FILE_H2CORE}"
   scp "${DIR_FILE_READER_FW_14}/${FILE_H2CORE}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_H2CORE Success \n"

   echo -e "Process Delete & Copy File $FILE_S40"
   ssh "${SSH_READER}" "rm ${PATH_FILE_S40}"
   scp "${DIR_FILE_READER_FW_14}/${FILE_S40}" "${SSH_READER}:${DIR_init_d}"
   echo -e "Process Delete & Copy File $FILE_S40 Success \n"

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_PARQUE_CHECK}' ]"; then
      echo -e "Delete & Copy File ${FILE_PARQUE_CHECK}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_PARQUE_CHECK}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_PARQUE_CHECK} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_14}/${FILE_PARQUE_CHECK}" "${SSH_READER}:${DIR_CRONJOB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_PARQUE_CHECK} Success\n"
         else
            echo -e "Error copying file ${FILE_PARQUE_CHECK} to ${SSH_READER}:${DIR_CRONJOB}\n"
         fi
      fi
   fi

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_ROOT}' ]"; then
      echo -e "Process Delete & Copy File ${FILE_ROOT}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_ROOT}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_ROOT} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_14}/${FILE_ROOT}" "${SSH_READER}:${DIR_CRONTAB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_ROOT} Success\n"
         else
            echo -e "Error copying file ${FILE_ROOT} to ${SSH_READER}:${DIR_CRONTAB}\n"
         fi
      fi
   fi
}

fw_v17(){
   echo -e "Process Copy File ${FILE_FIRMWARE}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_FIRMWARE' ]"; then
      echo -e "File ${FILE_FIRMWARE} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_17}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_FIRMWARE} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_FIRMWARE} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_FIRMWARE}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_17}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   fi

   echo -e "Process Copy File ${FILE_UI}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_UI' ]"; then
      echo -e "File ${FILE_UI} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_17}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_UI} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_UI} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_UI}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_17}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   fi
}

copy_script_v17(){

   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG"
   ssh "${SSH_READER}" "rm ${PATH_FILE_DEBUG_CONFIG}"
   scp "${DIR_FILE_READER_FW_17}/${FILE_DEBUG_CONFIG}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG Success \n"

   echo -e "Process Delete & Copy File $FILE_H2CORE"
   ssh "${SSH_READER}" "rm ${PATH_FILE_H2CORE}"
   scp "${DIR_FILE_READER_FW_17}/${FILE_H2CORE}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_H2CORE Success \n"

   echo -e "Process Delete & Copy File $FILE_S40"
   ssh "${SSH_READER}" "rm ${PATH_FILE_S40}"
   scp "${DIR_FILE_READER_FW_17}/${FILE_S40}" "${SSH_READER}:${DIR_init_d}"
   echo -e "Process Delete & Copy File $FILE_S40 Success \n"

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_PARQUE_CHECK}' ]"; then
      echo -e "Delete & Copy File ${FILE_PARQUE_CHECK}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_PARQUE_CHECK}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_PARQUE_CHECK} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_17}/${FILE_PARQUE_CHECK}" "${SSH_READER}:${DIR_CRONJOB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_PARQUE_CHECK} Success\n"
         else
            echo -e "Error copying file ${FILE_PARQUE_CHECK} to ${SSH_READER}:${DIR_CRONJOB}\n"
         fi
      fi
   fi

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_ROOT}' ]"; then
      echo -e "Process Delete & Copy File ${FILE_ROOT}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_ROOT}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_ROOT} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_17}/${FILE_ROOT}" "${SSH_READER}:${DIR_CRONTAB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_ROOT} Success\n"
         else
            echo -e "Error copying file ${FILE_ROOT} to ${SSH_READER}:${DIR_CRONTAB}\n"
         fi
      fi
   fi
}

fw_v19(){
   echo -e "Process Copy File ${FILE_FIRMWARE}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_FIRMWARE' ]"; then
      echo -e "File ${FILE_FIRMWARE} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_19}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_FIRMWARE} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_FIRMWARE} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_FIRMWARE}"
      echo -e "Process Copy File ${FILE_FIRMWARE}"
      scp "${DIR_FILE_READER_FW_19}/${FILE_FIRMWARE}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_FIRMWARE} Success\n"
      else
         echo -e "Error Copy File ${FILE_FIRMWARE} on ${SSH_READER}"
      fi
   fi

   echo -e "Process Copy File ${FILE_UI}"
   if ssh "${SSH_READER}" "[ ! -f '$PATH_FILE_UI' ]"; then
      echo -e "File ${FILE_UI} Not Found !!!! on ${SSH_READER}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_19}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   else
      echo -e "File ${FILE_UI} Found !!!! on ${SSH_READER}"
      echo -e "Delete File ${FILE_UI} on Reader"
      ssh "${SSH_READER}" "rm ${PATH_FILE_UI}"
      echo -e "Process Copy File ${FILE_UI}"
      scp "${DIR_FILE_READER_FW_19}/${FILE_UI}" "${SSH_READER}:${DIR_PARQUE_BIN}"
      if [ $? -eq 0 ]; then
         echo -e "Copy File ${FILE_UI} Success\n"
      else
         echo -e "Error Copy File ${FILE_UI} on ${SSH_READER}"
      fi
   fi
}

copy_script_v19(){

   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG"
   ssh "${SSH_READER}" "rm ${PATH_FILE_DEBUG_CONFIG}"
   scp "${DIR_FILE_READER_FW_19}/${FILE_DEBUG_CONFIG}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_DEBUG_CONFIG Success \n"

   echo -e "Process Delete & Copy File $FILE_H2CORE"
   ssh "${SSH_READER}" "rm ${PATH_FILE_H2CORE}"
   scp "${DIR_FILE_READER_FW_19}/${FILE_H2CORE}" "${SSH_READER}:${DIR_OCEAN}"
   echo -e "Process Delete & Copy File $FILE_H2CORE Success \n"

   echo -e "Process Delete & Copy File $FILE_S40"
   ssh "${SSH_READER}" "rm ${PATH_FILE_S40}"
   scp "${DIR_FILE_READER_FW_19}/${FILE_S40}" "${SSH_READER}:${DIR_init_d}"
   echo -e "Process Delete & Copy File $FILE_S40 Success \n"

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_PARQUE_CHECK}' ]"; then
      echo -e "Delete & Copy File ${FILE_PARQUE_CHECK}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_PARQUE_CHECK}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_PARQUE_CHECK} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_19}/${FILE_PARQUE_CHECK}" "${SSH_READER}:${DIR_CRONJOB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_PARQUE_CHECK} Success\n"
         else
            echo -e "Error copying file ${FILE_PARQUE_CHECK} to ${SSH_READER}:${DIR_CRONJOB}\n"
         fi
      fi
   fi

   if ssh "${SSH_READER}" "[ -f '${PATH_FILE_ROOT}' ]"; then
      echo -e "Process Delete & Copy File ${FILE_ROOT}"
      ssh "${SSH_READER}" "rm ${PATH_FILE_ROOT}"
      if [ $? -ne 0 ]; then
         echo -e "Error deleting file ${PATH_FILE_ROOT} on ${SSH_READER}\n"
      else
         scp "${DIR_FILE_READER_FW_19}/${FILE_ROOT}" "${SSH_READER}:${DIR_CRONTAB}"
         if [ $? -eq 0 ]; then
            echo -e "Delete & Copy File ${FILE_ROOT} Success\n"
         else
            echo -e "Error copying file ${FILE_ROOT} to ${SSH_READER}:${DIR_CRONTAB}\n"
         fi
      fi
   fi
}

config_PSAM(){
   #new_reader_v19
   echo -e "\n====================================================\n"
   echo -e "\nPastikan Semua PSAM sudah terpasang\n"
	read -p "INPUT DEVICE NAME: " DEVICE_NAME
	read -p "INPUT TID DEVICE: " TID_DEVICE

	if [ ! -d "${DIR_FILE_READER}/${DEVICE_NAME}" ]; then
		echo -e "Create Folder for config.ini, etc...\n"
		mkdir -p "${DIR_FILE_READER}/${DEVICE_NAME}"
	else
		echo -e "Folder Reader Already Exist...\n"
	fi

	#echo -e "Process Bypass Reader"
	#bypass_reader
	#echo -e "Bypass Reader Done\n"

	echo -e "Backup Default ${FILE_PSAM_config}"
	scp "${SSH_READER}:${PATH_FILE_PSAM_config}" "${DIR_FILE_READER}/${DEVICE_NAME}"
	ssh "${SSH_READER}" "cat ${PATH_FILE_PSAM_config}"
	#sleep 10
	cd "${DIR_FILE_READER}/${DEVICE_NAME}"
	cp "${DIR_FILE_READER}/${DEVICE_NAME}/${FILE_PSAM_config}" "default_config_$(date +%d_%m_%Y-%H_%M_%S).ini"
	ls -lhtr
	echo -e "Backup Default ${FILE_PSAM_config} - Done\n"

	#read -p "Lanjut untuk ubah Config PSAM (y/n)? " ANSWER
	#if [[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]; then
		truncate -s 0 "${DIR_FILE_READER}/${DEVICE_NAME}/${FILE_PSAM_config}"
		nano "${DIR_FILE_READER}/${DEVICE_NAME}/${FILE_PSAM_config}"
   #fi

	#read -p "Lanjut untuk ubah Config CMS (y/n)? " ANSWER
	#if [[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]; then
	#   truncate -s 0 "${DIR_FILE_READER}/${DEVICE_NAME}/config_CMS_${TID_DEVICE}.ini"
	#   nano "${DIR_FILE_READER}/${DEVICE_NAME}/config_CMS_${TID_DEVICE}.ini"
   #fi

	#read -p "Lanjut SCP file ${FILE_PSAM_config} ke READER jangan lupa COPY Married Code BNI (y/n)? " ANSWER
	#if [[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]; then
		scp "${DIR_FILE_READER}/${DEVICE_NAME}/${FILE_PSAM_config}" "${SSH_READER}:${PATH_FILE_PSAM_config}"
		ssh "${SSH_READER}" "cat ${PATH_FILE_PSAM_config}"
   #fi

   #read -p "Reboot? (y/n)? " ANSWER
   #if [[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]; then
		reboot_reader
		sleep 15
		echo -e "Jangan lupa COPY Married Code BNI ke Sheet"
		ssh "${SSH_READER}" "cat ${PATH_FILE_PSAM_config}"
		sleep 1
   #fi

   #read -p "Backup File config.ini? (y/n)? " ANSWER
   #if [[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]; then
      echo -e "Backup File ${FILE_PSAM_config} untuk jaga-jaga ke Folder ${DIR_FILE_READER}/${DEVICE_NAME}"
      scp "${SSH_READER}:$PATH_FILE_PSAM_config" "${DIR_FILE_READER}/${DEVICE_NAME}"
      backup_timestamp=$(date +%d_%m_%Y-%H_%M_%S)
      cp "${DIR_FILE_READER}/${DEVICE_NAME}/${FILE_PSAM_config}" "backup_config_${TID_DEVICE}_${backup_timestamp}.ini"
      echo -e "Nama Filenya adalah backup_config_${TID_DEVICE}_${backup_timestamp}.ini\n"
      cp "${DIR_FILE_READER}/${DEVICE_NAME}/${FILE_PSAM_config}" "${DIR_FILE_READER}/${DEVICE_NAME}/config_${TID_DEVICE}.ini"
      echo -e "File config_${TID_DEVICE}.ini tolong kasih ke bang Fahmi\n"
      #echo -e "\n====================================================\n"
      #echo -e "Monggo Daftarin ke CMS yakk confignya begini: "
      #cat "${DIR_FILE_READER}/${DEVICE_NAME}/config_CMS_${TID_DEVICE}.ini"
      sleep 1
      echo -e "\n====================================================\n"
      ssh "${SSH_READER}" "grep '^MRG=' ${PATH_FILE_PSAM_config} | head -4 | cut -d'=' -f2"
      echo -e "\n====================================================\n"
   #fi
}

cek_config_PSAM(){
   clear
   read -p "INPUT DEVICE NAME: " DEVICE_NAME
   read -p "INPUT TID DEVICE: " TID_DEVICE
   echo -e "\n====================================================\n"
   cat "${DIR_FILE_READER}/${DEVICE_NAME}/config_${TID_DEVICE}.ini"
   echo -e "\n====================================================\n"
   #cat "${DIR_FILE_READER}/${DEVICE_NAME}/config_CMS_${TID_DEVICE}.ini"
   #echo -e "\n====================================================\n"
}

new_reader_v8(){
   clear
   bypass_reader
   mkdir_fw
   fw_v8
   disable_service
   copy_script_v8
   chmod_file
   update_script
   reboot_reader
}

new_reader_v12(){
   clear
   bypass_reader
   mkdir_fw
   fw_v12
   disable_service
   copy_script_v12
   chmod_file
   update_script
   reboot_reader
}

new_reader_v13(){
   clear
   bypass_reader
   mkdir_fw
   fw_v13
   disable_service
   copy_script_v13
   chmod_file
   update_script
   reboot_reader
}

new_reader_v14(){
   clear
   bypass_reader
   #ssh "${SSH_READER}" "rm ${PATH_FILE_PSAM_config}"
   mkdir_fw
   #scp "${DIR_FILE_READER}/076-v2t-04/config.ini" "${SSH_READER}:$PATH_FILE_PSAM_config"
   fw_v14
   disable_service
   copy_script_v14
   chmod_file
   update_script
   #reboot_reader
}

new_reader_v17(){
   clear
   bypass_reader
   #ssh "${SSH_READER}" "rm ${PATH_FILE_PSAM_config}"
   mkdir_fw
   #scp "${DIR_FILE_READER}/076-v2t-04/config.ini" "${SSH_READER}:$PATH_FILE_PSAM_config"
   fw_v17
   disable_service
   copy_script_v17
   chmod_file
   update_script
   #reboot_reader
}


new_reader_v19(){
   clear
   bypass_reader
   #ssh "${SSH_READER}" "rm ${PATH_FILE_PSAM_config}"
   mkdir_fw
   #scp "${DIR_FILE_READER}/076-v2t-04/config.ini" "${SSH_READER}:$PATH_FILE_PSAM_config"
   fw_v19
   disable_service
   copy_script_v19
   chmod_file
   update_script
   #reboot_reader
}

download_java(){
   DL_FOLDER="$HOME/Downloads"
   BASE_URL='https://download.bell-sw.com/java'

   VERSION_JAVA_11='11.0.27+9'
   VERSION_JAVA_13='13.0.2+9'
   VERSION_JAVA_15='15.0.2+10'
   VERSION_JAVA_17='17.0.15+10'
   VERSION_JAVA_19='19.0.2+9'
   VERSION_JAVA_21='21.0.3+12'

   PATH_BIN_JAVA_11="/usr/lib/jvm/bellsoft-java11-full-amd64/bin/java"
   PATH_BIN_JAVA_13="/usr/lib/jvm/bellsoft-java13-full-amd64/bin/java"
   PATH_BIN_JAVA_15="/usr/lib/jvm/bellsoft-java15-full-amd64/bin/java"
   PATH_BIN_JAVA_17="/usr/lib/jvm/bellsoft-java17-full-amd64/bin/java"
   PATH_BIN_JAVA_19="/usr/lib/jvm/bellsoft-java19-full-amd64/bin/java"
   PATH_BIN_JAVA_21="/usr/lib/jvm/bellsoft-java21-full-amd64/bin/java"

   FILENAME_JAVA_11="bellsoft-jdk${VERSION_JAVA_11}-linux-amd64-full.deb"
   FILENAME_JAVA_13="bellsoft-jdk${VERSION_JAVA_13}-linux-amd64-full.deb"
   FILENAME_JAVA_15="bellsoft-jdk${VERSION_JAVA_15}-linux-amd64-full.deb"
   FILENAME_JAVA_17="bellsoft-jdk${VERSION_JAVA_17}-linux-amd64-full.deb"
   FILENAME_JAVA_19="bellsoft-jdk${VERSION_JAVA_19}-linux-amd64-full.deb"
   FILENAME_JAVA_21="bellsoft-jdk${VERSION_JAVA_21}-linux-amd64-full.deb"

   PATH_FILE_JAVA_11="${DL_FOLDER}/${FILENAME_JAVA_11}"
   PATH_FILE_JAVA_13="${DL_FOLDER}/${FILENAME_JAVA_13}"
   PATH_FILE_JAVA_15="${DL_FOLDER}/${FILENAME_JAVA_15}"
   PATH_FILE_JAVA_17="${DL_FOLDER}/${FILENAME_JAVA_17}"
   PATH_FILE_JAVA_19="${DL_FOLDER}/${FILENAME_JAVA_19}"
   PATH_FILE_JAVA_21="${DL_FOLDER}/${FILENAME_JAVA_21}"

   URL_DL_JAVA_11="${BASE_URL}/${VERSION_JAVA_11}/${FILENAME_JAVA_11}"
   URL_DL_JAVA_13="${BASE_URL}/${VERSION_JAVA_13}/${FILENAME_JAVA_13}"
   URL_DL_JAVA_15="${BASE_URL}/${VERSION_JAVA_15}/${FILENAME_JAVA_15}"
   URL_DL_JAVA_17="${BASE_URL}/${VERSION_JAVA_17}/${FILENAME_JAVA_17}"
   URL_DL_JAVA_19="${BASE_URL}/${VERSION_JAVA_19}/${FILENAME_JAVA_19}"
   URL_DL_JAVA_21="${BASE_URL}/${VERSION_JAVA_21}/${FILENAME_JAVA_21}"

   clear && sudo apt update && echo -e "\n"

   echo -e "Ensuring Java Version ${VERSION_JAVA_15} Installed"
   if ! [ -f "${PATH_BIN_JAVA_15}" ]; then
      wget --no-check-certificate -O "${PATH_FILE_JAVA_15}" "${URL_DL_JAVA_15}"
      sudo dpkg -i "${PATH_FILE_JAVA_15}"
      sudo apt install -f -y
      sudo apt --fix-broken install -y
      sudo apt autoremove -y
      rm "${PATH_FILE_JAVA_15}"
      echo -e "Installing Java Version ${VERSION_JAVA_15} - Done\n"
   else
      echo -e "Java Version ${VERSION_JAVA_15} Has Been Installed\n"
   fi

   echo -e "Ensuring Java Version ${VERSION_JAVA_11} Installed"
   if ! [ -f "${PATH_BIN_JAVA_11}" ]; then
      echo -e "Installing Java Version ${VERSION_JAVA_11}"
      wget --no-check-certificate -O "${PATH_FILE_JAVA_11}" "${URL_DL_JAVA_11}"
      sudo dpkg -i "${PATH_FILE_JAVA_11}"
      sudo apt install -f -y
      sudo apt --fix-broken install -y
      sudo apt autoremove -y
      rm "${PATH_FILE_JAVA_11}"
      echo -e "Installing Java Version ${VERSION_JAVA_11} - Done\n"
   else
      echo -e "Java Version ${VERSION_JAVA_11} Has Been Installed\n"
   fi

   echo -e "Ensuring Java Version ${VERSION_JAVA_13} Installed"
   if ! [ -f "${PATH_BIN_JAVA_13}" ]; then
      wget --no-check-certificate -O "${PATH_FILE_JAVA_13}" "${URL_DL_JAVA_13}"
      sudo dpkg -i "${PATH_FILE_JAVA_13}"
      sudo apt install -f -y
      sudo apt --fix-broken install -y
      sudo apt autoremove -y
      rm "${PATH_FILE_JAVA_13}"
      echo -e "Installing Java Version ${VERSION_JAVA_13} - Done\n"
   else
      echo -e "Java Version ${VERSION_JAVA_13} Has Been Installed\n"
   fi




   echo -e "Ensuring Java Version ${VERSION_JAVA_17} Installed"
   if ! [ -f "${PATH_BIN_JAVA_17}" ]; then
      wget --no-check-certificate -O "${PATH_FILE_JAVA_17}" "${URL_DL_JAVA_17}"
      sudo dpkg -i "${PATH_FILE_JAVA_17}"
      sudo apt install -f -y
      sudo apt --fix-broken install -y
      sudo apt autoremove -y
      rm "${PATH_FILE_JAVA_17}"
      echo -e "Installing Java Version ${VERSION_JAVA_17} - Done\n"
   else
      echo -e "Java Version ${VERSION_JAVA_17} Has Been Installed\n"
   fi

   echo -e "Ensuring Java Version ${VERSION_JAVA_19} Installed"
   if ! [ -f "${PATH_BIN_JAVA_19}" ]; then
      wget --no-check-certificate -O "${PATH_FILE_JAVA_19}" "${URL_DL_JAVA_19}"
      sudo dpkg -i "${PATH_FILE_JAVA_19}"
      sudo apt install -f -y
      sudo apt --fix-broken install -y
      sudo apt autoremove -y
      rm "${PATH_FILE_JAVA_19}"
      echo -e "Installing Java Version ${VERSION_JAVA_19} - Done\n"
   else
      echo -e "Java Version ${VERSION_JAVA_19} Has Been Installed\n"
   fi

   echo -e "Ensuring Java Version ${VERSION_JAVA_21} Installed"
   if ! [ -f "${PATH_BIN_JAVA_21}" ]; then
      wget --no-check-certificate -O "${PATH_FILE_JAVA_21}" "${URL_DL_JAVA_21}"
      sudo dpkg -i "${PATH_FILE_JAVA_21}"
      sudo apt install -f -y
      sudo apt --fix-broken install -y
      sudo apt autoremove -y
      rm "${PATH_FILE_JAVA_21}"
      echo -e "Installing Java Version ${VERSION_JAVA_21} - Done\n"
   else
      echo -e "Java Version ${VERSION_JAVA_21} Has Been Installed\n"
   fi
}

test_reader(){
   #download_java
   clear
   while true; do
      echo "Pilih lokasi Gate:"
      echo "1. Backoffice"
      echo "2. LSG"
      echo "3. PM"
      echo "4. PK"
      read -p "Masukkan pilihan (1/2/3/4): " PILIHAN

      case "$PILIHAN" in
      1) NEW_ID=1; break ;;
      2) NEW_ID=2; break ;;
      3) NEW_ID=3; break ;;
      4) NEW_ID=9; break ;;
      *) echo "Pilihan tidak valid. Silakan pilih 1, 2, 3, atau 4." ;;
      esac
   done

   sudo sed -i "s|^locationGateId=.*|locationGateId=${NEW_ID}|" /opt/app/agent/parkee-agent/temporary.temp
   echo -e "\nCheck All File for Parkee Agent"
   sudo killall -9 java

   if ! [ -p /opt/app/agent/parkee-agent ]; then
      sudo mkdir -p /opt/app/agent/parkee-agent
      sudo update-alternatives --set java /usr/lib/jvm/bellsoft-java15-full-amd64/bin/java
   fi

   #if [ -f "/opt/app/agent/parkee-agent/temporary.temp" ];then
   #   sudo rm -r /opt/app/agent/parkee-agent/temporary.temp
   #fi

   if [ ! -f "/opt/app/agent/parkee-agent/device.properties" ]; then
      tee ~/Music/device.properties<<EOF
camera.password=
reader.port=/dev/ttyUSB0
booster.connection=serial
tito=true
camera.timeout=3
wuzz.reader.standby.mode=STANDBY_MODE_READER
manless.entry.ui=new
use.gstreamer=true
reader.retry=0
printer.font.a.length=48
dispenser.timeout=2000
printer.font.b.length=64
printer.font.c.length=33
payment.method.membership.backoffice=cash
printer.connection=usb
face.base.camera.url=rtspt://CAMERA_ADMIN:CAMERA_PASSWORD@CAMERA_URL:CAMERA_PORTCAMERA_DIRECTORY
keyboard.barcode.manless=true
prevent.close.apps=active
qrcode.image.width=250
barcode.debounce=0
face.camera.url=192.168.0.40
barcode.image.width=475
rfid.mode=cycle
booster.heartbeat=offline
qrcode.image.height=250
sti.timeout=-1
reader.type.02=
camera.port=554
screen.min.width=960
camera.url=192.168.0.39
camera.directory=/live/0/MAIN
use.video=true
gate.threshold=2
mock.main.exit.dispenser=
face.camera.directory=/live/0/MAIN
use.face.camera.stream=false
sti.uart=16550A
printer.type=epson
gate.timeout=1
suggestion.mode=false
reader.port.type=serial
dds.type=none
reader.trim.response=true
face.camera.port=554
timeout.reset.unsupported.card=30
face.camera.admin=admin
sound.volume=100.0
face.camera.snapshot=/Snapshot/1/RemoteImageCapture?ImageFormat=2
lpr.type=none
reader.error.retry.delay=5000
booster.type=keyboard
screen.min.height=691
multi.reader=false
face.camera.password=
barcodereader.type=honeywell
use.vehicle.camera.stream=false
barcode.orientation=Horizontal_Default
dds.connection=serial
dds.port=
sti.reader.thread.sleep=500
reader.port.02=
reader.connection=serial
reader.port.type.02=
button=touchless
printer.tech=thermal
manless.exit.ui=new
barcode.serial.width=2
reader.type=coherent
barcode.serial.height=100
camera.snapshot=/Snapshot/1/RemoteImageCapture?ImageFormat=2
camera.serial=
face.camera.serial=
camera.admin=admin
barcode.justification=Center_Default
booster.port.double.loop=
reader.check.balance.standby.timeout=2
barcodereader.connection=serial
camera.type=ipcam
coupon.external.mock.mode=false
online.payment.mock.qiqo.mode=false
printer.port=
timeout.reset.smartcard.number.finished.transaction=15
base.camera.url=rtspt://CAMERA_ADMIN:CAMERA_PASSWORD@CAMERA_URL:CAMERA_PORTCAMERA_DIRECTORY
prevent.close.apps.manless=active
reader.environment=production
dispenser.version=v2
suggestion.debounce=500
barcode.image.height=100
gate=accesspro
face.camera.type=dummy
reader.check.balance.standby.mode=false
booster.port=
booster.timeout=10
qrcode.serial.size=10
mode.reset.on.vehicle=true
EOF
   sudo mv ~/Music/device.properties /opt/app/agent/parkee-agent/device.properties

   fi

   if [ ! -f "/opt/app/agent/parkee-agent/server.properties" ]; then
      tee ~/Music/server.properties<<EOF
serverHost=${AGENT_SERVER_HOST}
dbHost=${AGENT_SERVER_HOST}
dbPort=5432
db=${AGENT_DB_NAME}
connectionTimeout=20000
wsHost=${AGENT_SERVER_HOST}
wsPort=9005
kafkaHost=${AGENT_SERVER_HOST}
kafkaPort=9092
cache.client.impl=redis
redisHost=${AGENT_SERVER_HOST}
redisPort=6379
redisTimeout=2000
redisConnectTimeout=20000
redisOperationTimeout=20000
redisMaxConnection=25000
redisIdleConnection=
ftp.host=${FTP_HOST}
ftp.username=${FTP_USERNAME}
ftp.password=${SUPPORT_SSH_PASS}${AGENT_DB_SUFFIX}
ftp.dir=/home/parkee/Desktop/parkee/settlement/Request
local.dir=/Users/parkee/Downloads
minio.endpoint=http://${AGENT_SERVER_HOST}:9000
minio.accesskey=minioadmin
minio.secretkey=minioadmin
leakDetectionThreshold=12000
maximumPoolSize=3
minio.writeTimeout=20000
minio.readTimeout=20000
minio.connectTimeout=20000
fisherman.host=${AGENT_SERVER_HOST}
fisherman.port=8888
qiqo.password=${QIQO_PASSWORD}
qiqo.salt=${QIQO_SALT}
membership.card.mode=parkee
membership.card.mode.support.custom=parkee
normalize.membership.mode=off
redis.pubsub.mode=on
redis.mode=on
redis.lpr=true
redis.retry=30
environment=staging
redis.sync.mode=true
lpr.receiver=redis
parkee.payment.mode=kafka
maintenance.mode=false
credential.information=${CREDENTIAL_INFO}
EOF
   sudo mv ~/Music/server.properties /opt/app/agent/parkee-agent/server.properties
   fi

   if ! sudo sshpass -p "${SUPPORT_SSH_PASS}${AGENT_DB_SUFFIX}" rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no" support@${AGENT_SERVER_HOST}:/mnt/shared/{production/parkee-agent-production.jar,dependencies,sound} /opt/app/agent/parkee-agent/; then
      sudo sshpass -p "${SUPPORT_SSH_PASS}${AGENT_DB_SUFFIX}" rsync -avz --progress -e "ssh -p ${AGENT_SSH_PORT_ALT} -o StrictHostKeyChecking=no" support@${AGENT_SERVER_HOST}:/mnt/shared/{production/parkee-agent-production.jar,dependencies,sound} /opt/app/agent/parkee-agent/
   fi

   echo -e "Check All File for Parkee Agent - Done\n"
   echo -e "Ready For Launch"
   cd /opt/app/agent/parkee-agent/
   sudo /usr/lib/jvm/bellsoft-java15-full-amd64/bin/java -jar /opt/app/agent/parkee-agent/parkee-agent-production.jar
   cd "$HOME"

   clear
}

setup_file(){
   sudo apt update && sudo apt install sshpass -y
   if ! [ -d $DIR_FILE_READER ]; then
      mkdir -p ${DIR_FILE_READER}
   fi

   #download_java

   if ! [ -f "${DIR_FILE_READER}/Setup.zip" ]; then
      wget -O "${DIR_FILE_READER}/Setup.zip" "https://drive.usercontent.google.com/u/0/uc?id=1U88OXXPeMRSm0EsaAxcFZd9Y2autXogG&export=download"
      unzip "${DIR_FILE_READER}/Setup.zip" -d "${DIR_FILE_READER}"
   fi
}

clear
while true; do
	echo -e "====================================================="
	echo -e "==============SETUP READER PARKEE================"
	echo -e "====================================================="
	echo -e "0. Bypass SSH Reader"
	echo -e "1. Inject Reader Kosongan V14"
	echo -e "2. Inject Reader Kosongan V17"
	echo -e "3. Inject Reader Kosongan V19"
	echo -e "4. Reboot Reader"
	echo -e "5. Config New PSAM"
	echo -e "6. Cek Config New PSAM"
	echo -e "7. Parkee Agent"
	echo -e "8. Download File Setup & Java"
	echo -e "9. Keluar"
	echo -e "====================================================="
	read -p "INPUT pilihan (0-9): " pilihan

	case $pilihan in
	0) bypass_reader ;;
	1) new_reader_v14 ;;
	2) new_reader_v17 ;;
	3) new_reader_v19 ;;
	4) reboot_reader ;;
	5) config_PSAM ;;
	6) cek_config_PSAM ;;
	7) test_reader;;
	8) setup_file ;;
	9) echo -e "👋 Keluar..."; sleep 1; clear; exit ;;
	*) echo -e "❌ Pilihan tidak valid!";;
	esac
done
