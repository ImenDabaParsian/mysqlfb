#!/bin/env bash

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
	    echo "Subject: Backup report - Git"
	    echo -e $content
	    echo "."
	    sleep 5
	    echo quit
	) | telnet
	flag=false
	if [ $? -eq 0 ]; then
	    echo "We have some problem in sending email via telnet." > backup.log
	    echo -e $emailcontent >> backup.log
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

# newbackup="netband-$server-$data.sql"
# oldbackup='netband-$server-$(data --date="yesterday" +"%F").sql'
emailcontent=""

# create backup directory:
if [ ! -d $backup_dir ]; then
    res=$($mkdir $backup_dir)
    if [ $? -ne 0 ]; then
	emailcontent=$emailcontent"We have a problem in creating backup directory. (Error Massage: "$res").\n"
	# sendmail "$(echo $emailcontent)" "netband ("$server") backup failed."
    fi
fi

# dumping databases in four different files:
for edatabase in $(OLDIFS=$IFS; IFS=","; echo $database; IFS=$OLDIFS); do
    # First file is DB schematic:
    res=$($mysqldump --user=$username --password=$password --databases $edatabase --no-data --skip-triggers --result-file=$backup_dir/$database-schema-$date.sql 2>&1)
    if [ $? -ne 0 ]; then
	emailcontent=$emailcontent"We have a problem in dumping "$edatabase" schematic. (Error Message= "$res").\n"
    else
	emailcontent=$emailcontent$edatabase" schematic dumped successfully.\n"
    fi
    # Second file is DB data:
    res=$($mysqldump --user=$username --password=$password --databases $edatabase --no-create-info --skip-triggers --result-file=$backup_dir/$database-data-$date.sql 2>&1)
    if [ $? -ne 0 ]; then
	emailcontent=$emailcontent"We have a problem in dumping "$edatabase" data. (Error Message= "$res").\n"
	# sendmail "$(echo $emailcontent)" "netband ("$server") backup failed."
    else
	emailcontent=$emailcontent$edatabase" data dumped successfully.\n"
    fi
    # third file is DB triggers:
    res=$($mysqldump --user=$username --password=$password --databases $edatabase --no-create-info --no-data --triggers --result-file=$backup_dir/$database-triggers-$date.sql 2>&1)
    if [ $? -ne 0 ]; then
	emailcontent=$emailcontent"We have a problem in dumping "$edatabase" triggers. (Error Message= "$res").\n"
    else
	emailcontent=$emailcontent$edatabase" triggers dumped successfully.\n"
    fi
    # frouth file is All of DB without trigggers:
    res=$($mysqldump --user=$username --password=$password --databases $edatabase --skip-triggers --result-file=$backup_dir/$database-$date.sql 2>&1)
    if [ $? -ne 0 ]; then
	emailcontent=$emailcontent"We have a problem in dumping "$edatabase". (Error Message= "$res").\n"
    else
	emailcontent=$emailcontent$edatabase" dumped in all-in-one file successfully.\n"
    fi
done

# capture binary log file:
res=$($tar --create --absolute-name --gzip --file $backup_dir/binary-logs-$date.tar.gz /var/log/mysql/* 2>&1)
if [ $? -ne 0 ]; then
    emailcontent=$emailcontent"We have a problem in caputring binary log files. (Error Message= "$res")\n"
    # sendmail "$(echo $emailcontent)" "netband ("$server") backup failed."
else
    emailcontent=$emailcontent"Mysql binary log files successfully backed up in compressed tar archive.\n"
fi

# capture config files:
res=$($tar --create --absolute-name --gzip --file $backup_dir/config-files-$date.tar.gz /etc/mysql 2>&1)
if [ $? -ne 0 ]; then
    emailcontent=$emailcontent"We have a problem in backing up mysql config files. (Error Message= "$res")\n"
else
    emailcontent=$emailcontent"Mysql config files successfull backed up.\n"
fi

# dump mysql database for backing up users and privileges:
res=$($mysqldump --user=$username --password=$password --databases mysql --skip-triggers --result-file=$backup_dir/$database-privileges-$date.sql 2>&1)
if [ $? -ne 0 ]; then
    emailcontent=$emailcontent"We have a problem in dumping mysql database. (Error Message= "$res")\n"
else
    emailcontent=$emailcontent"User and Privileges backed up successfully.\n"
fi

#create remote directory for today files:
res=$($ssh -i key.pri back@172.18.0.3 /bin/mkdir -p /home/backup/$rbackup_dir/$date)
if [ $? -ne 0 ]; then
    emailcontent=$emailcontent"We have a problem in creteing today backup directory on backup server.\n"
else
    emailcontent=$emailcontent"Today backup directory created successfully.\n"
fi

# # create remote backup directory:
# res=$($ssh -i key.pri back@172.18.0.3 mkdir -p $rbackup_dir/$date )
# if [ $? -ne 0 ]; then
#     emailcontent=$emailcontent"We have a problem in creating today backup directory. (Error Massage: "$res").\n"
# else
#     emailcontent=$emailcontent"Today remote backup directory successfully created.\n"
# fi

# transfer backup files to backup disk
for efile in $(ls -1 $backup_dir); do
    echo "fileee: " $efile
    echo $backup_dir/$efile
    res=$($scp -i key.pri $backup_dir/$efile back@172.18.0.3:~/$rbackup_dir/$date 2>&1)
    if [ $? -ne 0 ]; then
	emailcontent=$emailcontent"We have a problem in copying "$efile" to backup disk. (Error Message: "$res").\n"
    else
	emailcontent=$emailcontent$efile" copyed successfully.\n"
	# compare files MD5 checksum and remove new files from server and od files from backup server if result of compare is OK
	local_file_md5=$($md5sum $backup_dir/$efile | cut -d" " -f1 2>&1)
	echo "local file md5*******: " $local_file_md5
	remote_file_md5=$($ssh -i key.pri back@172.18.0.3 /usr/bin/md5sum /home/backup/$rbackup_dir/$date/$efile | cut -d" " -f1 2>&1)
	echo "remote file md5: " $remote_file_md5
	if [[ $local_file_md5 == $remote_file_md5 ]]; then
	    emailcontent=$emailcontent$efile" backup file correctly transfered.\n"
	    rm $backup_dir/$efile
	    emailcontent=$emailcontent$efile" local backup file deleted from server.\n"
	else
	    emailcontent=$emailcontent "An error occur in transfering" $efile "backup file to backup server and the file on the server is crroupted\n"
	fi    
    fi
done

echo "========= emailcontent before send function:"$emailcontent

# send backup report via email:
sendmail "$(echo -e $emialcontent)" "$(echo Subject: Backup From "$host" mysql service - "$database" database[s])" 

# dump database
# res=$(/usr/bin/mysqldump --user=$user --password=$password --databases $database --result-file=~/$newbackup 2>&1)
# if [ $? -eq 0 ]; then
#     emailcontent=$emailcontent" database successfully dumped."
#     # transfer to backup machine
#     scp ~/$newbackup daba@172.18.0.32:~/backup/netband/database
#     if [ $? -eq 0 ]; then
# 	emailcontent=$emailcontent" backup file successfully transferd."
# 	# check files md5 check sum and remove backup file if it's same:
# 	remote_file=$(ssh daba@172.18.0.32 md5sum ~/backup/netband/database/$newbackup | awk '{print $1}')
# 	source_file=$(md5sum ~/$newbackup | awk '{print $1}')
# 	if [[ $remote_file == $source_file ]];  then
# 	    rm ~/$newbackup
# 	    ssh daba@172.18.0.32 rm ~/backup/netband/database/$oldbackup
# 	    emailcontent=$emailcontent" old backup file and temporary backupfile successfully removed."
# 	else
# 	    emailcontent=$emailcontent" We have a problem in checking MD5 hash or removing old files."
# 	    sendmail "$(echo $emailcontent)" "netband ("$server") backup failed"
# 	fi
#     else
# 	emailcontent=$emailcontent" We have a problem in transfering backed up file to backup machine."
# 	sendmail "$(echo $emailcontent)" "netband ("$server") backup failed"
#     fi
# else
#     emailcontent=$emailcontent" We have a problem in dumping mysql. (Error Message = "$res")"
#     sendmail "$(echo $emailcontent)" "netband ("$server") backup failed"
# fi

# # send report
# sendmail "$(echo $emailcontent)" "netband ("$server") backup successful"

