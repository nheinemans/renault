#!/bin/bash
# EDIT THE VARIABLES DOWN BELOW, MOVE THE FILE TO A RASPBERRY PI OR LINUX MACHNINE
# RUN THIS COMMAND TO INSTALL 'BC' "apt-get install bc" AND GIVE RENAULT.SH PERMISSIONS TO RUN "chmod 700 /home/renault/renault.sh" AND RUN IT
# Download https://github.com/jamesremuscat/pyze?fbclid=IwAR1KDSOIib6sIaQ1cGDUGKeNnceU2Kg1QICp1xUetomR6jFjONkjp1--CAc to /home/renault/
# Make a cronjob that runs every 5 minutes for /home/renault/renault.sh

vehicle=$VIN
IP="192.168.1.2"
PORT="8086"
curl="/usr/bin/curl"
FILE="/renault.txt"

# Get metrics from Renault API into temp file
echo "The renault.sh script has started and the data is being retrieved from Renault for vehicle VIN $vehicle."
/usr/local/bin/pyze status --vin $vehicle --km >> $FILE
if [[ $? -ne 0 ]]; then
  echo "ERROR: The Renault API is not working properly, no metrics received."
  exit 1
fi

# Battery related variables
batpercent=`cat $FILE | grep level | awk '{print $3}' | rev | cut -c2- | rev`
echo "Battery percentage: $batpercent"
energy=`cat $FILE | grep energy | awk '{print $3}' | rev | cut -c4- | rev`
echo "Energy available (kWh): $energy"
rangekm=`cat $FILE | grep estim | awk '{print $3}' | rev | cut -c3- | rev`
echo "Range (km): $rangekm"

# Temperature related variables
battemp=`cat $FILE | grep "Battery temp" | awk '{print $3}' | rev | cut -c4- | rev`
echo "Battery temperature: $battemp"
exttemp=`cat $FILE | grep "External temp" | awk '{print $3}' | rev | cut -c4- | rev`
echo "External temperature: $exttemp"

# Charging related variables
charging=`cat $FILE | grep "Charging state" | awk '{print $3}'`
echo "Charging state: $charging"
pluggedin=`cat $FILE | grep "Plug state" | awk '{print $3}'`
echo "Plugged state: $pluggedin"
remainingtime=`cat $FILE | grep remaining | awk '{print $3}' | awk -F: {'print $1*3600+$2*60'} `
echo "Remaining charging time (seconds): $remainingtime"

# Car related variables
gpslat=`cat $FILE | grep Location | awk '{print $2}' | awk -F, {'print $1'} `
gpslong=`cat $FILE | grep Location | awk '{print $2}' | awk -F, {'print $2'} `
echo "GPS location (long/lat): $gpslat,$gpslong"
mileage=`cat $FILE | grep mileage | awk '{print $3}' | rev | cut -c3- | rev`
echo "Milage (km): $mileage"

# Battery related variables to Influxdb
if [[ $batpercent =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "battery,vehicle=$vehicle percentage=$batpercent"
else
  echo "WARN: Battery percentage digit not found. No syncronization to InfluxDB."
fi
if [[ $energy =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "battery,vehicle=$vehicle energy=$energy"
else
  echo "WARN: Available energy digit not found. No syncronization to InfluxDB."
fi
if [[ $rangekm =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "battery,vehicle=$vehicle range=$rangekm"
else
  echo "WARN: Range not found. No syncronization to InfluxDB."
fi

# Temperature related variables to Influxdb
if [[ $battemp =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "temperature,vehicle=$vehicle batterytemp=$battemp"
else
  echo "WARN: Battery temperature digit not found. No syncronization to InfluxDB."
fi
if [[ $exttemp =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "temperature,vehicle=$vehicle externaltemp=$exttemp"
else
  echo "WARN: External temperature digit not found. No syncronization to InfluxDB."
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
  echo "WARN: Remaining time digit not found. No syncronization to InfluxDB."
fi

# Vehicle related variables to Influxdb
if [[ $gpslat =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "car,vehicle=$vehicle latitude=$gpslat,longitude=$gpslong"
else
  echo "WARN: GPS location not found. No syncronization to InfluxDB."
fi
if [[ $mileage =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "car,vehicle=$vehicle milage=$mileage"
else
  echo "WARN: Milage not found. No syncronization to InfluxDB."
fi
