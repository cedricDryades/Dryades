#! /bin/bash
#####################################################################################
### Script de sauvegarde par CcK <cck@dryades.org>                                ###
### Copyleft www.dryades.org                                                      ###
### Version 0.5 Alpha 											                  ###
### 															                  ###
### Script de sauvegarde par rsync                                                ###
### il faut etre capable de faire du ssh sans pass entre les deux machines        ###
### Les backups sont des dirs rsyncés pour limiter la bp, puis un tar distant     ###
#####################################################################################

### TODO
# fonctions avec retours d'erreur
# gestion des erreurs autre que rsync
# envoi du mail conditioné aux erreurs trouvées
# le log est un peu flou, a eclaircir ;)
# Gerer les fichiers d'archives
# Gerer les backup horaires ?
# Verification si dossiers sont bons
# Archive locale en option ?

### Nom du repertoires qui contiendra toute les sauvegardes sur la cible
backupdirprefix='nom_de_ma_machine'

### Repertoires sources
webdir='/home/www/'
maildir='/var/spool/mail/virtual/'
sqldir='/var/lib/mysql/'

### Exclusions de sites web selon contexte (space separated)
exclude_web='blog/ video/ '

#Utilisateur mysql Realisant les dumps
#Droit requis : SELECT global, LOCK TABLES
sqluser='root'
sqlpass='root_password'
sqlsock='/var/run/mysql/mysql.sock'

### Machine distante de sauvegarde (besoin de ssh sans pass entre elles)
ordibackup='IP'
compteordi='root'
port='22'

# Le reste
# --acls Pour gerer les acls (ne semble pas fonctionner pour cette version)
# --xattrs Pour les attributs etendus (ne semble pas fonctionner pour cette version)
# --stats Pas utile mais toujours fun ;)
rsync_opts='-avz --delete --delete-excluded --bwlimit=60'
# Pourcentage minimum d'espace libre sur le disque distant, sinon on quitte
minSize='5'
# Email ou on envoi les problemes / rapports
email='email_admin'

distantbackupdir='/home/backup/' 
# Fichier de log ( a voir )
logfile='/var/log/backup.log'















################################################################################################################################################
# Fin de la configuration. Ne rien editer ci dessous a moins de savoir le faire ;)
################################################################################################################################################







# Fichier temporaire du rapport
resume='/tmp/backup.log'


### Fonction à lancer apres chaque rsync pour verifier que cela a bien fonctionné
# en param, passer le message a afficher/logguer/mailer !
checkFailure(){
	if [ $? -gt 0 ] ; then
			echo 'Erreur dans le script de backup: '$1 >> $resume
			# logger -i -f $logfile -p kern.crit -t 'Backup' 'Backup impossible, Manque de place sur le serveur distant! ('$HOSTNAME' '$jour'/'$mois'/'$annee')'
			mail -s 'Backup de '$HOSTNAME' impossible ('$jour'/'$mois'/'$annee')' $email < $resume	
			endBackup
	fi
}

### Verification de l'espace disque restant, s'il reste moins d'un certain pourcentage, on arrete le backup et previens l'admin
spaceLeft(){
	distant_space=$(ssh $compteordi@$ordibackup -p $port df $distantbackupdir | grep '/dev')
	distant_space_available=$(echo $distant_space | cut -f 4 -d ' ')
	distant_total_space=$(echo $distant_space | cut -f 2 -d ' ')
	
	((reserved_size=$distant_total_space*$minSize/100 ))
	# echo 'reserved '$reserved_size' left '$distant_space_available
	if [ "$reserved_size" -gt "$distant_space_available" ] ; then
		echo 'Manque de place sur le serveur distant ('$minSize'%): '$distant_space_available'Ko Disponibles sur '$reserved_size'Ko Minimum' >> $resume
		logger -i -f $logfile -p kern.crit -t 'Backup' 'Backup impossible, Manque de place sur le serveur distant! ('$HOSTNAME' '$jour'/'$mois'/'$annee')'
		mail -s 'Backup de '$HOSTNAME' impossible ('$jour'/'$mois'/'$annee')' $email < $resume
		exit
	# else
		# echo 'plus de 5% restant!'
	fi
	# echo 'taille de la sauvegarde '$update_size' taille restante '$distant_space_available' sur '$distant_total_space
}

### Verification s'il y a assez de place pour faire la sauvegarde
checkSize(){
	# exemple de recuperation de la taille en dry run a passer a la fonction:
	# foo=$(rsync -n $rsync_opts -e "ssh -p $port" $excludes $webdir $compteordi@$ordibackup:${distantbackupdir}'web/' | grep 'sent ' | cut -f 2 -d ' ')

	# Comme le dry run nous renvoi des bytes, on convertit
	update_size=$[$1/1024]
	# echo 'update de '$update_size'Ko'
	distant_space=$(ssh $compteordi@$ordibackup -p $port df $distantbackupdir | grep '/dev')
	distant_space_available=$(echo $distant_space | cut -f 4 -d ' ')
	distant_total_space=$(echo $distant_space | cut -f 2 -d ' ')
	
	# distant_total_space=2456950
	((space_left=$distant_space_available-$update_size))
	((reserved_size=$distant_total_space*$minSize/100 ))
	# echo 'reserved '$reserved_size' left '$space_left
	if [ "$reserved_size" -gt "$space_left" ] ; then
		echo 'Manque de place sur le serveur distant, la sauvegarde ('$update_size'Ko) empietterait sur la reserve ('$minSize'%): '$distant_space_available'Ko Disponibles sur '$reserved_size'Ko Minimum' >> $resume
		logger -i -f $logfile -p kern.crit -t 'Backup' 'Backup impossible, Manque de place sur le serveur distant! ('$HOSTNAME' '$jour'/'$mois'/'$annee')'
		mail -s 'Backup de '$HOSTNAME' impossible ('$jour'/'$mois'/'$annee')' $email < $resume	
		exit
	# else
	# 	echo 'plus de 5% restant!'
	fi
	# echo 'taille de la sauvegarde '$update_size' taille restante '$distant_space_available' sur '$distant_total_space
	# echo $resume
	# exit
}








#########################################################
### Début: creation rapport, verif root et spaceleft  ###
#########################################################


heure=$(date +%H)
minute=$(date +%M)
jour=$(date +%d)
mois=$(date +%m)
annee=$(date +%Y)

# On commence par verifier qu'on est bien root
if [ "$(id -u)" != "0" ]; then
	echo 'Doit être root pour pouvoir fonctionner!'
	logger -i -f $logfile -p kern.crit -t 'Backup' 'Backup impossible, il faut etre root! ('$HOSTNAME' '$jour'/'$mois'/'$annee')'
	endBackup
fi

### Debut du rapport
echo '' > $resume 
echo '' >> $resume
echo ' -------------------------------------------------------------------' >> $resume
echo ' Backup de '$HOSTNAME' | ' $jour'/'$mois'/'$annee 'a' $heure'h'$minute >> $resume
echo '-------------------------------------------------------------------' >> $resume
echo '' >> $resume
echo '' >> $resume


# Verification que le disque distant n'est pas saturé
spaceLeft

#############################
### Backup des sites Web  ###
#############################

### Log
echo '' >> $resume
echo '##### Backup des sites web' >> $resume
echo '' >> $resume

### Definition des exclusions selon ce qui a été donné en config ( plus haut )
# excludes="--exclude-from='"$exclude_web"'"
excludes=""
for exclusions in $exclude_web; do
	excludes="$excludes --exclude $exclusions"
done

# Verification que la sauvegarde n'empiette pas sur l'espace disque reserve
foo=$(rsync -n $rsync_opts -e "ssh -p $port" $excludes $webdir $compteordi@$ordibackup:${distantbackupdir}'web/' | grep 'sent ' | cut -f 2 -d ' ')
checkSize foo

### Rsync du repertoire sur la machine distante
rsync $rsync_opts -e "ssh -p $port" $excludes $webdir $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/web/' >> $resume
checkFailure 'Backup Web'

### creation de l'archive
# ssh $compteordi@$ordibackup -p $port tar -cjf ${distantbackupdir}'archives/'$jour'_'$mois'_web.tar.bz2' ${distantbackupdir}'web/' >> $resume

##############################
### Sauvegarde  Mysql Dump ###
##############################

### Log
echo '' >> $resume
echo '##### Backup des bases mysql' >> $resume
echo '' >> $resume

# On définit un nom temporaire utilisé par le script (ici la date jusqu'à la minute)
# dirname="dump_`date +%d`.`date +%m`.`date +%y`@`date +%H`h`date +%M`"
dirname='sqldump_'$jour'_'$mois'_'$heure'H'$minute
# On crée sur le disque un répertoire temporaire (changer le chemin précédant /$dirname)
mkdir '/tmp/'$dirname

# On place dans un tableau le nom de toutes les bases de données du serveur
# On peut choisir ici d'exclure certaines bases de données de la sauvegarde grâce à la clause LIKE
# Ex : -e "show databases LIKE 'dryades_%'"

# DBS="$($sqldir -u root -p$DBPASS -Bse 'show databases')"
# for DBNAME in $DBS
# do
# mysqldump --opt -u root -p$DBPASS $DBNAME > $BACKUPDIR/$DATEFORMAT-$DBNAME.sql
# echo "Base de données $DBNAME sauvegardée"
# done

# 
databases="$(mysql -S $sqlsock --user=$sqluser --password=$sqlpass -Bse 'SHOW DATABASES;' | grep -v Database)"

# Pour chacune des bases de données trouvées ...
for db in ${databases[@]}
do
	# echo $db
	#... on crée dans le dossier temporaire un dossier portant le nom de la base
	mkdir "/tmp/${dirname}/${db}"
	#... on récupère chacune des tables de cette base de données dans un tableau ...
	tables="$(mysql -S $sqlsock $db --user=$sqluser --password=$sqlpass -e 'SHOW TABLES;' | grep -v Tables_in)"
	#... et on parcourt chacune de ces tables ...
	for table in ${tables[@]}
	do
		#... que l'on dump avec mysqldump dans un fichier portant le nom de la table dans le dossier de la bdd parcourue
		mysqldump -S $sqlsock --user=$sqluser --password=$sqlpass --quick --add-locks --lock-tables --extended-insert $db $table > /tmp/${dirname}/${db}/${table}.sql
	done
done

### Sauvegarde du dump sql
rsync $rsync_opts -e "ssh -p $port" "/tmp/${dirname}/" $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/sql/' >> $resume
checkFailure 'Backup Sql'

### creation de l'archive
# tar -cjf "/tmp/${jour}_${mois}_sqldump.tar.bz2" "/tmp/${dirname}/"
# # Envoi de l'archive
# rsync $rsync_opts -e "ssh -p $port" "/tmp/"$jour"_"$mois"_sqldump.tar.bz2" "$compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/sql/'" >> $resume
# # On supprime le répertoire temporaire
# rm -rf "/tmp/${dirname}/"
# # On supprime l'archive locale
# rm -rf "/tmp/${jour}_${mois}_sqldump.tar.bz2"


#################################
### Backup des Mysql Binaire  ###
#################################

# Mise en attente des requettes sur la base
mysql -S $sqlsock --user=$sqluser --password=$sqlpass -Bse 'FLUSH TABLES WITH READ LOCK;'

# Verification que la sauvegarde n'empiette pas sur l'espace disque reserve
foo=$(rsync -n $rsync_opts -e "ssh -p $port" $sqldir $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/sqlbin/' | grep 'sent ' | cut -f 2 -d ' ')
checkSize foo

# Sauvegarde binaire des bases de données
rsync $rsync_opts -e "ssh -p $port" $sqldir $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/sqlbin/' >> $resume
checkFailure 'Backup SqlBin'

# On libere les tables de mysql
mysql -S $sqlsock --user=$sqluser --password=$sqlpass -Bse 'UNLOCK TABLES;'

##########################
### Backup des eMails  ###
##########################


### Log
echo '' >> $resume
echo '##### Backup des emails' >> $resume
echo '' >> $resume

# Verification que la sauvegarde n'empiette pas sur l'espace disque reserve
foo=$(rsync -n $rsync_opts -e "ssh -p $port" $maildir $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/mail/' | grep 'sent ' | cut -f 2 -d ' ')
checkSize foo

### Rsync du repertoire sur la machine distante
rsync $rsync_opts -e "ssh -p $port" $maildir $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/mail/' >> $resume
checkFailure 'Backup Mail'


### creation de l'archive
# ssh $compteordi@$ordibackup -p $port tar -cjf ${distantbackupdir}$jour"_"$mois"_mail.tar.bz2 "${distantbackupdir}'mail/' >> /dev/null >> $resume

###################################
### Backup des fichiers de conf ###
###################################

### Log
echo '' >> $resume
echo '##### Backup des fichiers systeme' >> $resume
echo '' >> $resume

# Mode "mirroir sans suppression"	
rsync $rsync_opts -e "ssh -p $port" /etc/ $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/sys/etc/' >> $resume
checkFailure 'Backup Etc'
rsync $rsync_opts -e "ssh -p $port" /usr/local/apache2/conf/ $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/sys/apache2conf/' >> $resume
checkFailure 'Backup apacheConf'
rsync $rsync_opts -e "ssh -p $port" /root/lilylove/ $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/sys/lilylove/' >> $resume
checkFailure 'Backup scriptLilyLove'
rsync $rsync_opts -e "ssh -p $port" /usr/src/linux/.config $compteordi@$ordibackup:${distantbackupdir}${backupdirprefix}'/sys/' >> $resume
checkFailure 'Backup noyal'

### pas d'archive locale
### creation de l'archive distante
# ssh $compteordi@$ordibackup -p $port tar -cjf ${distantbackupdir}'archives/'$jour'_'$mois'_sys.tar.bz2' ${distantbackupdir}'sys/' >> $resume

###################################################
### Suppressions des archives de plus de 7 jours ###
####################################################

# ssh $compteordi@$ordibackup -p 222 'find /var/log/backup/archives -atime 7 -name \*'$nom_tar'.tar -exec rm -f {} \;' >> $resume
### local
# find $localbackupdir -atime 7 -name \*.tar.bz2 -exec rm -f {} \; >> $resume
### distant
# ssh $compteordi@$ordibackup -p $port 'find '$distantbackupdir' -atime 7 -name \*.tar.bz2 -exec rm -f {} \;' >> $resume


#########################################
### Log, mail, suppression du rapport ###
#########################################

### Fin du log
echo '' >> $resume
echo '' >> $resume
echo '-------------------------------------------------------------------' >> $resume
echo 'Backup de '$HOSTNAME' Termine. Temps requis: '$SECONDS' secondes.' >> $resume
echo '-------------------------------------------------------------------' >> $resume
echo '' >> $resume

### Log sur la machine
logger -i -f $logfile -p kern.crit -t 'Backup de '$HOSTNAME' du '$jour'/'$mois'/'$annee' Termine. Temps requis: '$SECONDS' secondes.'
### On copie le resume dans un fichier de log (hum taille qui grossiera indefiniement)
# echo $resume >> $logfile 
### Envoi du mail
mail -s 'Backup de '$HOSTNAME' ('$jour'/'$mois'/'$annee')' $email < $resume
# Supression du rapport temporaire
rm $resume
exit 0
































# Creer un fichier unique dans /tmp ( a verif ceci dit )
# PREFIXE=backup
# resume=`mktemp $PREFIXE.XXXXXX`


# Sauvegarde par ftp trouvee sur le net, pourquoi ne pas rajouter l'option rsyc ou ftp ?
# ### Dump backup using FTP ###
# #Start FTP backup using ncftp
# ncftp -u"$FTPU" -p"$FTPP" $FTPS<
# mkdir $FTPD
# mkdir $FTPD/$NOW
# cd $FTPD/$NOW
# lcd $BACKUP
# mput *
# quit
# EOF
# ### Find out if ftp backup failed or not ###
# if [ "$?" == "0" ]; then
# rm -f $BACKUP/*
# else
# T=/tmp/backup.fail
# echo "Date: $(date)">$T
# echo "Hostname: $(hostname)" >>$T
# echo "Backup failed" >>$T
# mail -s "BACKUP FAILED" "$EMAILID" <$T
# rm -f $T
# fi


# some error handling and/or run our backup and accounting
# if [ -f $EXCLUDES ]; then
# if [ -d $BACKUPDIR ]; then
#   # now the actual transfer
#   make_free_space && do_rsync && do_accounting
# else
#   echo "cant find $BACKUPDIR"; exit
# fi
# else
#   echo "cant find $EXCLUDES"; exit
# fi


# if test -d $DST/today ; then
#     # Et si le fichier contenant la date de la dernière sauvegarde existe
#     if test -f $DST/last_date ; then
#     
#         LASTDATE=`cat $DST/last_date`
#         # Alors on fait un copie en hardlinks de la sauvegarde d'hier
#         cp -al $DST/today $DST/tmp/
#         # Puis on renomme la copie pour qu'elle devienne la sauvegarde d'hier
#         mv $DST/tmp/today $DST/$LASTDATE
#         
#     fi
#     
# # Sinon, on crée le premier dossier
# else
#     mkdir $DST/today
# fi

# verif si pas de prob
# if [[ $# -gt "0" ]]; then
# 	echo 'OOOOOOOOOOOOOOOOOOps '$#
# else 
# 	echo 'tout va bien '$#
# fi;


# # REMOVE OLD BACKUPS
# for FILE in "$( $FIND $OLD -maxdepth 1 -type d -mtime +$DAYS )"
# do
# #	$RM -Rf $FILE
# #   $ECHO $FILE
# done
# exit 0