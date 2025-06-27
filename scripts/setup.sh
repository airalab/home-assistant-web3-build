#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get mqtt password
source $SCRIPT_DIR/raw_passwd_mqtt.txt

echo "this script will create all necessary repositories and start docker containers"

# set to false if you don't want to start Zigbee2MQTT container
Z2MENABLE=true

# Check if Zigbee dongle is connected
if [ -d /dev/serial/by-id/ ]; then
  # If device exists
  if [ "$(ls -A /dev/serial/by-id/)" ]; then
    echo "the Zigbee coordinator is installed"
    # Count how many devices are connected
    NUMB=$(ls -1q /dev/serial/by-id/ | wc -l)

    if (($NUMB > 1)); then
      echo "You have more than 1 connected device, which seems to be a Zigbee coordinator. Please choose one:"
      select f in /dev/serial/by-id/*; do
        test -n "$f" && break
        echo ">>> Invalid Selection"
      done
      echo "You select $f"
      Z2MPATH=$f
    else
      Z2MPATH=$(ls /dev/serial/by-id/)
      Z2MPATH="/dev/serial/by-id/"$Z2MPATH
    fi

  else
    echo "Cannot find Zigbee coordinator location. Please insert it and run script again."
    echo "Do you want to continue without Zigbee coordinator? It will not start Zigbee2MQTT container."
    while true; do
        read -p "Do you want to proceed? (Y/n) " yn
        case $yn in
	          [yY]| "" ) echo Ok, proceeding without Zigbee coordinator;
	            Z2MENABLE=false
		          break;;
	          [nN] ) echo exiting...;
		          exit;;
	          * ) echo invalid response;;
        esac
    done
    Z2MPATH="."
  fi
else
    echo "Cannot find zigbee coordinator location. Please insert it and run script again. The directory "/dev/serial/by-id/" does not exist"
    echo "Do you want to continue without zigbee coordinator? It will not start Zigbee2MQTT container."
    while true; do
        read -p "Do you want to proceed? (Y/n) " yn
        case $yn in
	          [yY]| "" ) echo ok, we will proceed;
	            Z2MENABLE=false
		          break;;
	          [nN] ) echo exiting...;
		          exit;;
	          * ) echo invalid response;;
        esac
    done
    Z2MPATH="."
fi
export Z2MPATH
echo "Z2M path is - $Z2MPATH"

# check .env file
if [[ -f $SCRIPT_DIR/../.env ]]
then
  echo ". env file exists"
else
  echo ".env file does not exist. Exit"
  exit 1
fi

source $SCRIPT_DIR/../.env

# Check the last symbol in path. if it is "/", then delete it.
LAST_SYMBOL=${CONFIG_PATH: -1}
if [ "$LAST_SYMBOL" = "/" ]; then
  CONFIG_PATH="${CONFIG_PATH%?}"
fi

# grap version of packages
source $SCRIPT_DIR/../src/packages.env

# save current path to return later
CURRENT_PATH=$(pwd)

if [[ $CONFIG_PATH == "./configs" ]]; then
  if [[ ! -d $SCRIPT_DIR/../configs ]]; then
    mkdir -p $SCRIPT_DIR/../configs
  fi
fi

if [[ -d $CONFIG_PATH ]]
then
  cd $CONFIG_PATH
  echo "config path - $CONFIG_PATH"
else
  echo "config directory does not exist. Exit"
  exit 1
fi

#zigbee2mqtt
mkdir -p "zigbee2mqtt/data"

echo "# Home Assistant integration (MQTT discovery)
homeassistant: true

# allow new devices to join
permit_join: false

# MQTT settings
mqtt:
  # MQTT base topic for zigbee2mqtt MQTT messages
  base_topic: zigbee2mqtt
  # MQTT server URL
  server: 'mqtt://localhost'
  # MQTT server authentication, uncomment if required:
  user: connectivity
  password: $MOSQUITTO_PASSWORD

advanced:
  channel: $ZIGBEE_CHANNEL
  last_seen: 'ISO_8601'

availability:
  enabled: true

frontend:
  enable: true
  # Optional, default 8080
  port: 8099

# Serial settings
serial:
  # Location of CC2531 USB sniffer
  port: /dev/ttyACM0

" | tee ./zigbee2mqtt/data/configuration.yaml


# home assistant config setup

if [[ -d ./homeassistant/.storage ]]
then
  echo "homeassistant/.storage directory already exist"
else
  mkdir -p "homeassistant/.storage"

  # mqtt integration
  echo "{
    \"version\": 1,
    \"minor_version\": 1,
    \"key\": \"core.config_entries\",
    \"data\": {
      \"entries\": [
        {
          \"entry_id\": \"92c28c246bb8163e5cc9e6dc5b5d8606\",
          \"version\": 1,
          \"domain\": \"mqtt\",
          \"title\": \"localhost\",
          \"data\": {
            \"broker\": \"localhost\",
            \"port\": 1883,
            \"username\": \"connectivity\",
            \"password\": \"$MOSQUITTO_PASSWORD\",
            \"discovery\": true,
            \"discovery_prefix\": \"homeassistant\"
          },
          \"options\": {},
          \"pref_disable_new_entities\": false,
          \"pref_disable_polling\": false,
          \"source\": \"user\",
          \"unique_id\": null,
          \"disabled_by\": null
        }
      ]
    }
  }
  " | tee ./homeassistant/.storage/core.config_entries

fi

# create homeassistant/custom_components repository
if [[ -d ./homeassistant/custom_components ]]
then
  echo "homeassistant/custom_components directory already exist"
else
  mkdir -p "homeassistant/custom_components"

  #download robonomics integration and unpack it
  wget https://github.com/airalab/homeassistant-robonomics-integration/archive/refs/tags/$ROBONOMICS_VERSION.zip &&
  unzip $ROBONOMICS_VERSION.zip &&
  mv homeassistant-robonomics-integration-$ROBONOMICS_VERSION/custom_components/robonomics ./homeassistant/custom_components/ &&
  rm -r homeassistant-robonomics-integration-$ROBONOMICS_VERSION &&
  rm $ROBONOMICS_VERSION.zip
fi

# return to the directory with compose
cd $CURRENT_PATH

# at the end save Z2Mpath to env file for use in the update script
echo "" >> $SCRIPT_DIR/../.env
echo "Z2MENABLE=$Z2MENABLE" >> $SCRIPT_DIR/../.env
echo "" >> $SCRIPT_DIR/../.env
echo "Z2MPATH=$Z2MPATH" >> $SCRIPT_DIR/../.env
