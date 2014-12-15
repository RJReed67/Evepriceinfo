#!/usr/bin/bash
#set environment
logfile=/opt/evepriceinfo/logs/restart.log
#PID=`pgrep -f "Evepriceinfo.pl"`
PID=`pgrep -f "epi_main.pl"`
if [ -z "$PID" ]
then
/etc/rc.d/rc.local
echo "Started Process at `date`" >> $logfile
fi
