#!/bin/sh

#remoteExe='echo'

#Get the options of command
while getopts "hv:l:r:" arg; do
  case $arg in
	h)	echo "ec2-backup [-h] [-l filter] [-r filter] [-v volume-id] dir"
		exit 1
		;;
	v)	volumeId=$OPTARG
		;;
	l)	localExe="$OPTARG"
		;;
	r)	remoteExe="${OPTARG} &&"
		;;
	?)	exit 1;;
    esac
done
#Redirect the option(folder)
tempNumber=`expr $OPTIND - 1`
shift  $tempNumber

#Get EC2_BACKUP_FLAGS_AWS and EC2_BACKUP_FLAGS_SSH
if [ ! -z "$EC2_BACKUP_FLAGS_SSH" ]; then
# homeFolder=`echo $HOME|tail -c +2|sed sed 's/\//\\\//g'`
 homeFolder=`echo $HOME|tail -c +2`
 flagssh=`echo $EC2_BACKUP_FLAGS_SSH|sed 's/ ~\// \/$homeFolder\//g'`
fi

if [ ! -z "$EC2_BACKUP_FLAGS_AWS" ]; then
  flagaws=$EC2_BACKUP_FLAGS_AWS
fi

#Calculate the target volume size.
#It is two times the size of the directory to be backup, and upper to integer
#For example: if the size of folder is 600MB, the size of volume is 2GB
volumeFoldersize=1
#Temporary Server is Ubuntu Server 16.04 LTS
instanceAMI="ami-43a15f3e"
volumeDevice='/dev/sdh'
volumeDeviceChar=`echo $volumeDevice|grep -o '.$'`
volumeFoldersizeorig=`du -s $1| awk '{print $1}'`
volumeFoldersizeorig=`expr $volumeFoldersizeorig \* 2`
if [ ! $? -eq 0 ]; then
  exit 1
fi
oneGB=`expr 1024 \* 1024`
if [ $volumeFoldersizeorig -gt $oneGB ]; then
  tempNumber=`expr $oneGB + $volumeFoldersizeorig `
  tempNUmber=`expr $tempNumber - 1`
  volumeFoldersize=`expr $tempNumber / $oneGB` 
fi
if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
  echo "Complete volume size calculation. Volume size is $volumeFoldersize."
fi
#Create instance
#If volume id is provided, get the zone of volume and create new instance on the same zone
#else create new instance directly
if [ ! -z "$volumeId" ]; then
#Get volume's zone 
  volumeRegion=`aws ec2 describe-volumes --volume-ids $volumeId|grep AvailabilityZone|awk '{print $2}'|tr -d "\","`
  if [ ! $? -eq 0 ]; then
    exit 1
  fi
#Get related subnetId
  subnetId=`aws ec2  describe-subnets --filters Name=availabilityZone,Values=$volumeRegion --query 'Subnets[*].SubnetId' --output text`
  if [ ! $? -eq 0 ]; then
    exit 1
  fi
#create new instance on the same zone
  instanceId=`aws ec2 run-instances $flagaws --image-id $instanceAMI --subnet-id $subnetId|grep InstanceId|tr ",\"\n" " "|awk '{print $3}'`
  if [ ! $? -eq 0 ]; then
    exit 1
  fi
	if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
    echo "$volumeId is specified. Complete creating new instance $instanceId with this volumeId."
		echo "Waiting for instance preparation..."
  fi
else
#create new instance directly if volume is not specified
  instanceId=`aws ec2 run-instances $flagaws --image-id $instanceAMI --block-device-mappings "{\"DeviceName\": \"$volumeDevice\",\"Ebs\": {\"VolumeSize\": $volumeFoldersize}}"|grep InstanceId|tr ",\"\n" " "|awk '{print $3}'`
  if [ ! $? -eq 0 ]; then
    exit 1
  fi
  if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
    echo "Complete new instance $instanceId creation with new volume on $volumeDevice."
    echo "Waiting for instance preparation..."
  fi
fi

#Wait for the server boot. At least 50 seconds
for i in $(seq 1 100); 
do
  result=`aws ec2 describe-instance-status --instance-ids $instanceId|tr -d "\n\""|awk '{print $14}'`
  if [ ! $? -eq 0 ]; then
    exit 1
  fi
#If the status is running after 20 seconds,it looks good. But still wait for 30 seconds
  if [ $i -gt 20 ] && [  $result = "running" ]; then 
   #Attach volume if it is specified
    if [ ! -z "$volumeId" ]; then
      result=`aws ec2 attach-volume --device $volumeDevice --instance-id $instanceId --volume-id $volumeId`
      if [ ! $? -eq 0 ]; then
        exit 1
      fi
      if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
        echo "Complete volume $volumeId attachment. Keep waiting for instance preparation..."
      fi
    fi
    for j in $(seq 1 30);
    do
     sleep 1
    done
    break
  fi
  sleep 1
done

#Get the volumeId
volumeId=`aws ec2 describe-volumes  --filters Name=attachment.device,Values=$volumeDevice Name=attachment.instance-id,Values=$instanceId --query 'Volumes[*].{ID:VolumeId}'  --output text`
if [ ! $? -eq 0 ]; then
  exit 1
fi

#Get the instance public IP
instanceIp=`aws ec2 describe-instances --filters Name=instance-id,Values=$instanceId --query "Reservations[*].Instances[*].PublicIpAddress"  --output=text`
if [ ! $? -eq 0 ]; then
   exit 1
fi
if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
  echo "Instance is ready.Public IP address is $instanceIp"
fi

#Try to connect the server at first. Avoid unnecessary output (-q)
ssh $flagssh -o StrictHostKeyChecking=no -q ubuntu@$instanceIp "exit" >/dev/null

#Get the fdisk status of volume
result=`ssh $flagssh -o StrictHostKeyChecking=no  ubuntu@$instanceIp "sudo fdisk -l|grep xvd${volumeDeviceChar}"`
if [  $? -gt 1 ]; then
  exit 1
fi
#If the volume partition does not exist, exit 
if [ -z "$result" ]; then
  if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
    echo "Not find the volume"
  fi
  exit 2
fi
if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
  echo "Target volume is loaded successfully."
fi
#Start backup
if [ -z "$localExe" ]; then
  result=`tar cPf - $1|ssh $flagssh -o StrictHostKeyChecking=no  ubuntu@$instanceIp "$remoteExe  sudo dd of=/dev/xvd${volumeDeviceChar}" 2>&1`
else
  result=`tar cPf - $1|${localExe}|ssh $flagssh -o StrictHostKeyChecking=no  ubuntu@$instanceIp "$remoteExe sudo dd of=/dev/xvd${volumeDeviceChar}" 2>&1`
fi
if [ ! $? -eq 0 ]; then
   exit 1
fi
if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
  echo "Complete backup."
fi
#Complete backup. Stop instance, detach volume, terminate instance
result=`aws ec2 stop-instances --instance-ids $instanceId|grep stopping|tr -d "\""|awk '{print $2}'`
if [ ! $? -eq 0 ]; then
   exit 1
fi
if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
  echo "Stopping the instance..."
fi

sleep 10
result=`aws ec2 detach-volume --volume-id $volumeId|grep State|tr -d ",\""|awk '{print $2}'`
if [ ! $? -eq 0 ]; then
   exit 1
fi
if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
  echo "Detach volume."
fi

result=`aws ec2 terminate-instances --instance-ids $instanceId|grep -E 'shutting-down|terminated'|tr -d "\""|awk '{print $2}'`
if [ ! $? -eq 0 ]; then
   exit 1
fi
if [ ! -z "$EC2_BACKUP_VERBOSE" ]; then
  echo "Terminating instance..."
	echo "Local $1 is backup to below vloume:"
fi

#Return volumeId
echo $volumeId
exit 0
