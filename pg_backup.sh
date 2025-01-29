#!/bin/bash

# TODO !!! set pg_pass file for each cluster instance and pass it as argument

backup_type_full="full"
backup_type_inc="inc"
backup_types=($backup_type_full $backup_type_inc)

# DBMS username and group
dbms_user=postgres
dbms_group=postgres

# Help message
help() {
    echo "Usage: $0 [-e <env_file> -t <backup_type>]"
    echo "Available backup_types are: ${backup_types[@]}"
    exit 1
}

# Getting arguments
while getopts ":e:t:" opt; do
    case "$opt" in
        e) env_file="$OPTARG" ;;
        t) backup_type="$OPTARG" ;;
        *) help ;;
    esac
done

# Script arguments validation. Show help on errors
if [[ -z "$env_file" || -z "$backup_type" || ! "${backup_types[*]}" =~ $backup_type ]]; then
    help
fi

# Getting environment variables from configuration file
source $env_file

# Setting backup storage path
# Format:
# backup_storage_root/postgresql_instance_name/current_year/current_month/current_date/backup_type_full_or_inc/current_hour_minute_second
# Backup directory structure in specific cluster backup can be displayed with:
# ~~~
# cd backup_storage_root && tree postgresql_instance_name/ -d -L 5
# ~~~
# You must replace backup storage root and postgresql_instance_name with your directory names

# Getting PostgreSQL version number
pg_version="$($PGBINPATH/psql --version | grep -oP '(?<=psql \(PostgreSQL\) )\d+\.\d+' | sed 's/\./_/')"
current_date_time=$(date +%Y)_$(date +%m)_$(date +%d)_$(date +%H)_$(date +%M)_$(date +%S)


# backup_archive_path="${BACKUP_ROOT}/${PGDB}"/$(date +%Y)/$(date +%m)/$(date +%d)/$backup_type/$(date +%H)_$(date +%M)_$(date +%S)
# backup_archive_path=${BACKUP_ROOT}/${PGDB}/$(date +%Y)_$(date +%m)_$(date +%d)_$(date +%H)_$(date +%M)_$(date +%S)_${backup_type}_${PGDB}
backup_archive_path=${BACKUP_ROOT}/${PGDB}/$current_date_time/${PGDB}_pg_${pg_version}_${backup_type}_${current_date_time}
# Creating backup directory structure and setting permissions
mkdir -p $backup_archive_path
chown -R $dbms_user:$dbms_group ${BACKUP_ROOT} -R && chmod -R 755 ${BACKUP_ROOT} -R

echo "Backup ${PGDB} with ${backup_type} type started"

# Backup procedure

# Full backup
if [[ $backup_type == $backup_type_full ]]; then
    sudo -u $dbms_user $PGBINPATH/pg_basebackup -d postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT -D $backup_archive_path
fi


# Incremental backup. Find latest backup_manifest file (can be inside full or previous incremental backup dir)
if [[ $backup_type == $backup_type_inc ]]; then
    previous_backup_manifest_file="$(find ${BACKUP_ROOT}/${PGDB} -type f -name backup_manifest  -printf '%T+ %p\n'  | sort -r | head -1 | cut -f 2 -d " ")"
    
    # Validation process of backup_manifest file exists and is file
    if [[ -z "$previous_backup_manifest_file" ]]; then
        # TODO may be run full backup?
        echo "[ERROR] Previous backup_manifest file not found" >&2
        exit 1
    fi

    if [[ ! -f "$previous_backup_manifest_file" ]]; then
        # TODO may be run full backup?
        echo "[ERROR] Previous backup_manifest file does not exists $previous_backup_manifest_file" >&2
        exit 1
    fi

    echo "Валидация успешна"


    echo "[INFO] Previous backup manifest file for incremental backup is ${previous_backup_manifest_file}"
    sudo -u $dbms_user $PGBINPATH/pg_basebackup -d postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT -i $previous_backup_manifest_file -D $backup_archive_path
fi

# Backup verification procedure

# TODO verify backup
echo "Backup ${PGDB} with ${backup_type} type, stored at $backup_archive_path verification"
sudo -u $dbms_user $PGBINPATH/pg_verifybackup $backup_archive_path &> /dev/null


if [ $? -eq 0 ]; then
    echo "[SUCCESS] Backup ${PGDB} with ${backup_type} type, stored at $backup_archive_path verification complete"
else
    echo "[ERROR] Backup ${PGDB} with ${backup_type} type, stored at $backup_archive_path verification error"
    exit 1
fi
# TODO compress previous full backup and all incremental backups older than previous full

# TODO archive depth remove archives older than1


echo "Backup ${PGDB} with ${backup_type} type was stored at ${backup_archive_path}"
