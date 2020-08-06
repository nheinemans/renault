#!/bin/bash
# EDIT THE VARIABLES DOWN BELOW, MOVE THE FILE TO A RASPBERRY PI OR LINUX MACHNINE
# RUN THIS COMMAND TO INSTALL 'BC' "apt-get install bc" AND GIVE RENAULT.SH PERMISSIONS TO RUN "chmod 700 /home/renault/renault.sh" AND RUN IT
# Download https://github.com/jamesremuscat/pyze?fbclid=IwAR1KDSOIib6sIaQ1cGDUGKeNnceU2Kg1QICp1xUetomR6jFjONkjp1--CAc to /home/renault/
# Make a cronjob that runs every 5 minutes for /home/renault/renault.sh

echo "INFO: Looking up vehicle with registration $REG in your Renault account."
VIN=`pyze vehicles | grep $REG | awk {'print $NF'} | sed "s/.//;s/.$//"`
if [[ $? -ne 0 ]]; then
  echo "ERROR: The Renault API is not working properly, could not get VIN number for vehicle $REG."
  exit 1
fi
vehicle=$REG
IP="192.168.1.2"
PORT="8086"
curl="/usr/bin/curl"
FILE="/renault.txt"

# Get metrics from Renault API into temp file
echo "INFO: Retrieving data from Renault for vehicle $vehicle with VIN $VIN"
/usr/local/bin/pyze status --vin $VIN --km > $FILE
if [[ $? -ne 0 ]]; then
  echo "ERROR: The Renault API is not working properly, no metrics received."
  exit 1
fi

# Battery related variables
batpercent=`cat $FILE | grep "^Battery level" | sed 's/[^0-9.]*//g'`
echo "INFO: Battery percentage: $batpercent"
energy=`cat $FILE | grep "^Available energy" | sed 's/[^0-9.]*//g'`
echo "INFO: Energy available (kWh): $energy"
rangekm=`cat $FILE | grep "^Range estimate" | sed 's/[^0-9.]*//g'`
echo "INFO: Range (km): $rangekm"

# Temperature related variables
battemp=`cat $FILE | grep "^Battery temperature" | sed 's/[^0-9.]*//g'`
echo "INFO: Battery temperature: $battemp"
exttemp=`cat $FILE | grep "^External temperature" | sed 's/[^0-9.]*//g'`
echo "INFO: External temperature: $exttemp"

# Charging related variables
charging=`cat $FILE | grep "Charging state" | awk '{print $3}'`
echo "INFO: Charging state: $charging"
pluggedin=`cat $FILE | grep "Plug state" | awk '{print $3}'`
echo "INFO: Plugged state: $pluggedin"
remainingtime=`cat $FILE | grep "^Time remaining" | awk '{print $3}' | awk -F: {'print $1*3600+$2*60'} `
echo "INFO: Remaining charging time (seconds): $remainingtime"
chargerate=`cat $FILE | grep "^Charge rate" | sed 's/[^0-9.]*//g'`
echo "INFO: Charge rate (kW): $chargerate"

# Car related variables
gpslat=`cat $FILE | grep Location | awk '{print $2}' | awk -F, {'print $1'} `
gpslong=`cat $FILE | grep Location | awk '{print $2}' | awk -F, {'print $2'} `
echo "INFO: GPS location (long/lat): $gpslat,$gpslong"
mileage=`cat $FILE | grep "^Total mileage" | sed 's/[^0-9.]*//g'`
echo "INFO: Mileage (km): $mileage"
acstate=`cat $FILE | grep "AC state" | awk '{print $3}'`
echo "INFO: AC state: $acstate"

# Battery related variables to Influxdb
if [[ $batpercent =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "battery,vehicle=$vehicle percentage=$batpercent"
else
  echo "WARN: Battery percentage digit not found. No sync to InfluxDB."
fi
if [[ $energy =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "battery,vehicle=$vehicle energy=$energy"
else
  echo "WARN: Available energy digit not found. No sync to InfluxDB."
fi
if [[ $rangekm =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "battery,vehicle=$vehicle range=$rangekm"
else
  echo "WARN: Range not found. No sync to InfluxDB."
fi

# Temperature related variables to Influxdb
if [[ $battemp =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "temperature,vehicle=$vehicle batterytemp=$battemp"
else
  echo "WARN: Battery temperature digit not found. No sync to InfluxDB."
fi
if [[ $exttemp =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "temperature,vehicle=$vehicle externaltemp=$exttemp"
else
  echo "WARN: External temperature digit not found. No sync to InfluxDB."
fi

# Charging related variables to Influxdb
if [ $charging = "Not" ]
then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle charging=0"
else
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle charging=1"
fi
if [ $pluggedin = "Unplugged" ]
then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle pluggedin=0"
else
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle pluggedin=1"
fi
if [[ $remainingtime =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle remainingtime=$remainingtime"
else
  echo "WARN: Remaining time digit not found. No sync to InfluxDB."
fi
if [[ $chargerate =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle chargerate=$chargerate"
else
  echo "WARN: Charge rate digit not found. No sync to InfluxDB."
fi

# Vehicle related variables to Influxdb
if [[ $gpslat =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "car,vehicle=$vehicle latitude=$gpslat,longitude=$gpslong"
else
  echo "WARN: GPS location not found. No sync to InfluxDB."
fi
if [[ $mileage =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "car,vehicle=$vehicle mileage=$mileage"
else
  echo "WARN: Mileage not found. No sync to InfluxDB."
fi
if [[ $acstate = "off" ]]
then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "car,vehicle=$vehicle acstate=0"
else
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "car,vehicle=$vehicle acstate=1"
fi
