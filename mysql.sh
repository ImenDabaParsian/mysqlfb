#!/bin/bash

###########################################################################
# FileName:    mysql.sh							  #
# Description: supply mysql service backup from some different way.	  #
#              (schema, data, triggers, all-in-one), configs, binary logs #
#              and mysql usre privileges.				  #
# Version:     1.01 stabel						  #
# Feedback:    v.maani@dabacenter.ir/Vahid.Maani@gmial.com		  #
###########################################################################

# a function to email script report:
function sendmail(){
    content=$1
    subject=$2
    flag=true
    while $flag ; do
	 (
	    echo open mails.ir smtp
	    sleep 5
	    echo HELO mail.dabacenter.ir
	    sleep 5
	    echo mail from: "no-reply@dabacenter.ir"
	    sleep 5
	    echo rcpt to: "v.maani@dabacenter.ir"
	    sleep 5
	    # echo rcpt to: "heydarlou@dabacenter.ir"
	    # sleep 5
	    echo data
	    sleep 5
	    echo "Subject:" $subject
	    echo -e $content
	    echo "."
	    sleep 5
	    echo quit
	) | telnet
	flag=false
	if [ $? -ne 0 ]; then
	    echo "** We have some problem in sending email via telnet." >> /home/daba/scripts/mysql/backup.log
	    exit 1
	else
	    exit 0
	fi
    done
    exit 0
}

# parse script arguments and set default values
args=$(getopt -o h:u:p:D:r: -- "$@")
eval set -- "$args"
while true; do
    case $1 in
	-h) host=$2; shift 2;;
	-u) username=$2; shift 2;;
	-p) password=$2; shift 2;;
	-D) database=$2; shift 2;;
	-r) rbackup_dir=$2; shift 2;;
	*) shift; break;;
    esac
done
date=$(date +"%F")
backup_dir="/home/daba/tmp-backup"
tar=$(which tar)
mysqldump=$(which mysqldump)
mkdir=$(which mkdir)
scp=$(which scp)
telnet=$(which telnet)
ssh=$(which ssh)
md5sum=$(which md5sum)
script_dir=$0
echo "" > $script_dir/backup.log

# create backup directory:
if [ ! -d $backup_dir ]; then
    res=$($mkdir $backup_dir)
    if [ $? -ne 0 ]; then
	echo "** We have a problem in creating backup directory. (Error Massage: "$res")." >> $script_dir/backup.log
	# sendmail "$(echo $emailcontent)" "netband ("$server") backup failed."
    fi
fi

# dumping databases in four different files:
for edatabase in $(OLDIFS=$IFS; IFS=","; echo $database; IFS=$OLDIFS); do
    # First file is DB schematic:
    res=$($mysqldump --user=$username --password=$password --databases $edatabase --no-data --skip-triggers --result-file=$backup_dir/$edatabase-schema-$date.sql 2>&1)
    if [ $? -ne 0 ]; then
	echo "** We have a problem in dumping "$edatabase" schematic. (Error Message= "$res")." >> $script_dir/backup.log
    else
	echo $edatabase" schematic dumped successfully." >> $script_dir/backup.log
    fi
    # Second file is DB data:
    res=$($mysqldump --user=$username --password=$password --databases $edatabase --no-create-info --skip-triggers --result-file=$backup_dir/$edatabase-data-$date.sql 2>&1)
    if [ $? -ne 0 ]; then
	echo "** We have a problem in dumping "$edatabase" data. (Error Message= "$res")." >> $script_dir/backup.log
	# sendmail "$(echo $emailcontent)" "netband ("$server") backup failed."
    else
	echo $edatabase" data dumped successfully." >> $script_dir/backup.log
    fi
    # third file is DB triggers:
    res=$($mysqldump --user=$username --password=$password --databases $edatabase --no-create-info --no-data --triggers --result-file=$backup_dir/$edatabase-triggers-$date.sql 2>&1)
    if [ $? -ne 0 ]; then
	echo "** We have a problem in dumping "$edatabase" triggers. (Error Message= "$res")." >> $script_dir/backup.log
    else
	echo $edatabase" triggers dumped successfully." >> $script_dir/backup.log
    fi
    # frouth file is All of DB without trigggers:
    res=$($mysqldump --user=$username --password=$password --databases $edatabase --skip-triggers --result-file=$backup_dir/$edatabase-$date.sql 2>&1)
    if [ $? -ne 0 ]; then
	echo "** We have a problem in dumping "$edatabase". (Error Message= "$res")." >> $script_dir/backup.log
    else
	echo $edatabase" dumped in all-in-one file successfully." >> $script_dir/backup.log
    fi
done

# capture binary log file:
res=$($tar --create --absolute-name --gzip --file $backup_dir/binary-logs-$date.tar.gz /var/log/mysql/* 2>&1)
if [ $? -ne 0 ]; then
    echo "** We have a problem in caputring binary log files. (Error Message= "$res")" >> $script_dir/backup.log
    # sendmail "$(echo $emailcontent)" "netband ("$server") backup failed."
else
    echo "Mysql binary log files successfully backed up in compressed tar archive." >> $script_dir/backup.log
fi

# capture config files:
res=$($tar --create --absolute-name --gzip --file $backup_dir/config-files-$date.tar.gz /etc/mysql 2>&1)
if [ $? -ne 0 ]; then
    echo "** We have a problem in backing up mysql config files. (Error Message= "$res")" >> $script_dir/backup.log
else
    echo "Mysql config files successfull backed up." >> $script_dir/backup.log
fi

# dump mysql database for backing up users and privileges:
res=$($mysqldump --user=$username --password=$password --databases mysql --skip-triggers --result-file=$backup_dir/database-privileges-$date.sql 2>&1)
if [ $? -ne 0 ]; then
    echo "** We have a problem in dumping mysql database. (Error Message= "$res")" >> $script_dir/backup.log
else
    echo "User and Privileges backed up successfully." >> $script_dir/backup.log
fi

#create remote directory for today files:
res=$($ssh -i $script_dir/key.pri back@172.18.0.3 /bin/mkdir -p /home/backup/$rbackup_dir/$date)
if [ $? -ne 0 ]; then
    echo "** We have a problem in creteing today backup directory on backup server." >> $script_dir/backup.log
else
    echo "Today backup directory created successfully." >> $script_dir/backup.log
fi

# transfer backup files to backup disk
file_counter=0
for efile in $(ls -1 $backup_dir); do
    res=$($scp -i $script_dir/key.pri $backup_dir/$efile back@172.18.0.3:~/$rbackup_dir/$date 2>&1)
    if [ $? -ne 0 ]; then
	echo "** We have a problem in copying "$efile" to backup disk. (Error Message: "$res")." >> $script_dir/backup.log
    else
	echo $efile" copyed successfully." >> $script_dir/backup.log
	# compare files MD5 checksum and remove new files from server and od files from backup server if result of compare is OK
	local_file_md5=$($md5sum $backup_dir/$efile | cut -d" " -f1 2>&1)
	remote_file_md5=$($ssh -i $script_dir/key.pri back@172.18.0.3 /usr/bin/md5sum /home/backup/$rbackup_dir/$date/$efile | cut -d" " -f1 2>&1)
	if [[ $local_file_md5 == $remote_file_md5 ]]; then
	    echo $efile" backup file correctly transfered." >> $script_dir/backup.log
	    rm $backup_dir/$efile
	    echo $efile" local backup file deleted from server." >> $script_dir/backup.log
	    file_counter=$(expr $file_counter + 1 ) 
	else
	    echo "** An error occur in transfering" $efile "backup file to backup server and the file on the server is crroupted" >> $script_dir/backup.log
	fi
    fi
done
if [ $file_counter -eq 7 ]; then
    yesterday=$(date --date="yesterday" +"%F")
    res=$($ssh -i $script_dir/key.pri back@172.18.0.3 /bin/rm -r /home/backup/$rbackup_dir/$yesterday 2>&1)
    if [ $? -ne 0 ]; then
	echo "** We have a problem in removing old directory from backup server. (Error Massage: "$res")." >> $script_dir/backup.log
    else
	echo "Old backup directory successfully removed from backup server." >> $script_dir/backup.log
    fi
fi

# send backup report via email:
emailcontent=""
while read -r line; do
    emailcontent=$emailcontent$line"\n"
done < <(cat $script_dir/backup.log)
sendmail "$(echo $emailcontent)" "$(echo Subject: Backup From "$host" mysql service - "$database" database[s])"

exit 0
