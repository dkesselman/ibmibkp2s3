#!/QOpenSys/pkgs/bin/bash

# Initialize variables and contants #
PASE_FORK_JOBNAME='BKP2S3'
export PASE_FORK_JOBNAME
#
dt=$(date '+%Y%m%d');
host=$(hostname);
s3cmd='/QOpenSys/pkgs/bin/aws s3 --profile icos-dal --endpoint-url=https://s3.us-south.cloud-object-storage.appdomain.cloud ';
bucket='s3://mybackups/'$host'-'$dt'/';
IMGCLG='BKP2S3';
IMGCLGPATH='/'$IMGCLG;
CSVFILE=$IMGCLGPATH'/'$IMGCLG'.csv'
CSVFILEZ=$CSVFILE'*'
IMGSIZ=50000;
TAPEPREFIX='BKP';
TapeQty=10
BKP2S3LOG=$IMGCLGPATH'/'$IMGCLG'_'$dt'.log';
num_procs=3

#==================== Functions ==========================#
function CLEANDIR(){
# Unload Virtual Tape Device
echo 'Unload Virtual Tape Device' >> $BKP2S3LOG
system "LODIMGCLG IMGCLG($IMGCLG) OPTION(*UNLOAD)" >> $BKP2S3LOG

# Remove Image Catalog virtual cartridges
CLEANIMGCLG 

# Remove compressed cartridges 
cd $IMGCLGPATH
rm *.zst >> $BKP2S3LOG
}
#=========================================================#
function CLEANIMGCLG(){
# Remove Image Catalog virtual cartridges
echo 'Remove virtual cartridges' >> $BKP2S3LOG 
for ((TN=1;TN<=TapeQty;TN++))
do
    system "RMVIMGCLGE IMGCLG($IMGCLG) IMGCLGIDX($TN) KEEP(*NO)" >> $BKP2S3LOG
done
}
#=========================================================#
function INITIMGCLG(){
# Add Virtual Cartridges to IMAGE CATALOG
for ((TN=1;TN<=TapeQty;TN++))
do
  CARTRIDGE=$TAPEPREFIX$(printf '%02d' $TN);
  system "ADDIMGCLGE IMGCLG($IMGCLG) FROMFILE(*NEW) TOFILE($CARTRIDGE) IMGSIZ($IMGSIZ) VOLNAM($CARTRIDGE) TEXT('Virtual Tape - Respaldo semanal a S3')" >> $BKP2S3LOG
done
}
#=========================================================#
function LOADVTDEV(){
system "LODIMGCLG IMGCLG($IMGCLG) DEV(VTAP01)" >> $BKP2S3LOG 
error=$?
echo $error >> $BKP2S3LOG 
if [ $error -ne 0 ]; then
	errmsg="BACKUP TO S3 Cloud - Error loading Virtual Tape Device - Unable to fix!";
	system "SNDMSG MSG('"$errmsg"') TOUSR(*SYSOPR)";
	echo $errmsg >> $BKP2S3LOG;
	MAILERROR 
	# Exitig the backup program #
	exit 1
fi 
}
#=========================================================#
function MAILERROR()
{
# Use here your email notifications
	echo "";
}
#=========================================================#
function BACKUPSTR(){
# Start the backup
echo 'Backup Starting' >> $BKP2S3LOG
date >> $BKP2S3LOG

# Security
echo 'SAVSECDTA' >> $BKP2S3LOG
system "SAVSECDTA DEV(VTAP01) ENDOPT(*LEAVE) OUTPUT(*OUTFILE) OUTFILE(ESSELWARE/$IMGCLG)" >> $BKP2S3LOG
# Configuration
echo 'SAVCFG' >> $BKP2S3LOG
system "SAVCFG DEV(VTAP01) ENDOPT(*LEAVE) OUTPUT(*OUTFILE) OUTFILE(ESSELWARE/$IMGCLG) OUTMBR(*FIRST *ADD)" >> $BKP2S3LOG
# *IBM Libraries
echo 'SAVLIB *IBM' >> $BKP2S3LOG
date >> $BKP2S3LOG
system "SAVLIB LIB(*IBM) DEV(VTAP01) ENDOPT(*LEAVE) SAVACT(*LIB) SAVACTWAIT(20) SAVACTMSGQ(DKESSELMAN) OUTPUT(*OUTFILE) OUTFILE(ESSELWARE/$IMGCLG) OUTMBR(*FIRST *ADD)" >> $BKP2S3LOG
# *ALLUSR Libraries
echo 'SAVLIB *ALLUSR'>> $BKP2S3LOG
date >> $BKP2S3LOG
system "SAVLIB LIB(*ALLUSR) DEV(VTAP01) ENDOPT(*LEAVE) SAVACT(*SYSDFN) SAVACTWAIT(20) SAVACTMSGQ(DKESSELMAN) OMITLIB(QUSRBRM) OUTPUT(*OUTFILE) OUTFILE(ESSELWARE/$IMGCLG) OUTMBR(*FIRST *ADD)" >> $BKP2S3LOG
bkperr=$?;
# Unload Virtual Tape Device
system "LODIMGCLG IMGCLG($IMGCLG) OPTION(*UNLOAD)" >> $BKP2S3LOG

# Save backup *OUTFILE
cd $IMGCLGPATH

rm $CSVFILE >> $BKP2S3LOG
rm $CSVFILEZ >> $BKP2S3LOG
# Export the CSV File "
touch $CSVFILE >> $BKP2S3LOG
system "CPYTOIMPF FROMFILE(ESSELWARE/$IMGCLG) TOSTMF('$CSVFILE') MBROPT(*REPLACE) STMFCCSID(*STMF) RCDDLM(*CRLF) DATFMT(*ISO) TIMFMT(*JIS) ADDCOLNAM(*SYS)" >> $BKP2S3LOG
# Compress CSV #
/QOpenSys/pkgs/bin/zstd $CSVFILE >> $BKP2S3LOG
}
#=========================================================#
function VTAPS3UP(){
# Change *BASE pool activity level
system "CHGSHRPOOL POOL(*BASE) ACTLVL(10000)"
# Upload CSV file 
CSVFILEZ=$CSVFILE'.zst'
$s3cmd cp $CSVFILEZ $bucket 

# Upload Virtual Cartridges to S3 Bucket
echo 'Uploading to S3' >> $BKP2S3LOG
FILES='*.zst';
# Set child jobs name
PASE_FORK_JOBNAME='BKP2S3UP'
for ZSTDFILE in $FILES
do
	
	$s3cmd cp $ZSTDFILE $bucket 
# Parallel upload is disabled #	
#    $s3cmd cp $ZSTDFILE $bucket &
#	if [[ $(jobs -r -p | wc -l) -ge $num_procs ]]; then
#		wait -n
#    fi
done
# Wait for the last submited processes #
#wait

# Listing backup directory and cloud bucket content to LOG #
echo ' ------ Listing backups before upload ------' >> $BKP2S3LOG
ls -l *.zst                                         >> $BKP2S3LOG
echo ' ------ Listing S3 content -----------------' >> $BKP2S3LOG
$s3cmd ls $bucket  >> $BKP2S3LOG
echo ' -------------------------------------------' >> $BKP2S3LOG

date >> $BKP2S3LOG
}
#=========================================================#
function VTAPZIP(){
# Change *BASE pool activity level
system "CHGSHRPOOL POOL(*BASE) ACTLVL(10000)"
# Compress Virtual Tape images #
echo 'Compressing Virtual Cartridges...' >> $BKP2S3LOG
date >> $BKP2S3LOG

TAPEZ=$TAPEPREFIX'*.zst'
TAPE=$TAPEPREFIX'*'

rm $TAPEZ >> $BKP2S3LOG
# Set child jobs name
PASE_FORK_JOBNAME='BKP2S3Z'

for VTAPEFILE in $TAPE
do
	/QOpenSys/pkgs/bin/zstd $VTAPEFILE >> $BKP2S3LOG &
	if [[ $(jobs -r -p | wc -l) -ge $num_procs ]]; then
		wait -n
    fi
done
# Wait for the last submited processes #
wait

date >> $BKP2S3LOG
}
#=========================================================#

#######################################################
# Email - Backup starts                               #
##NOTE='Backup Starts;
##RCP1='user1@emailaddress.com';
##RCP2='user2@emailaddress.com';
##RCP3='user3@emailaddress.com';
##RCP4='user4@emailaddress.com';
##SUBJECT='Backup starts - S3 - CLOUD';
##system "SNDSMTPEMM RCP(('$RCP1') ('$RCP2') ('$RCP3') ('$RCP4')) SUBJECT('$SUBJECT') NOTE('$NOTE')"
#######################################################
system "SNDMSG MSG('Backup to S3 Starts') TOUSR(*SYSOPR)";

date > $BKP2S3LOG 

# Clean directory
CLEANDIR

# Add Virtual Cartridges to IMAGE CATALOG
INITIMGCLG

# Load Virtual Tape Device
LOADVTDEV

# Backup security and Libraries *IBM and *ALLUSR #
BACKUPSTR

# Compress Virtual Cartridge
VTAPZIP

# Upload cartridges and CSV file with content to S3 bucket #
VTAPS3UP

PASE_FORK_JOBNAME='BKP2S3'

# Remove Image Catalog virtual cartridges
CLEANIMGCLG

date >> $BKP2S3LOG
echo '==================== The End! ==========================' >> $BKP2S3LOG

# Upload the log
/QOpenSys/pkgs/bin/zstd $BKP2S3LOG
BKP2S3LOGZ=$BKP2S3LOG'.zst'
$s3cmd cp $BKP2S3LOGZ  $bucket

# Change attributes to avoid backing up the backup
system "CHGATR OBJ('$IMGCLGPATH') ATR(*ALWSAV) VALUE(*NO) SUBTREE(*ALL)"

# Email - Sends the backup log #
##ATTACH=$BKP2S3LOGZ;
##NOTE='Backup has finished;
##RCP1='user1@emailaddress.com';
##RCP2='user2@emailaddress.com';
##RCP3='user3@emailaddress.com';
##RCP4='user4@emailaddress.com';
##SUBJECT='Backup has finished - S3 - CLOUD';
##system "SNDSMTPEMM RCP(('$RCP1') ('$RCP2') ('$RCP3') ('$RCP4')) SUBJECT('$SUBJECT') NOTE('$NOTE')   ATTACH(('$ATTACH' *OCTET *BIN))";
system "SNDMSG MSG('Backup Ends') TOUSR(*SYSOPR)";
#==================== Backup End  ==========================#

exit

#==================== PROGRAM END ========================#
