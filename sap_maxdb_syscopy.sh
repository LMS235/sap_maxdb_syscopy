#!/usr/bin/bash

# SYSCOPY MaxDB AIX/LINUX################################################################################  
################################################################################ (c) 2017 Florian Lamml #

# Prerequisites #########################################################################################
# - ssh communication between source and target without password (authorized_keys2) for both sidadm     #
#   via "ssh-keygen -t rsa -b 2048" and  ".ssh/authorized_keys2" (only source --> target)               #
#   --> ssh sourceadm@sourcehost must work without PW                                                   #
#   --> ssh targetadm@targethost must work without PW                                                   #
# - the target database is large enough (automatic check)                                               #
# - copy this script to the source host and set the execution right                                     #
# - xuser DEFAULT for ABAP/JAVA DB User (SAP<SID> or SAP<SID>DB) must be available                      #
# - if passwords from source and target are different, xuser for copy can not be used                   #
# - the source database must be online, the target database must be able to start in state admin        #
# - adjust the configuration of source and target system in this script                                 #
# - best use with screen tool for unix/linux                                                            #
#########################################################################################################

# Features ##############################################################################################
# - automatic function and prerequisites check                                                          #
# - backup to 2 parallel PIPE                                                                           #
# - can use compressed and uncompressed backup (default uncompress)                                     #
# - root is not needed                                                                                  #
# - copy status bar with size, transfered, left and speed (5 second update)                             #
# - automatic size check                                                                                #
# - dd over ssh from source to target                                                                   #
# - ssh encryption default cipher is aes192-ctr                                                         #
# - automatic rename database to target                                                                 #
# - automatic export of custom tables (incl. templates of the most common)                              #
# - you can use a custom db user or xuser for backup and restore                                        #
#########################################################################################################

# Exit Codes ############################################################################################
# exit 0 = normal or user exit                                                                          #
# exit 99 = script run as root                                                                          #
# exit 98 = another script is running                                                                   #
# exit 97 = source database is not available                                                            #
# exit 96 = source database size bigger than target database max size                                   #
# exit 95 = error in backup start                                                                       #
# exit 94 = error in restore start                                                                      #
# exit 93 = error in backup                                                                             #
# exit 92 = error in restore                                                                            #
# exit 91 = error with SSH on source                                                                    #
# exit 90 = error with SSH on target                                                                    #
# exit 89 = error with temporary status files on source                                                 #
# exit 88 = error with temporary status files on target                                                 #
# exit 87 = error with pipes on source                                                                  #
# exit 86 = error with pipes on target                                                                  #
# exit 85 = error in config check                                                                       #
# exit 84 = error in target db start                                                                    #
# exit 83 = error in target backup template create                                                      #
# exit 82 = error in source backup template create                                                      #
# exit 81 = error in rename target db                                                                   #
#########################################################################################################

# Configuration start ###################################################################################
# configuration need to be adjusted
#
# source host (example: server1 or the IP)
export sourcehost=server1 
#
# target host (example: server2 or the IP)
export targethost=server2
#
# source SID (example: AAA)
export sourcesid=AAA
#
# target SID (example: BBB)
export targetsid=BBB
#
# logfile name (example/default: DB_Copy_AAAtoBBB_01011900.log)
export dbcopylog=DB_Copy_"$sourcesid"to"$targetsid"_$(date "+%d%m%Y").log
#
# send mail after syscopy (default no)
export sendfinishmail=no
export mailadress=user@domain.tld
#
#
#### Export / Import Options ####
# save sec directory with the sap certificates (default yes, saved in cdD/cdJ as syscopy_sec)
export savesecdir=yes
# define if abap or java (default abap)
export abaporjava=abap
#custom table export and imports (default is only e070l and sap license, yes or no)
# Export location on target (default /tmp, without ending / -> /tmp = OK, /tmp/ = NOT OK)
export exportlocation=/tmp
# import after syscopy (default yes)
export autoimport=yes
# export E070L (default yes, should be done if target is an existing system)
export e07lexport=yes
# SAP License (default yes)
export licexport=yes
# RZ10 Profiles
export rz10export=no
# RZ04 Operation Modes
export rz04export=no
# STRUST
export strustexport=no
# STRUSTSSO2
export strustsso2export=no
# STMS_QA (manual refresh in SAP needed before you can start)
export stmsqaexport=no
# STMS configuration
export stmsexport=no
# AL11
export al11export=no
# BD54
export bd54export=no
# FILE
export fileexport=no
# RZ70/SLD configuration
export rz70sldexport=no
# SCOT
export scotexport=no
# SICF services
export sicfexport=no
# RFC connections
export rfcconnectionsexport=no
# SM69 external commands
export sm69export=no
# WE20 WE21 BD97
export we202197export=no
# SMLG/RZ12
export smlgrz12export=no
# ABAP Dev (only if target is a development system)
export abapdevexport=no
# GTS/SLL Export
export gtssllexport=no
# OAC0
export oac0export=no
# SCC4
export scc4export=no
# Report Variants
export reportvariants=no
# DBACOCKPIT
export dbacockpit=no
# Custom Tables (adjust array tables_customtables like this ('table1' 'table2' 'table3'))
export customtables=no
declare -a tables_customtables=('table1' 'table2' 'table3')
#
#### Expert Options ####
# change only if you know exactly what you are doing #
#
# use xuser instead of normal db user (default yes)
# Info: If you use xuser, no passwords will shown at the console
# Info: use 'xuser list' to show the available xusers
# WARNING: CAN NOT BE USED IF TARGET AND SOURCE DB USERS HAVE DIFFERENT PASSWORDS!
# WARNING: If the passwords of the target and source db users are different you have to set no!
export usexuser=yes
#
# xuserkey source (default w, xusersource need at least Backup, DBInfoRead, AccessUtility and SystemCmd)
export xusersource=w
#
# xuserkey target (default w, xusertarget need at least DBStart, DBStop, DBInfoRead, AccessUtility, SystemCmd, AccessSQL, LoadSysTab and Recovery)
export xusertarget=w
#
# source db user for backup (default SUPERDBA, need at least Backup, DBInfoRead, AccessUtility and SystemCmd)
# Warning: If you use db users, passwords will shown at the console
# only used if usexuser=no
export dbsourceuser=SUPERDBA
#
# target db user for restore (default SUPERDBA, need at least DBStart, DBStop, DBInfoRead, AccessUtility, SystemCmd, AccessSQL, LoadSysTab and Recovery)
# Warning: If you use db users, passwords will shown at the console
# only used if usexuser=no
export dbtargetuser=SUPERDBA
#
# second clear log run (default is no, yes or no)
export secondclearlog=no
#
# compressed backup (default is no, yes or no)
# Warning: can adversely affect the performance of the source system!
export backupcompressed=no
#
# ssh chipher (default aes192-ctr, example: arcfour, arcfour128, arcfour256, aes192-ctr, aes256-ctr, aes192-cbc, aes256-cbc etc.)
# on IBM Power7 "arcfour" is the fastest, on IBM Power8 "aes192-ctr" is best of security and speed
export sshcipher=aes192-ctr
#
# MaxDB pipe size (default 128 (1MB), value in pages and 1 page = 8 KB)
# dd blocksize and MaxDB pipe size are interdependent!
# pipesize should half blocksize (blocksize in k / 8 / 2)
# Warning: can adversely affect the performance of the source system!
# low performance impact but lower speed --> 8-32
# high performance impact but faster --> >= 64
export pipesize=128
#
# dd blocksize (default is automatic calculated, example: 8k, 512k, 1M, 16M)
# dd blocksize and MaxDB pipe size are interdependent!
# blocksize should be double pipesize (pipesize * 8 * 2 k)
# Warning: can adversely affect the performance of the source system!
export blocksize=$(echo "($pipesize*8*2)" | bc -l)k
# export blocksize=2048k
#
# disable CTRL+C on some points to prevent damage and endless processes (default yes)
export disablectrlc=yes
#
# remove export file after successfull import (default no)
export remexpafterimp=no
#
# enable batch mode (no security question, default no)
# INFO: to run in batchmode you have to use nohup (example "nohup db_copy_xx.sh &")
# INFO: batchmode is only possible if you use xuser!
export enablebatch=no
#
#
#### Transport and SQL configuration ####
# change only if you know exactly what you are doing #
#
# sql tables to delete 
declare -a sql_deltables=('ALCONSEG' 'ALSYSTEMS' 'DBSNP' 'MONI' 'OSMON' 'PAHI' 'SDBAD' 'SDBAH' 'SDBAP' 'SDBAR' 'DDLOG' 'TPFET' 'TPFHT' 'TLOCK' 'CNHIST' 'CNREPRT' 'CNMEDIA' 'DBSTATHADA' 'DBSTATIHADA' 'DBSTATIADA' 'DBSTATTADA' 'SDBAADAUPD')
# e07lexport
declare -a tables_e07lexport=('E070L')
# licexport
declare -a tables_licexport=('SAPLIKEY')
# rz10export
declare -a tables_rz10export=('TPFET' 'TPFHT')
# rz04export
declare -a tables_rz04export=('BTCOMSET' 'TPFBA' 'TPFID')
# strustexport
declare -a tables_strustexport=('SMIME_CAPA_CRYPT' 'SMIME_CAPA_SIGN' 'SMIME_CAPABILITY' 'SSF_PSE_D' 'SSF_PSE_H' 'SSF_PSE_HIST' 'SSF_PSE_L' 'SSF_PSE_T' 'SSFAPPLIC' 'SSFAPPLICT' 'SSFARGS' 'SSFVARGS' 'SSFVARGST' 'SSFVKEYDEF' 'STRUSTCAB' 'STRUSTCERT' 'STRUSTCRL' 'STRUSTCRP' 'STRUSTCRPT' 'STRUSTCRR' 'STRUSTCRRT' 'STRUSTCRS' 'STRUSTCRT' 'TWPSSO2ACL' 'USERINFO_STORAGE' 'USRCERTMAP' 'USRCERTRULE')
# strustsso2export
declare -a tables_strustsso2export=('SNCSYSACL' 'TSP0U' 'TXCOMSECU' 'USRACL' 'USRACLEXT')
# stmsqaexport
declare -a tables_stmsqaexport=('TMSQNOTES' 'TMSQNOTESH' 'TMSQWLF' 'TMSQWLFH' 'TMSQWLH' 'TMSQWLN' 'TMSQWL' 'TMSQLASTWL')
# stmsexport
declare -a tables_stmsexport=('ALMBCDATA' 'DLV_SYSTC' 'E070L' 'E070USE' 'TCECLILY' 'TCECPSTAT' 'TCEDELI' 'TCERELE' 'TCESYST' 'TCESYSTT' 'TCETARG' 'TCETARGHDR' 'TCETARGT' 'TCETRAL' 'TCETRALT' 'TCEVERS' 'TCEVERST' 'TMSACTDAT' 'TMSALOG' 'TMSALOGAR' 'TMSALRTSYS' 'TMSBCIBOX' 'TMSBCIIBOX' 'TMSBCIJOY' 'TMSBCINEX' 'TMSBCINTAB' 'TMSBCIOBJ' 'TMSBCIXBOX' 'TMSBUFCNT' 'TMSBUFPRO' 'TMSBUFREQ' 'TMSBUFTXT' 'TMSCDES' 'TMSCDOM' 'TMSCDOMT' 'TMSCNFS' 'TMSCNFST' 'TMSCROUTE' 'TMSCSYS' 'TMSCSYST' 'TMSCTOK' 'TMSFSYSH' 'TMSFSYSL' 'TMSMCONF' 'TMSPCONF' 'TMSPVERS' 'TMSQASTEPS' 'TMSQASTEPT' 'TMSQASTEPZ' 'TMSQCONFRM' 'TMSSRV' 'TMSSRVT' 'TMSTLOCKNP' 'TMSTLOCKNR' 'TMSTLOCKP' 'TMSTLOCKR' 'TRBAT' 'TRJOB' 'TRNSPACE' 'TRNSPACEL' 'TRNSPACETT')
# al11export
declare -a tables_al11export=('USER_DIR')
# bd54export
declare -a tables_bd54export=('TBDLS' 'TBDLST')
# fileexport
declare -a tables_fileexport=('FILENAME' 'FILENAMECI' 'FILEPATH' 'FILESYS' 'FILETEXT' 'FILETEXTCI' 'FSYSTXT' 'OPSYSTEM' 'OPTEXT' 'PARAMVALUE' 'PATH' 'PATHTEXT' 'USER_DIR')
# rz70sldexport
declare -a tables_rz70sldexport=('LCRT_INDX' 'SLDAGADM')
# scotexport
declare -a tables_scotexport=('BCSD_BLMODULE' 'BCSD_BREAKLOOP' 'BCSD_RQST' 'BCSD_STML' 'SXADMINTAB' 'SXCONVERT' 'SXCONVERT2' 'SXCOS' 'SXCOS_T' 'SXCPDEF' 'SXCPRECV' 'SXCPSEND' 'SXDEVTYPE' 'SXDEVTYPL' 'SXDOMAINS' 'SXJOBS' 'SXNODES' 'SXPARAMS' 'SXRETRY' 'SXROUTE' 'SXSERV' 'SXTELMOIN' 'SXTELMOOUT' 'T005J' 'T005K' 'TSAPD')
# sicfexport
declare -a tables_sicfexport=('ICF_SESSION_CNTL' 'ICFAPPLICATION' 'ICFDOCU' 'ICFHANDLER' 'ICFINSTACT' 'ICFSECPASSWD' 'ICFSERVICE' 'ICFSERVLOC' 'ICFVIRHOST' 'TWPURLSVR')
# rfcconnectionsexport
declare -a tables_rfcconnectionsexport=('RFC_TT_ACL' 'RFC_TT_ACL_HIST' 'RFC_TT_SAMEU' 'RFCADPTATTR' 'RFCATTRIB' 'RFCCAT' 'RFCCHECK' 'RFCCMC' 'RFCDES' 'RFCDESSECU' 'RFCDOC' 'RFCGO' 'RFC2SOAPS' 'RFCSOAPS' 'RFCSYSACL' 'RFCSYSACL_CLNT' 'RFCTRUST' 'RFCTXTAB' 'RFCTYPE' 'RSECACHK' 'RSECACTB' 'RSECTAB' 'SNCSYSACL')
# we202197export
declare -a tables_we202197export=('EDIPO' 'EDIPO2' 'EDIPOA' 'EDIPOACODPAG' 'EDIPOD' 'EDIPOF' 'EDIPOI' 'EDIPORT' 'EDIPOX' 'EDIPOXH' 'EDIPOXU' 'EDP12' 'EDP13' 'EDP21' 'EDPP1' 'TBLSYSDEST' 'TBSPECDEST')
# sm69export
declare -a tables_sm69export=('SXPGCOSTAB')
# smlgrz12export
declare -a tables_smlgrz12export=('RZLLICLASS' 'RZLLITAB')
# abapdevexport
declare -a tables_abapdevexport=('ADIRACCESS' 'DEVACCESS' 'ENHCONTRACTCONT' 'ENHLOG' 'ENHOBJCONTRACT' 'RSEUMOD' 'VRSD' 'VRSMODISRC' 'VRSX' 'VRSX2' 'VRSX3' 'VRSX4' 'VRSX5')
# gtssllexport
declare -a tables_gtssllexport=('/SAPSLL/TCOGVA' '/SAPSLL/TCOGVS' '/SAPSLL/TCOGVST')
# oac0export
declare -a tables_oac0export=('TOAAR')
# scc4export
declare -a tables_scc4export=('T000')
# reportvariants
declare -a tables_reportvariants=('VARI' 'VARID' 'VARIT' 'VARIS' 'VARINUM')
# dbacockpit
declare -a tables_dbacockpit=('DB6NAVSYST' 'DB6PMPROT' 'DBA_CONFIG' 'DBCON' 'DBCONUSR' 'SDBAD' 'SDBAH' 'SDBAP' 'SDBAR')
# Configuration end #####################################################################################

# INFOS AND CHECKS ######################################################################################

# variables - do NOT modify
export targetsidadm=$(echo $targetsid | tr '[:upper:]' '[:lower:]')adm
export sourcesidadm=$(echo $sourcesid | tr '[:upper:]' '[:lower:]')adm
export pipedate=$(date "+%d%m%Y")
export workdirectory=$(pwd)
export dbcopy_script_version='GitHub Version 1.0 (c) Florian Lamml - 2017'

# clear screen
clear

### define functions ###
# mail batch check
function sendmailcheckbatch {
if [ $sendfinishmail == yes ] && [ $enablebatch == yes ];
then
  echo $RCCODE | mail -s "System Copy $sourcesid to $targetsid ERROR in checks" "$mailadress"
fi
}

# function batchmode ssh source
function batchmodesshsource {
ssh -oBatchMode=yes -oForwardX11=no -c $sshcipher $sourcesidadm@$sourcehost "$1"
}

# function batchmode ssh target
function batchmodesshtarget {
ssh -oBatchMode=yes -oForwardX11=no -c $sshcipher $targetsidadm@$targethost "$1"
}

# function ssh source
function sshsource {
ssh -oForwardX11=no -c $sshcipher $sourcesidadm@$sourcehost "$1"
}

# function ssh target
function sshtarget {
ssh -oForwardX11=no -c $sshcipher $targetsidadm@$targethost "$1"
}

# sleep and space
function sleepandspace {
	sleep 1
	echo "=====" | tee -a $dbcopylog
	sleep 1
}

# send mail normal
function sendmailnormal {
if [ $sendfinishmail == yes ];
then
  cat $dbcopylog | mail -s "System Copy $sourcesid to $targetsid finish" "$mailadress"
fi
}

# send mail batch
function sendmailbatch {
if [ $sendfinishmail == yes ] && [ $enablebatch == yes ];
then
  cat $dbcopylog | mail -s "System Copy $sourcesid to $targetsid ERROR" "$mailadress"
fi
}
### define functions ###

# do some checks
echo "===================================="
echo "DB Copy Script "$(date "+%d.%m.%Y %H:%M:%S")
echo $dbcopy_script_version
echo "===================================="
echo "Check environment, please wait..."

# root check
echo -ne "* Check root... \c"
if [ "$(whoami)" == "root" ];
then
	echo "This script must not be run as root user! ... EXIT! (RC=99)"
	export RCCODE="This script must not be run as root user! ... EXIT! (RC=99)"
	sendmailcheckbatch
	exit 99
fi
sleep 1
echo "OK!"

# test source login an chipher
echo -ne "* Check SSH on source... \c"
batchmodesshsource 'exit'
if [ $? -ne 0 ];
 then
	echo "Problem with SSH on source! .ssh/authorized_keys2 OK? SSH Chipher OK? known hosts OK? ... EXIT! (RC=91)"
	export RCCODE="Problem with SSH on source! .ssh/authorized_keys2 OK? SSH Chipher OK? known hosts OK? ... EXIT! (RC=91)"
	sendmailcheckbatch
	exit 91
fi
sleep 1
echo "OK!"

# test target login an chipher
echo -ne "* Check SSH on target... \c"
batchmodesshtarget 'exit'
if [ $? -ne 0 ];
 then
	echo "Problem with SSH on target! .ssh/authorized_keys2 OK? SSH Chipher OK? known hosts OK? ... EXIT! (RC=90)"
	export RCCODE="Problem with SSH on target! .ssh/authorized_keys2 OK? SSH Chipher OK? known hosts OK? ... EXIT! (RC=90)"
	sendmailcheckbatch
	exit 90
fi
sleep 1
echo "OK!"

# lock file
echo -ne "* Check lockfile... \c"
export copylockfile=/tmp/dbcopy.lock
if [ -f $copylockfile ];
then
        kill -0 $(cat $copylockfile) &>/dev/null
        if [ $? -eq 0 ];
        then
                echo "Another copy script is still running. ... EXIT! (RC=98)"
				export RCCODE="Another copy script is still running. ... EXIT! (RC=98)"
				sendmailcheckbatch
                exit 98
        else
                echo -ne "Deprecated lock file found. Remove lock file. \c"
                rm -f $copylockfile
        fi
fi
sleep 1
echo "OK!"

# write lockfile
echo $$ > $copylockfile

# logfile check
echo -ne "* Check logfile... \c"
if [ -f $dbcopylog ];
then
	echo -ne "Logfile with same name exists - rename to "$dbcopylog"."$(date "+%d%m%Y%H%M%S")"... \c"
	mv $dbcopylog $dbcopylog.$(date "+%d%m%Y%H%M%S")
fi
sleep 1
echo "OK!"

# check config
echo -ne "* Check config... \c"
if [ $enablebatch == yes ] && [ $usexuser == no ];
then
	echo "Cannot run batchmode without xusers, check your config... EXIT!  (RC=85)"
	export RCCODE="Cannot run batchmode without xusers, check your config... EXIT!  (RC=85)"
	sendmailcheckbatch
	exit 85
elif [ -z "$sourcehost" ] || [ -z "$targethost" ] || [ -z "$sourcesid" ] || [ -z "$targetsid" ] || [ -z "$dbcopylog" ] || [ -z "$pipesize" ] || [ -z "$blocksize" ] || [ -z "$exportlocation" ];
then
	echo "Some parameter missing... EXIT!  (RC=85)"
	export RCCODE="Some parameter missing... EXIT!  (RC=85)"
	sendmailcheckbatch
	exit 85
fi
sleep 1
echo "OK!"

# check temporary status files source
echo -ne "* Check tempfile write on source... \c"
export check_tmprcheck=0
declare -a check_tempstatusfiles=('
dbcopy_tmpbacklist' '/tmp/dbcopy_backuplog' '/tmp/dbcopy_backupend' '/tmp/dbcopy_tmp_recover_state' '/tmp/dbcopy_pipecopyend_1' '/tmp/dbcopy_pipecopyend_2' '/tmp/dbcopy_deltables.sql' '/tmp/dbcopy_tmp_exporttables.tpl' '/tmp/dbcopy_tmp_exporttables_unsort.tpl' '/tmp/dbcopy_tmp_exporttables_sort.tpl' '/tmp/dbcopy_dbsizetarget_'$sourcesid'' '/tmp/dbcopy_dbversion_'$sourcesid'')
for check_tempstatusfile in "${check_tempstatusfiles[@]}"
do
   touch $check_tempstatusfile &>/dev/null
   export check_tmprcheck=$(($check_tmprcheck + $?))
done
if [ $check_tmprcheck -ne 0 ];
 then
	echo "Problem to create temporary status files on source. Check if there are in /tmp old data from a previous run! ... EXIT!  (RC=89)"
	rm -f $copylockfile
	export RCCODE="Problem to create temporary status files on source. Check if there are in /tmp old data from a previous run! ... EXIT!  (RC=89)"
	sendmailcheckbatch
	exit 89
fi
for check_tempstatusfile in "${check_tempstatusfiles[@]}"
do
   rm $check_tempstatusfile
done
sleep 1
echo "OK!"

# check temporary status files target
echo -ne "* Check tempfile write on target... \c"
export check_tmprcheck=0
declare -a check_tempstatusfiles=('/tmp/dbcopy_tmprestlist' '/tmp/dbcopy_restorelog' '/tmp/dbcopy_restoreend' '/tmp/dbcopy_deltables.sql' '/tmp/dbcopy_dbsizetarget_'$targetsid'' '/tmp/dbcopy_dbversion_'$targetsid'' ''$exportlocation'/'$targetsid'_dbcopy_exporttables.tpl' ''$exportlocation'/'$targetsid'_dbcopy_exporttables.log' '/tmp/dbcopy_renamedbsid' '/tmp/dbcopy_dbonline' '/tmp/dbcopy_changesqlpass')
for check_tempstatusfile in "${check_tempstatusfiles[@]}"
do
   batchmodesshtarget 'touch '$check_tempstatusfile'' &>/dev/null
   export check_tmprcheck=$(($check_tmprcheck + $?))
done
if [ $check_tmprcheck -ne 0 ];
 then
	echo "Problem to create temporary status files on target. Check if there are in /tmp old data from a previous run! ... EXIT!  (RC=88)"
	rm -f $copylockfile
	export RCCODE="Problem to create temporary status files on target. Check if there are in /tmp old data from a previous run! ... EXIT!  (RC=88)"
	sendmailcheckbatch
	exit 88
fi
for check_tempstatusfile in "${check_tempstatusfiles[@]}"
do
   batchmodesshtarget 'rm '$check_tempstatusfile''
done
sleep 1
echo "OK!"

# check pipes on source
echo -ne "* Check pipes on source... \c"
export check_tmprcheck=0
touch /tmp/"$sourcesid"to"$targetsid"_pipe_t_"$pipedate"_1 &>/dev/null
export tmprcheck=$(($tmprcheck + $?))
touch /tmp/"$sourcesid"to"$targetsid"_pipe_t_"$pipedate"_2 &>/dev/null
export tmprcheck=$(($tmprcheck + $?))
if [ $check_tmprcheck -ne 0 ];
 then
	echo "Problem to create pipes on source. Check if there are in /tmp old data from a previous run! ... EXIT!  (RC=87)"
	rm -f $copylockfile
	export RCCODE="Problem to create pipes on source. Check if there are in /tmp old data from a previous run! ... EXIT!  (RC=87)"
	sendmailcheckbatch
	exit 87
fi
rm /tmp/"$sourcesid"to"$targetsid"_pipe_t_"$pipedate"_1
rm /tmp/"$sourcesid"to"$targetsid"_pipe_t_"$pipedate"_2
sleep 1
echo "OK!"

# check pipes on target
echo -ne "* Check pipes on target... \c"
export check_tmprcheck=0
batchmodesshtarget 'touch /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1' &>/dev/null
export tmprcheck=$(($tmprcheck + $?))
batchmodesshtarget 'touch /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2' &>/dev/null
export tmprcheck=$(($tmprcheck + $?))
if [ $check_tmprcheck -ne 0 ];
 then
	echo "Problem to create pipes on target. Check if there are in /tmp old data from a previous run! ... EXIT!  (RC=86)"
	rm -f $copylockfile
	export RCCODE="Problem to create pipes on target. Check if there are in /tmp old data from a previous run! ... EXIT!  (RC=86)"
	sendmailcheckbatch
	exit 86
fi
batchmodesshtarget 'rm /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1'
batchmodesshtarget 'rm /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2'
sleep 1
echo "OK!"

#info
echo "===================================="
sleep 2

# clear screen
clear

# message
echo "===================================="					| tee -a $dbcopylog
echo "DB Copy Script "$(date "+%d.%m.%Y %H:%M:%S")			| tee -a $dbcopylog
echo $dbcopy_script_version                                 | tee -a $dbcopylog
echo "===================================="                 | tee -a $dbcopylog
echo "Source DB.........:" $sourcesid                       | tee -a $dbcopylog
echo "Source HOST.......:" $sourcehost                      | tee -a $dbcopylog
echo "Source SAPADM.....:" $sourcesidadm                    | tee -a $dbcopylog
if [ $usexuser == yes ];                                    
then                                                        
 echo "Source XUSER Key..:" $xusersource                    | tee -a $dbcopylog
else                                                        
 echo "Source DB User....:" $dbsourceuser                   | tee -a $dbcopylog
fi                                                          
echo "Target DB.........:" $targetsid                       | tee -a $dbcopylog
echo "Target HOST.......:" $targethost						| tee -a $dbcopylog
echo "Target SAPADM.....:" $targetsidadm					| tee -a $dbcopylog
if [ $usexuser == yes ];
then
 echo "Target XUSER Key..:" $xusertarget					| tee -a $dbcopylog
else
 echo "Target DB User....:" $dbtargetuser					| tee -a $dbcopylog
fi
if [ $sourcehost == $targethost ];		
then
 echo "Local System Copy.: yes"								| tee -a $dbcopylog
fi
echo "DB Copy Logfile...:" $dbcopylog						| tee -a $dbcopylog
echo "Compressed Backup.:" $backupcompressed				| tee -a $dbcopylog
echo "SSH Chipher.......:" $sshcipher						| tee -a $dbcopylog
echo "DD Blocksize......:" $blocksize						| tee -a $dbcopylog
echo "MaxDB PIPE Size...:" $pipesize						| tee -a $dbcopylog
echo "Save secdir.......:" $savesecdir						| tee -a $dbcopylog
echo "Table Export......: yes/no"							| tee -a $dbcopylog
echo "* SAP License.....:" $licexport                       | tee -a $dbcopylog
echo "* E070L...........:" $e07lexport                      | tee -a $dbcopylog
echo "* RZ10 Profiles...:" $rz10export                      | tee -a $dbcopylog
echo "* RZ04 Modes......:" $rz04export                      | tee -a $dbcopylog
echo "* STRUST..........:" $strustexport                    | tee -a $dbcopylog
echo "* STRUSTSSO2......:" $strustsso2export                | tee -a $dbcopylog
echo "* STMS_QA.........:" $stmsqaexport                    | tee -a $dbcopylog
echo "* STMS............:" $stmsexport                      | tee -a $dbcopylog
echo "* AL11............:" $al11export                      | tee -a $dbcopylog
echo "* BD54............:" $bd54export                      | tee -a $dbcopylog
echo "* FILE............:" $fileexport                      | tee -a $dbcopylog
echo "* RZ70/SLD........:" $rz70sldexport                   | tee -a $dbcopylog
echo "* SCOT............:" $scotexport                      | tee -a $dbcopylog
echo "* SICF............:" $sicfexport                      | tee -a $dbcopylog
echo "* RFC Connections.:" $rfcconnectionsexport            | tee -a $dbcopylog
echo "* WE20/WE21/DB97..:" $we202197export                  | tee -a $dbcopylog
echo "* SM69............:" $sm69export                      | tee -a $dbcopylog
echo "* SMLG/RZ12.......:" $smlgrz12export                  | tee -a $dbcopylog
echo "* ABAP DEV........:" $abapdevexport                   | tee -a $dbcopylog
echo "* GTS/SLL.........:" $gtssllexport                    | tee -a $dbcopylog
echo "* OAC0............:" $oac0export                      | tee -a $dbcopylog
echo "* SCC4............:" $scc4export                      | tee -a $dbcopylog
echo "* Report Variants.:" $reportvariants                  | tee -a $dbcopylog
echo "* DBACOCKPIT......:" $dbacockpit                      | tee -a $dbcopylog
echo "* Custom Tables...:" $customtables                    | tee -a $dbcopylog
if [ $sendfinishmail == yes ];
then
 echo "Send mail to......:" $mailadress						| tee -a $dbcopylog
fi
echo "===================================="					| tee -a $dbcopylog
if [ $stmsqaexport == yes ];
 then
echo "************************************"								| tee -a $dbcopylog
echo "ATTENTION: PLEASE UPDATE STMS_QA IN SOURCE BEFORE PROCEEDING"		| tee -a $dbcopylog
echo "************************************"								| tee -a $dbcopylog
echo "===================================="								| tee -a $dbcopylog
fi

# check if xuser is used or read passwords for db user
if [ $usexuser == yes ];
then
 # set connectioninformation
 export dbmcliconnetsource="-U $xusersource"
 export dbmcliconnettarget="-U $xusertarget"
 export dbmcliconnetsourcesql="-USQL $xusersource"
 export dbmcliconnettargetsql="-USQL $xusertarget"
else
 # read passwords
 echo $dbsourceuser "password of" $sourcesid ":"
 # switch off echo
 stty -echo
 read sysdbapwdsource
 # switch on echo
 stty echo
 echo $dbtargetuser "password of" $targetsid" :"
 # switch off echo
 stty -echo
 read sysdbapwdtarget
 # switch on echo
 stty echo
 echo "===================================="
 # set connectioninformation
 export dbmcliconnetsource="-u '$dbsourceuser','$sysdbapwdsource'"
 export dbmcliconnettarget="-u '$dbtargetuser','$sysdbapwdtarget'"
 export dbmcliconnetsourcesql="-uSQL '$dbsourceuser','$sysdbapwdsource'"
 export dbmcliconnettargetsql="-uSQL '$dbtargetuser','$sysdbapwdtarget'"
fi

# db size informations and checks
sshsource 'dbmcli -d '$sourcesid' '"$dbmcliconnetsource"' -o /tmp/dbcopy_dbsizesource_'$sourcesid' info state'
sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' -o /tmp/dbcopy_dbsizetarget_'$targetsid' info state'
export sourcesizekberror=$(sshsource 'grep "ERR" /tmp/dbcopy_dbsizesource_'$sourcesid'' | wc -l)
export sourcesizekb=$(sshsource 'grep "Data" /tmp/dbcopy_dbsizesource_'$sourcesid' | grep KB | grep -v Perm | grep -v Temp | grep -v Max' | awk '{ print $4 }')
export sourcesizemb=$(echo "scale=0;0$sourcesizekb/1024" | bc -l)
export targetmaxsizekberror=$(sshtarget 'grep "ERR" /tmp/dbcopy_dbsizetarget_'$targetsid'' | wc -l)
export targetmaxsizekb=$(sshtarget 'grep "Data Max" /tmp/dbcopy_dbsizetarget_'$targetsid' | grep KB' | awk '{ print $5 }')
export targetmaxsizemb=$(echo "scale=0;0$targetmaxsizekb/1024" | bc -l)

# check source db
if [ $sourcesizekberror -ge 1 ];
then
	# message
	echo "source database not available --> EXIT (RC=97)"
	# logfile
	echo "source database not available --> EXIT  (RC=97) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
    # remove lockfile
    rm -f $copylockfile
    # cleanup
    sshtarget 'rm /tmp/dbcopy_dbsizetarget_'$targetsid''
    sshsource 'rm /tmp/dbcopy_dbsizesource_'$sourcesid''
	# send mail bath
    sendmailbatch
	exit 97;
else
# size check
if [ 1$sourcesizemb -gt 1$targetmaxsizemb ];
then
    # check target db
	if [ $targetmaxsizekberror == 0 ];
	then
	    # message
		echo "Size of source data in MB..........: " $sourcesizemb
	    echo "Maxsize of target database in MB...: " $targetmaxsizemb
		echo "Error source database size bigger than target max database size --> EXIT (RC=96)"
		# logfile
		echo "Size of source data in MB..........: " $sourcesizemb " "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
		echo "Maxsize of target database in MB...: " $targetmaxsizemb " "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
		echo "Error source database size bigger than target max database size --> EXIT (RC=96) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
        # remove lockfile
        rm -f $copylockfile
        # cleanup
        sshtarget 'rm /tmp/dbcopy_dbsizetarget_'$targetsid''
        sshsource 'rm /tmp/dbcopy_dbsizesource_'$sourcesid''
		exit 96;
	else
	# message
	sleep 1
	echo "Error - target database not available in state online"
	echo ""
	echo "Anyway, you can continue copy the system at your own risk!"
	echo ""
	echo "===================================="
	# logfile
	echo "Error target database not available, cannot check size "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo " "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "Anyway, you can continue copy the system at your own risk! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo " "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "==================================== "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# set noexport
	export donotexport=1
	fi
else
    # message
	sleep 1
	echo "Size of source data in MB..........: " $sourcesizemb
	echo "Maxsize of target database in MB...: " $targetmaxsizemb
	echo "===================================="
	# logfile
	echo "Size of source data in MB..........: " $sourcesizemb " "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "Maxsize of target database in MB...: " $targetmaxsizemb " "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "====================================" >> $dbcopylog
	# write E070L from source into log
	echo "E070L from "$targetsid $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	sshtarget 'sqlcli -U DEFAULT -f "SELECT * FROM E070L"' &>> $dbcopylog
	echo "====================================" >> $dbcopylog
	# set noexport
	export donotexport=0
fi
fi

# version check
sshsource 'dbmcli -d '$sourcesid' '"$dbmcliconnetsource"' -o /tmp/dbcopy_dbversion_'$sourcesid' dbm_version'
sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' -o /tmp/dbcopy_dbversion_'$targetsid' dbm_version'
export sourceversion=$(sshsource 'grep BUILD /tmp/dbcopy_dbversion_'$sourcesid'' | awk -F"= " '{ print $2 }')
export targetversion=$(sshtarget 'grep BUILD /tmp/dbcopy_dbversion_'$targetsid'' | awk -F"= " '{ print $2 }')
# message
sleep 1
echo "Version of Source DB...............: " $sourceversion
echo "Version of Target DB...............: " $targetversion
if [ "$sourceversion" != "$targetversion" ];
 then
  echo "************************************"   
  echo "ATTENTION: PLEASE CHECK THE DB VERSIONS!"
  echo "SOURCE <= TARGET = OK"
  echo "SOURCE > TARGET = NOT OK"
  echo "************************************"
fi
echo "===================================="
# logfile
echo "Version of Source DB...............: " $sourceversion " "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
echo "Version of Target DB...............: " $targetversion " "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
if [ "$sourceversion" != "$targetversion" ];
 then
  echo "************************************"       $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  echo "ATTENTION: PLEASE CHECK THE DB VERSIONS!"   $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  echo "SOURCE <= TARGET = OK"						$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  echo "SOURCE > TARGET = NOT OK"					$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  echo "************************************"       $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
fi
echo "====================================" >> $dbcopylog
#

# security question
if [ $enablebatch == no ];
then
  echo "Start the Database-Copy from "$sourcesid" to "$targetsid" ?"
  echo "WARNING: "$targetsid"-DB will be overwritten!"
  echo "===================================="
  read -r -p "Are you sure? [y/N] " response
  case $response in
      [yY][eE][sS]|[yY])
	      # message
          echo "Start the Database-Copy!"
		  echo "===================================="
		  # log
		  echo "Start the Database-Copy! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
		  echo "====================================" >> $dbcopylog
          ;;
      *)
          # message
		  echo "Stopping now & Cleanup! (RC=0)"
		  # log
		  echo "Stopping now & Cleanup! (RC=0) " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
		  # remove lockfile
		  rm -f $copylockfile
		  # cleanup
		  sshtarget 'rm /tmp/dbcopy_dbsizetarget_'$targetsid''
		  sshsource 'rm /tmp/dbcopy_dbsizesource_'$sourcesid''
		  exit 0
          ;;
  esac
elif [ $enablebatch == yes ];
then
 # message
 echo "Batchmode is active"
 echo "===================================="
 # log
 echo "Batchmode is active " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
 echo "====================================" >> $dbcopylog
fi
   
# START #################################################################################################

# time and date
echo "START DB COPY: " $(date "+%d.%m.%Y %H:%M:%S") & export starttime=$(date +%s)
echo "START DB COPY: " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
echo "===================================="
echo "====================================" >> $dbcopylog

# cleanup files no longer used
sshtarget 'rm /tmp/dbcopy_dbsizetarget_'$targetsid''
sshsource 'rm /tmp/dbcopy_dbsizesource_'$sourcesid''

if [ $savesecdir == yes ];
then 
  # message
  echo "Save SEC dir"
  # logfile
  echo "Save SEC dir "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  # save secdir
  if [ $abaporjava == abap ];
  then 
    sshtarget  'cdD; cp -rp sec syscopy_sec' >> $dbcopylog
	export savesecdirpath=$(sshtarget 'cdD; cd syscopy_sec; pwd')
	echo "SEC dir of "$targetsid" was saved to "$savesecdirpath" on "$targethost $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  elif [ $abaporjava == java ];
  then
    sshtarget  'cdJ; cp -rp sec syscopy_sec' >> $dbcopylog
	export savesecdirpath=$(sshtarget 'cdJ; cd syscopy_sec; pwd')
	echo "SEC dir of "$targetsid" was saved to "$savesecdirpath" on "$targethost $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  else
    export savesecdirpath='Cannot save secdir'
	echo $savesecdirpath $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
    # message
    echo "Please define if ABAP or JAVA, cannot save secdir"
    # log
    echo "Please define if ABAP or JAVA, cannot save secdir "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  fi
  # message
  echo "SEC dir saved"
  # logfile
  echo "SEC dir saved "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  # function sleepandspace
  sleepandspace
fi

if ( [ $e07lexport == yes ] || [ $licexport == yes ] || [ $rz10export == yes ] || [ $rz04export == yes ] || [ $strustexport == yes ] || [ $strustsso2export == yes ] || [ $stmsqaexport == yes ] || [ $stmsexport == yes ] || [ $al11export == yes ] || [ $bd54export == yes ] || [ $fileexport == yes ] || [ $rz70sldexport == yes ] || [ $scotexport == yes ] || [ $sicfexport == yes ] || [ $rfcconnectionsexport == yes ] || [ $we202197export == yes ] || [ $sm69export == yes ] || [ $smlgrz12export == yes ] || [ $abapdevexport == yes ] || [ $gtssllexport == yes ] || [ $oac0export == yes ] || [ $scc4export == yes ] || [ $reportvariants == yes ] || [ $dbacockpit == yes ] || [ $customtables == yes ] ) && ( [ $donotexport -eq 0 ] );
then
  # message
  echo "Create Export Template File"
  # logfile
  echo "Create Export Template File " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  # create export file header
  echo "export" > /tmp/dbcopy_tmp_exporttables.tpl
  echo "file = '"$exportlocation"/"$targetsid"_dbcopy_exporttables.dat'" >> /tmp/dbcopy_tmp_exporttables.tpl
  # create a unsort list of tables to export
  if [ $e07lexport == yes ];
   then
  	  for table in "${tables_e07lexport[@]}"
  	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $licexport == yes ];
   then
  	  for table in "${tables_licexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $rz10export == yes ];
   then
	  for table in "${tables_rz10export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $rz04export == yes ];
   then
	  for table in "${tables_rz04export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	 done
  fi
  
  if [ $strustexport == yes ];
   then
	  for table in "${tables_strustexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $strustsso2export == yes ];
   then
	  for table in "${tables_strustsso2export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $stmsqaexport == yes ];
   then
	  for table in "${tables_stmsqaexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $stmsexport == yes ];
   then
	  for table in "${tables_stmsexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $al11export == yes ];
   then
	  for table in "${tables_al11export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi

  if [ $bd54export == yes ];
   then
	  for table in "${tables_bd54export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $fileexport == yes ];
   then
	  for table in "${tables_fileexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $rz70sldexport == yes ];
   then
	  for table in "${tables_rz70sldexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $scotexport == yes ];
   then
	  for table in "${tables_scotexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $sicfexport == yes ];
   then
	  for table in "${tables_sicfexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $rfcconnectionsexport == yes ];
   then
	  for table in "${tables_rfcconnectionsexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $we202197export == yes ];
   then
	  for table in "${tables_we202197export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $sm69export == yes ];
   then
	  for table in "${tables_sm69export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $smlgrz12export == yes ];
   then
	  for table in "${tables_smlgrz12export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi

  if [ $abapdevexport == yes ];
   then
	  for table in "${tables_abapdevexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $gtssllexport == yes ];
   then
	  for table in "${tables_gtssllexport[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $oac0export == yes ];
   then
	  for table in "${tables_oac0export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $scc4export == yes ];
   then
	  for table in "${tables_scc4export[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $reportvariants == yes ];
   then
	  for table in "${tables_reportvariants[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $dbacockpit == yes ];
   then
	  for table in "${tables_dbacockpit[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  
  if [ $customtables == yes ];
   then
	  for table in "${tables_customtables[@]}"
	  do
		  echo $table >> /tmp/dbcopy_tmp_exporttables_unsort.tpl
	  done
  fi
  sleep 1
  
  # sort list of tables to export and only use unique
  sort -u /tmp/dbcopy_tmp_exporttables_unsort.tpl > /tmp/dbcopy_tmp_exporttables_sort.tpl
  sleep 1
  # create final file for export 
  while read tmp_exporttables
	  do
		  echo "delete from "$tmp_exporttables >> /tmp/dbcopy_tmp_exporttables.tpl
		  echo "select * from "$tmp_exporttables >> /tmp/dbcopy_tmp_exporttables.tpl
  done < /tmp/dbcopy_tmp_exporttables_sort.tpl
  # cleanup files
  rm /tmp/dbcopy_tmp_exporttables_unsort.tpl
  rm /tmp/dbcopy_tmp_exporttables_sort.tpl
  sleep 1
  # message
  echo "Export Template File created"
  # logfile
  echo "Export Template File created" $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  export noexport=0
  
  # function sleepandspace
  sleepandspace
else
  export noexport=1
fi

if [ $noexport -ne 1 ];
then
  # message
  echo "Export Tables from "$targetsid
  # logfile
  echo "Export Tables from "$targetsid $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  # export
  scp /tmp/dbcopy_tmp_exporttables.tpl $targetsidadm@$targethost:$exportlocation/"$targetsid"_dbcopy_exporttables.tpl >> $dbcopylog
  sshtarget 'R3trans -w '$exportlocation'/'$targetsid'_dbcopy_exporttables.log '$exportlocation'/'$targetsid'_dbcopy_exporttables.tpl' >> $dbcopylog
  export expcode=$(sshtarget "cat '$exportlocation'/'$targetsid'_dbcopy_exporttables.log | tail -n 2 | head -n 1 | awk -F\( '{ print $2 }' | awk -F\) '{ print $1 }'" | awk -F\( '{ print $2 }' | awk -F\) '{ print $1 }')
  # message
  echo "Tables from "$targetsid" exported with RC="$expcode
  if [ "$expcode" == '0000' ];
   then
    rm /tmp/dbcopy_tmp_exporttables.tpl
  fi
  # logfile
  echo "Tables from "$targetsid" exported " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  echo "Returncode of Export: " $expcode $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

  # function sleepandspace
  sleepandspace
fi

# message
echo "Create PIPE "$sourcesid"to"$targetsid"_pipe_(s/t)_"$pipedate"_1 and "$sourcesid"to"$targetsid"_pipe_(s/t)_"$pipedate"_2 in /tmp"
# logfile
echo "Create PIPE "$sourcesid"to"$targetsid"_pipe_(s/t)_"$pipedate"_1 and "$sourcesid"to"$targetsid"_pipe_(s/t)_"$pipedate"_2 in /tmp "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# create pipes (MaxDB default - 2 pipes)
# target
sshtarget 'mkfifo /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1; chmod 777 /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1' &>> $dbcopylog
sshtarget 'mkfifo /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2; chmod 777 /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2' &>> $dbcopylog
# source
sshsource 'mkfifo /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_1; chmod 777 /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_1' &>> $dbcopylog
sshsource 'mkfifo /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_2; chmod 777 /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_2' &>> $dbcopylog
# message
echo "PIPE "$sourcesid"to"$targetsid"_pipe_(s/t)_"$pipedate"_1 and "$sourcesid"to"$targetsid"_pipe_(s/t)_"$pipedate"_2 are created in /tmp"
# logfile
echo "PIPE "$sourcesid"to"$targetsid"_pipe_(s/t)_"$pipedate"_1 and "$sourcesid"to"$targetsid"_pipe_(s/t)_"$pipedate"_2 are created in /tmp "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# backup template
if [ $backupcompressed == yes ];
 then
  export backuptemplatesource=''$sourcesid'to'$targetsid' TO PIPE /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_1 COMPRESSED PIPE /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_2 COMPRESSED CONTENT COMPLETE DATA BLOCKSIZE '$pipesize''
  export backuptemplatetarget=''$sourcesid'to'$targetsid' TO PIPE /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1 COMPRESSED PIPE /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2 COMPRESSED CONTENT COMPLETE DATA BLOCKSIZE '$pipesize''
 else
  export backuptemplatesource=''$sourcesid'to'$targetsid' TO PIPE /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_1 PIPE /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_2 CONTENT COMPLETE DATA BLOCKSIZE '$pipesize''
  export backuptemplatetarget=''$sourcesid'to'$targetsid' TO PIPE /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1 PIPE /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2 CONTENT COMPLETE DATA BLOCKSIZE '$pipesize''
fi

# message
echo "Create source backup media"
# logfile
echo "Create source backup media "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# create backup media in source
sshsource 'dbmcli -d '$sourcesid' '"$dbmcliconnetsource"' backup_template_create '"$backuptemplatesource"'' >> $dbcopylog
# exit status
if [ $? -ne 0 ];
 then
	# message
	echo "Error create source backup media --> EXIT (RC=82)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Error create source backup media --> EXIT (RC=82) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 82;
fi
# message
echo "Source backup media created"
# logfile
echo "Source backup media created "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# message
echo "Create target backup media"
# logfile
echo "Create target backup media "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# create restore media in target
sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' backup_template_create '"$backuptemplatetarget"'' >> $dbcopylog
# exit status
if [ $? -ne 0 ];
 then
	# message
	echo "Error create target backup media --> EXIT (RC=83)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Error create target backup media --> EXIT (RC=83) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 83;
fi
# message
echo "Target backup media created"
# logfile
echo "Target backup media created "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# message
echo "Stop target SAP system"
# logfile
echo "Stop target SAP system "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# stop target system
sshtarget 'stopsap r3' >> $dbcopylog
# check the stopsap command if batchmode is not enabled
if [ $? -ne 0 ];
 then
 # message
 if [ $enablebatch == no ];
 then
  echo "Error with stopsap command." | tee -a $dbcopylog
  read -rsp $'Check the error, stop the target system and press ENTER to continue (cancel with CTRL+C)...\n'
 fi
fi

# message
echo "Target SAP system stopped"
# logfile
echo "Target SAP system stopped "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# disable Signal 2 (CTRL+C)
if [ $disablectrlc == yes ];
 then
	trap '' 2
    echo "### CTRL+C disabled ###" | tee -a $dbcopylog
	echo "=====" | tee -a $dbcopylog
fi

# message
echo "Start backup on source"
# logfile
echo "Start backup on source "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# start backup on source
sshsource 'echo "db_connect" > /tmp/dbcopy_tmpbacklist'
sshsource 'echo "backup_start "'$sourcesid'"to"'$targetsid' >> /tmp/dbcopy_tmpbacklist'
sshsource 'dbmcli -d '$sourcesid' '"$dbmcliconnetsource"' -i /tmp/dbcopy_tmpbacklist -o /tmp/dbcopy_backuplog && touch /tmp/dbcopy_backupend' >> $dbcopylog & 
# exit status
if [ $? -ne 0 ];
 then
	# message
	echo "Error Backup start --> EXIT (RC=95)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Error Backup start --> EXIT (RC=95) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 95;
fi
# status of backup
backupstartstatus=0
while [ $backupstartstatus -ne 1 ];
do
 export backupstartstatus=$(sshsource 'ls -l /tmp/ | grep dbcopy_backuplog | wc -l')
 sleep 5
done
# check
sleep 3
export backupstart=$(sshsource "cat /tmp/dbcopy_backuplog | head -n 2 | tail -n 1")
if [ "$backupstart" == 'OK' ];
then
	# message
	sleep 3
	echo "Backup started on source"
	# logfile
	echo "Backup started on source "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
else
	# message
	sleep 3
	echo "Error Backup start --> EXIT (RC=95)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Error Backup start --> EXIT (RC=95) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 95;
fi

# function sleepandspace
sleepandspace

# message
echo "Start restore on target"
# logfile
echo "Start restore on target "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# start restore on target
sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' db_admin' >> $dbcopylog
sshtarget 'echo "db_connect" > /tmp/dbcopy_tmprestlist'
sshtarget 'echo "db_activate RECOVER "'$sourcesid'"to"'$targetsid'" DATA AUTOIGNORE" >> /tmp/dbcopy_tmprestlist'
sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' -i /tmp/dbcopy_tmprestlist -o /tmp/dbcopy_restorelog && touch /tmp/dbcopy_restoreend' >> $dbcopylog &
# exit status
if [ $? -ne 0 ];
 then
	# message
	echo "Error Restore start --> EXIT  (RC=94)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Error Restore start --> EXIT (RC=94) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 94;
fi
# status of recover
export recoverstartstatus=0
while [ $recoverstartstatus -ne 1 ];
do
 export recoverstartstatus=$(sshtarget 'ls -l /tmp/ | grep dbcopy_restorelog | wc -l')
 sleep 5
done
# check
sleep 3
export backupstart=$(sshtarget "cat /tmp/dbcopy_restorelog | head -n 2 | tail -n 1")
if [ "$backupstart" == 'OK' ];
then
	# message
	sleep 3
	echo "Restore started on target"
	# logfile
	echo "Restore started on target "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
else
	# message
	sleep 3
	echo "Error Restore start --> EXIT  (RC=94)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Error Restore start --> EXIT (RC=94) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 94;
fi

# function sleepandspace
sleepandspace

# message
echo "Data transfer started with 2 dd streams"
# logfile
echo "Data transfer started with 2 dd streams "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# check if local or remote copy and start data transfer
if [ $sourcehost == $targethost ];
 then
   echo "Local System Copy"
   echo "Local System Copy "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
   sshsource 'dd if=/tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_1 of=/tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1 bs='$blocksize' && touch /tmp/dbcopy_pipecopyend_1' &>> $dbcopylog &
   sshsource 'dd if=/tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_2 of=/tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2 bs='$blocksize' && touch /tmp/dbcopy_pipecopyend_2' &>> $dbcopylog &
 else
   echo "Remote System Copy"
   echo "Remote System Copy "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
   sshsource 'dd if=/tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_1 bs='$blocksize' | ssh -oForwardX11=no -c '$sshcipher' '$targetsidadm'@'$targethost' dd of=/tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1 bs='$blocksize' && touch /tmp/dbcopy_pipecopyend_1' &>> $dbcopylog &
   sshsource 'dd if=/tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_2 bs='$blocksize' | ssh -oForwardX11=no -c '$sshcipher' '$targetsidadm'@'$targethost' dd of=/tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2 bs='$blocksize' && touch /tmp/dbcopy_pipecopyend_2' &>> $dbcopylog &
fi
# status of copy
export copystate=0
export transferstarted=0
export tempcounter=0
while [ $copystate -ne 2 ];
do
  # create a tempchar for status bar
  if [ $tempcounter -eq 0 ];
   then
     export tempchar="(|)"
     export tempcounter=$(($tempcounter + 1))
   elif [ $tempcounter -eq 1 ];
   then
     export tempchar="(/)"
     export tempcounter=$(($tempcounter + 1))
   elif [ $tempcounter -eq 2 ];
   then
     export tempchar="(-)"
     export tempcounter=$(($tempcounter + 1))
   elif [ $tempcounter -eq 3 ];
   then
     export tempchar="(\\)"
     export tempcounter=0
  fi
 # check recover state
 sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' recover_state' > /tmp/dbcopy_tmp_recover_state
 # restore overall pages
 export restoreprograssall=$(cat /tmp/dbcopy_tmp_recover_state | grep Count | grep -v Converter | awk '{ print $3 }')
 # restore left pages
 export restoreprogressleft=$(cat /tmp/dbcopy_tmp_recover_state | grep Left | awk '{ print $3 }')
 # restore transfered pages
 export restoreprogresstransfered=$(cat /tmp/dbcopy_tmp_recover_state | grep Transferred | awk '{ print $3 }')
 # copystate
 export copystate=$(sshsource 'ls -l /tmp/ | grep dbcopy_pipecopyend_ | wc -l')
 if [ $copystate -ne 2 ];
  then
   export restorepercent=$(echo "$restoreprogresstransfered/($restoreprograssall/100)" | bc -l | grep -v divide | awk -F. '{ print $1 }')
   # check if transfer started or clear log still running
   if [ 1$restoreprogressleft -gt 10 ];
    then
	   # take ddtime when transfer is really started
	   if [ $transferstarted -eq 0 ];
		then
		echo "Data transfer startet (after clear log) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
		export ddtimestart=$(echo "$(date +%s)+8" | bc -l)
		export transferstarted=1
	   fi
	 export allmb=$(echo "scale=2;(0$restoreprograssall*8)/1024" | bc -l)
     export leftmb=$(echo "scale=2;(0$restoreprogressleft*8)/1024" | bc -l)
     export transmb=$(echo "scale=2;(0$restoreprogresstransfered*8)/1024" | bc -l)
	 export ddduration=$(echo "$(date +%s)-$ddtimestart" | bc -l)
	 # check to prevent from divide by 0
	 if [ $ddduration -le 0 ];
	 then
	  export ddduration=8
	 fi
     export speed=$(echo "scale=2;$transmb/$ddduration" | bc -l)
  	 echo -ne "\r\e[KPage Count:" $restoreprograssall "("$allmb"MB) Transferred:" $restoreprogresstransfered "("$transmb"MB) Left:" $restoreprogressleft "("$leftmb"MB) Progress:" $restorepercent"% Speed: "$speed"MB/s "$tempchar" \r\c"
	    # write info to logfile (only every two minutes)
		if [ $(date "+%S") -ge 53 ] && [ $((10$(date "+%M")%2)) -eq 0 ];
         then
		 echo "Page Count:" $restoreprograssall "("$allmb"MB) Transferred:" $restoreprogresstransfered "("$transmb"MB) Left:" $restoreprogressleft "("$leftmb"MB) Progress:" $restorepercent"% Speed: "$speed"MB/s " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
		fi
    else
  	 echo -ne "\r\e[KWork in progress (that may take some time)... "$tempchar" \r\c"
   fi
   else       
	 echo -ne "\r\e[KData transfer end... \r\c"
 fi
sleep 5
done
sleep 2
sshsource 'rm /tmp/dbcopy_pipecopyend_*'
sshsource 'rm /tmp/dbcopy_tmp_recover_state'
# message
echo "Data transfer complete"
# logfile
echo "Data transfer complete "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# status of backup
export backupstate=0
while [ $backupstate -ne 1 ];
do
 export backupstate=$(sshsource 'ls -l /tmp/ | grep dbcopy_backupend | wc -l')
 sleep 5
done
sleep 2
sshsource 'rm /tmp/dbcopy_backupend'
# backupcheck
export dbcopy_backupendstate=$(sshsource 'grep "Returncode" /tmp/dbcopy_backuplog' | awk '{ print $2 }')
if [ "$dbcopy_backupendstate" == '0' ];
then 
	# message
	echo "Backup complete"
	# logfile
	echo "Backup complete "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
else
	# message
	echo "Backup Error --> EXIT (RC=93)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Backup Error --> EXIT (RC=93) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 93;
fi

# function sleepandspace
sleepandspace

# status of restore
export restorestate=0
while [ $restorestate -ne 1 ];
do
 export restorestate=$(sshtarget 'ls -l /tmp/ | grep dbcopy_restoreend | wc -l')
 sleep 5
done
sleep 2
sshtarget 'rm /tmp/dbcopy_restoreend'
# restorecheck
export dbcopy_restoreendstate=$(sshtarget 'grep "Returncode" /tmp/dbcopy_restorelog' | awk '{ print $2 }')
if [ "$dbcopy_restoreendstate" == '0' ];
then 
	# message
	echo "Restore complete"
	# logfile
	echo "Restore complete "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
else
	# message
	echo "Restore Error --> EXIT  (RC=92)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Restore Error --> EXIT (RC=92) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 92;
fi

# function sleepandspace
sleepandspace

# message
echo "Delete Backup and Restore logs"
# logfile
echo "Delete Backup and Restore logs "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# delete backup and restore logs
sshtarget 'rm /tmp/dbcopy_restorelog'
sshsource 'rm /tmp/dbcopy_backuplog'
# message
echo "Backup and Restore logs deleted"
# logfile
echo "Backup and Restore logs deleted "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

if [ $secondclearlog == yes ];
then 
  # message
  echo "Clear Log"
  # logfile
  echo "Clear Log "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  # clear log
  sshtarget  'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' db_offline' >> $dbcopylog
  sshtarget  'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' db_admin' >> $dbcopylog
  sshtarget  'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' util_execute clear log' >> $dbcopylog
  # message
  echo "Log cleared"
  # logfile
  echo "Log cleared "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  # function sleepandspace
  sleepandspace
fi

# enable Signal 2 (CTRL+C)
if [ $disablectrlc == yes ];
 then
	trap 2
	echo "### CTRL+C enabled ###" | tee -a $dbcopylog
	echo "=====" | tee -a $dbcopylog
fi

# message
echo "Start target DB"
# logfile
echo "Start target DB "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# start target db
if [ $usexuser == no ] && [ "$sysdbapwdsource" != "$sysdbapwdtarget" ];
  then
  echo "Different passwords between source and target "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
  sshtarget 'echo "user_sysdba "'$dbsourceuser'","'$sysdbapwdsource' > /tmp/dbcopy_dbonline; chmod 600 /tmp/dbcopy_dbonline'
  sshtarget 'echo "db_online" >> /tmp/dbcopy_dbonline'
  sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' -i /tmp/dbcopy_dbonline' >> $dbcopylog
  export dbstartstatus=$?
  sshtarget 'dbmcli -d '$targetsid' -u '$dbtargetuser','$sysdbapwdsource' user_put '$dbtargetuser' password='$sysdbapwdtarget'' >> $dbcopylog
  sshtarget 'rm /tmp/dbcopy_dbonline'
  # read passwords
  echo "Need actual password of SAP"$sourcesid "User of the "$targetsid" Database:"
  # switch off echo
  stty -echo
  read targetsqluserpassword
  # switch on echo
  stty echo
  sshtarget 'echo "ALTER PASSWORD SAP"'$sourcesid' '$targetsqluserpassword' > /tmp/dbcopy_changesqlpass; chmod 600 /tmp/dbcopy_changesqlpass'
  sshtarget 'sqlcli -d '$targetsid' -u '$dbtargetuser','"$sysdbapwdtarget"' -f -i /tmp/dbcopy_changesqlpass' &>> $dbcopylog
  sshtarget 'rm /tmp/dbcopy_changesqlpass' 
else
  sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' db_online' >> $dbcopylog
  export dbstartstatus=$?
fi
# exit status
if [ $dbstartstatus -ne 0 ];
 then
   # message
   echo "Error in Target DB start (RC=84)"
   # logfile
   echo "Error in Target DB start (RC=84) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
   # exit
   sendmailbatch
   exit 84;
fi
sleep 1
# check for error
export dbstartfail=$(sshsource 'grep "Database state: OFFLINE" '$workdirectory'/'$dbcopylog' | wc -l') >> $dbcopylog
if [ $dbstartfail -ne 0 ];
 then
 # message
 echo "Error in Target DB start (RC=84)"
 # logfile
 echo "Error in Target DB start (RC=84) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
 # exit
 sendmailbatch
 exit 84;
fi
# message
echo "Target DB started"
# logfile
echo "Target DB started "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# message
echo "Rename target DB"
# logfile
echo "Rename target DB "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# rename target db
sshtarget  'echo "sql_execute rename user SAP"'$sourcesid'" to SAP"'$targetsid' > /tmp/dbcopy_renamedbsid; chmod 600 /tmp/dbcopy_renamedbsid'
sshtarget  'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' '"$dbmcliconnettargetsql"' -i /tmp/dbcopy_renamedbsid' >> $dbcopylog
export dbrenamestatus=$?
sshtarget  'rm /tmp/dbcopy_renamedbsid'
# exit status
if [ $dbrenamestatus -ne 0 ];
 then
	# message
	echo "Error rename target DB --> EXIT (RC=81)"
	echo "You must fix the problem and clean up the /tmp directory before you start again!"
	# logfile
	echo "Error rename target DB --> EXIT (RC=81) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "You must fix the problem and clean up the /tmp directory before you start again! "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	# remove lockfile
	rm -f $copylockfile
	# send mail bath
    sendmailbatch
	exit 81;
fi
sleep 3
# message
echo "Target DB renamed"
# logfile
echo "Target DB renamed "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# message
echo "Truncate tables in target DB"
# logfile
echo "Truncate tables in target DB (messages with \"Unknown table name\" can be ignored) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# truncate tables in target db
for sql_deltable in "${sql_deltables[@]}"
do
 echo "truncate table "$sql_deltable >> /tmp/dbcopy_deltables.sql
 echo "//" >> /tmp/dbcopy_deltables.sql
done
scp /tmp/dbcopy_deltables.sql $targetsidadm@$targethost:/tmp/dbcopy_deltables.sql >> $dbcopylog
sshtarget 'sqlcli -U DEFAULT -f -i /tmp/dbcopy_deltables.sql' &>> $dbcopylog
sleep 3
sshsource 'rm /tmp/dbcopy_deltables.sql'
sshtarget 'rm /tmp/dbcopy_deltables.sql'
# message
echo "Tables in target DB truncated"
# logfile
echo "Tables in target DB truncated "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# message
echo "Delete source backup media"
# log
echo "Delete source backup media "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# delete backup media in source
sshsource 'dbmcli -d '$sourcesid' '"$dbmcliconnetsource"' backup_template_delete "'$sourcesid'"to"'$targetsid'" ' >> $dbcopylog
# exit status
if [ $? -ne 0 ];
 then
	# message
	echo "Error delete source backup media --> INFO"
	# logfile
	echo "Error delete source backup media --> INFO "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
fi
sleep 3
sshsource 'rm /tmp/dbcopy_tmpbacklist'
# message
echo "Source backup media deleted"
# logfile
echo "Source backup media deleted "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# message
echo "Delete target backup media"
# log
echo "Delete target backup media "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# delete restore media in target
sshtarget 'dbmcli -d '$targetsid' '"$dbmcliconnettarget"' backup_template_delete "'$sourcesid'"to"'$targetsid'" ' >> $dbcopylog
# exit status
if [ $? -ne 0 ];
 then
	# message
	echo "Error delete source backup media --> INFO"
	# logfile
	echo "Error delete source backup media --> INFO "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
fi
sleep 3
sshtarget 'rm /tmp/dbcopy_tmprestlist'
# message
echo "Target backup media deleted"
# logfile
echo "Target backup media deleted "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace

# message
echo "Delete PIPE"
# log
echo "Delete PIPE "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
# delete pipes
sshtarget 'rm /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_1'
sshtarget 'rm /tmp/'$sourcesid'to'$targetsid'_pipe_t_'$pipedate'_2'
sshsource 'rm /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_1'
sshsource 'rm /tmp/'$sourcesid'to'$targetsid'_pipe_s_'$pipedate'_2'
# message
echo "PIPE deleted"
# logfile
echo "PIPE deleted "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# function sleepandspace
sleepandspace


if [ $noexport -ne 1 ];
then
  if [ $autoimport == yes ];
  then
    # Import Tables
    # message
    echo "Import Tables for "$targetsid
    # logfile
    echo "Import Tables for "$targetsid $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
     if [ "$expcode" == '0000' ];
       then
	     # import tables
	     sshtarget 'cd '$exportlocation'; R3trans -w '$exportlocation'/'$targetsid'_dbcopy_exporttables_imp.log -i '$exportlocation'/'$targetsid'_dbcopy_exporttables.dat' >> $dbcopylog
	     sleep 3
	     sshtarget 'rm '$exportlocation'/'$targetsid'_dbcopy_exporttables.tpl; rm '$exportlocation'/'$targetsid'_dbcopy_exporttables_imp.log; rm '$exportlocation'/'$targetsid'_dbcopy_exporttables.log' >> $dbcopylog
	     if [ $remexpafterimp == yes ];
	     then
  	       sshtarget 'rm '$exportlocation'/'$targetsid'_dbcopy_exporttables.dat' >> $dbcopylog
	     else
	       sshtarget 'mv '$exportlocation'/'$targetsid'_dbcopy_exporttables.dat '$exportlocation'/'$targetsid'_dbcopy_exporttables.dat.save' >> $dbcopylog
	     fi
	     # message
	     echo "Tables for "$targetsid" imported"
	     # logfile
	     echo "Tables for "$targetsid" imported " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
       else
  	     # message
	     echo "No clean Table export for "$targetsid" found"
	     echo "Check Files "$exportlocation"/"$targetsid"_dbcopy_exporttables.tpl, "$exportlocation"/"$targetsid"_dbcopy_exporttables.dat and "$exportlocation"/"$targetsid"_dbcopy_exporttables.log on" $targethost 
	     # logfile
	     echo "No clean Table export for "$targetsid" found " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	     echo "Check Files "$exportlocation"/"$targetsid"_dbcopy_exporttables.tpl, "$exportlocation"/"$targetsid"_dbcopy_exporttables.dat and "$exportlocation"/"$targetsid"_dbcopy_exporttables.log on" $targethost >> $dbcopylog
     fi
    # function sleepandspace
    sleepandspace
  elif [ $autoimport == no ];
  then
    # message
    echo "Auto Import disabled for "$targetsid
	echo "To import the export use this command: R3trans -w "$exportlocation"/"$targetsid"_dbcopy_exporttables_imp.log -i "$exportlocation"/"$targetsid"_dbcopy_exporttables.dat on "$targethost" !"
    # logfile
    echo "Auto Import disabled for "$targetsid $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
	echo "To import the export use this command: R3trans -w "$exportlocation"/"$targetsid"_dbcopy_exporttables_imp.log -i "$exportlocation"/"$targetsid"_dbcopy_exporttables.dat on "$targethost" !" >> $dbcopylog
	# function sleepandspace
    sleepandspace
  fi
fi

# information for sapstart
echo "INFO: Please set rdisp/wp_no_btc = 0 and rdisp/wp_no_spo = 0 before start of the SAP system "$targetsid"!"
if [ $savesecdir == yes ];
then
  echo "INFO: SEC dir of "$targetsid" was saved to "$savesecdirpath" on "$targethost
  echo "INFO: SEC dir of "$targetsid" was saved to "$savesecdirpath" on "$targethost $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
fi

# function sleepandspace
sleepandspace

# END ###################################################################################################
# message
echo "Database-Copy created (RC=0)"
# logfile
echo "Database-Copy created (RC=0) "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog

# time and date
echo "===================================="	| tee -a $dbcopylog
echo "END DB COPY: " $(date "+%d.%m.%Y %H:%M:%S") & export endtime=$(date +%s)
echo "END DB COPY: " $(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog
echo "====================================" | tee -a $dbcopylog
export durationtime=$(($endtime - $starttime))
echo "Duration: $(($durationtime /3600)) h $(($durationtime % 3600 /60)) min $(($durationtime % 60)) sec"
echo "Duration: $(($durationtime /3600)) h $(($durationtime % 3600 /60)) min $(($durationtime % 60)) sec "$(date "+%d.%m.%Y %H:%M:%S") >> $dbcopylog 
echo "====================================" | tee -a $dbcopylog

# send mail
sendmailnormal

# remove lockfile
rm -f $copylockfile
sleep 2
exit 0
