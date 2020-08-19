#!/bin/bash
# EDIT THE VARIABLES DOWN BELOW, MOVE THE FILE TO A RASPBERRY PI OR LINUX MACHNINE
# RUN THIS COMMAND TO INSTALL 'BC' "apt-get install bc" AND GIVE RENAULT.SH PERMISSIONS TO RUN "chmod 700 /home/renault/renault.sh" AND RUN IT
# Download https://github.com/jamesremuscat/pyze?fbclid=IwAR1KDSOIib6sIaQ1cGDUGKeNnceU2Kg1QICp1xUetomR6jFjONkjp1--CAc to /home/renault/
# Make a cronjob that runs every 5 minutes for /home/renault/renault.sh

date

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
source home.sh

deg2rad () {
        bc -l <<< "$1 * 0.0174532925"
}

rad2deg () {
        bc -l <<< "$1 * 57.2957795"
}

acos () {
        pi="3.141592653589793"
        bc -l <<<"$pi / 2 - a($1 / sqrt(1 - $1 * $1))"
}

distance () {
        lat_1="$1"
        lon_1="$2"
        lat_2="$3"
        lon_2="$4"
        delta_lat=`bc <<<"$lat_2 - $lat_1"`
        delta_lon=`bc <<<"$lon_2 - $lon_1"`
        lat_1="`deg2rad $lat_1`"
        lon_1="`deg2rad $lon_1`"
        lat_2="`deg2rad $lat_2`"
        lon_2="`deg2rad $lon_2`"
        delta_lat="`deg2rad $delta_lat`"
        delta_lon="`deg2rad $delta_lon`"

        distance=`bc -l <<< "s($lat_1) * s($lat_2) + c($lat_1) * c($lat_2) * c($delta_lon)"`
        distance=`acos $distance`
        distance="`rad2deg $distance`"
        distance=`bc -l <<< "$distance * 60 * 1.85200"`
        distance=`bc <<<"scale=4; $distance / 1"`
        echo $distance
}

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
charging=`cat $FILE | grep "^Charging state" | awk '{$1=$2=""; print $0}' | sed 's/^ *//g'`
echo "INFO: Charging state: $charging"
pluggedin=`cat $FILE | grep "^Plug state" | awk '{$1=$2=""; print $0}' | sed 's/^ *//g'`
echo "INFO: Plugged state: $pluggedin"
remainingtime=`cat $FILE | grep "^Time remaining" | awk '{print $3}' | awk -F: {'print $1*3600+$2*60'} `
echo "INFO: Remaining charging time (seconds): $remainingtime"
chargerate=`cat $FILE | grep "^Charge rate" | sed 's/[^0-9.]*//g'`
echo "INFO: Charge rate (kW): $chargerate"

# Car related variables
gpslat=`cat $FILE | grep Location | awk '{print $2}' | awk -F, {'print $1'} `
gpslong=`cat $FILE | grep Location | awk '{print $2}' | awk -F, {'print $2'} `
echo "INFO: GPS location (lat/long): $gpslat,$gpslong"
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
if [[ $charging = "Charging" ]]
then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle charging=1"
  if [[ $remainingtime =~ [0-9] ]];then
    $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle remainingtime=$remainingtime"
  fi
  if [[ $chargerate =~ [0-9] ]];then
    $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle chargerate=$chargerate"
  fi
else
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle charging=0"
fi
if [[ $pluggedin = "Unplugged" ]]
then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle pluggedin=0"
else
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "charging,vehicle=$vehicle pluggedin=1"
fi

# Vehicle related variables to Influxdb
if [[ $gpslat =~ [0-9] ]];then
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "car,vehicle=$vehicle latitude=$gpslat,longitude=$gpslong"
  if [[ $gpslong = $homelong ]] && [[ $gpslat = $homelat ]]; then
    fromhome=0
  else
    if [[ $homelat =~ [0-9] ]] && [[ $homelong =~ [0-9] ]];then
      fromhome=`distance $gpslong $gpslat $homelong $homelat`
	else
	  fromhome=0
	fi
  fi
  echo "INFO: Distance from home (km): $fromhome"
  $curl -XPOST http://$IP:$PORT/write?db=renault --data-binary "car,vehicle=$vehicle fromhome=$fromhome"
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
