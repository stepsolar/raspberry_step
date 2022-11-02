#bin/bash
#Required Unix tool bc & jq

###### MBMD SECTION #######
#insert MBMD local IP
readonly MBMD_IP="127.0.0.1:8080"
#insert MBMD ID of PhotoVoltaic Meter PRODUCTION POSITIVE VALUE
readonly MBMD_PV_ID="SDM1.1"
#insert MBMD ID of Grid Meter GRID POSITIVE VALUE FOR CONSUMED, NEGATIVE FOR RETURNED
readonly MBMD_GRID_ID="SDM1.2"

###### PV Output SECTION #######
#insert PV Output API Key (from https://pvoutput.org/account.jsp)
readonly PVOUTPUT_APIKEY=""
#insert PV Output System ID (from https://pvoutput.org/account.jsp)
readonly PVOUTPUT_SYSID=""
#insert "yes" to upload also production data from MBMD, "no" to upload only consumption
readonly UPLOAD_PROD="no"

readonly VAR_FILE="/tmp/INITIALVALUES"
readonly LOG_FILE="/tmp/MBMD2PVOutput.log"
echo "Start getting measurement from MBMD "$MBMD_IP" and upload to PVOutput "$PVOUTPUT_SYSID | sudo tee -a $LOG_FILE
echo "START TIME: "$(date +%R:%S) | sudo tee -a $LOG_FILE

[[ -f $VAR_FILE ]] && { [[ $(date -r $VAR_FILE +%F) == $(date +%F) ]] && source $VAR_FILE || rm -f $VAR_FILE; }

if ! [[ -f $VAR_FILE ]]; then
	CONSUMED=$(curl -s http://$MBMD_IP/api/last/$MBMD_GRID_ID | jq '.Import')
	echo "MBMD ENERGY CONSUMED: "$CONSUMED" Wh" | sudo tee -a $LOG_FILE
	RETURNED=$(curl -s http://$MBMD_IP/api/last/$MBMD_GRID_ID | jq '.Export')
	echo "MBMD ENERGY RETURNED: "$RETURNED" Wh" | sudo tee -a $LOG_FILE
	PV=$(curl -s http://$MBMD_IP/api/last/$MBMD_PV_ID | jq '.Import')
	echo "MBMD ENERGY PRODUCED: "$PV" Wh" | sudo tee -a $LOG_FILE
	TOTAL=$(bc -l <<<"$CONSUMED-$RETURNED+$PV")
	echo "MBMD ENERGY TOTAL BALANCE: "$TOTAL" Wh" | sudo tee -a $LOG_FILE
	PVOutputSTART=$(curl -s -d "d="$(date +%Y%m%d) -d "stats=1" -H "X-Pvoutput-Apikey: "$PVOUTPUT_APIKEY -H "X-Pvoutput-SystemId: "$PVOUTPUT_SYSID https://pvoutput.org/service/r2/getstatus.jsp)
	IFS=';' read -ra TEMP <<< "$PVOutputSTART"
	IFS=',' read -ra TEMP0 <<< "${TEMP[0]}"
	IFS=',' read -ra TEMP1 <<< "${TEMP[1]}"
	re='^[0-9]+$'
	if ! [[ $TEMP0 =~ $re ]] ; then
		PVOutputENERGY=0
	else
		PVOutputENERGY=${TEMP0}
	fi
	echo "PV Output ENERGY PRODUCED: "$PVOutputENERGY" Wh" | sudo tee -a $LOG_FILE
	if ! [[ $TEMP1 =~ $re ]] ; then
		PVOutputENERGYUSED=0
	else
		PVOutputENERGYUSED=${TEMP1}
	fi
	echo "PV Output ENERGY USED: "$PVOutputENERGYUSED" Wh" | sudo tee -a $LOG_FILE
	echo -e "TOTAL=$TOTAL\nPVOutputENERGY=$PVOutputENERGY\nPVOutputENERGYUSED=$PVOutputENERGYUSED\nPV=$PV" > $VAR_FILE
	echo "First Time of the day. Exit" | sudo tee -a $LOG_FILE
	exit 0
fi
echo -e "LAST TOTAL ENERGY COUNTER: "$TOTAL" Wh\nPVOutput ENERGY Production: "$PVOutputENERGY" Wh\nPVOutput ENERGY Used: "$PVOutputENERGYUSED" Wh" | sudo tee -a $LOG_FILE
CONSUMED_now=$(curl -s http://$MBMD_IP/api/last/$MBMD_GRID_ID | jq '.Import')
RETURNED_now=$(curl -s http://$MBMD_IP/api/last/$MBMD_GRID_ID | jq '.Export')
PV_now=$(curl -s http://$MBMD_IP/api/last/$MBMD_PV_ID | jq '.Import')
PV_POWER=$(curl -s http://$MBMD_IP/api/last/$MBMD_PV_ID | jq '.Power')
if [[ $PV_POWER =~ "-" ]]; then 
    PV_POWER=0
fi
GRID_POWER=$(curl -s http://$MBMD_IP/api/last/$MBMD_GRID_ID | jq '.Power')
VOLTAGE=$(curl -s http://$MBMD_IP/api/last/$MBMD_PV_ID | jq '.Voltage')
CONSUMPTION_POWER=$(bc -l <<<"$PV_POWER+$GRID_POWER")
TOTAL_now=$(bc -l <<<"($CONSUMED_now-$RETURNED_now+$PV_now)")
echo "TOTAL ENERGY COUNTER @"$(date +%R) $TOTAL_now" Wh" | sudo tee -a $LOG_FILE
ENERGY=$(bc -l <<<"(($TOTAL_now-$TOTAL)*1000+$PVOutputENERGYUSED)")
PV_ENERGY=$(bc -l <<<"($PV_now-$PV)*1000+$PVOutputENERGY")
printf "\e[1;34mData from MBMD @"$(date +%R:%S)"\n\e[0m" | sudo tee -a $LOG_FILE
echo "PV Power: "$PV_POWER" W" | sudo tee -a $LOG_FILE
echo "Cons Power: "$CONSUMPTION_POWER" W" | sudo tee -a $LOG_FILE
#printf "PV Energy now: %.1f Wh\n" $PV_ENERGY | sudo tee -a $LOG_FILE
#printf "Energy now: %.1f Wh\n" $ENERGY | sudo tee -a $LOG_FILE
if test "$UPLOAD_PROD" = "yes"; then
	curl -d "d="$(date +%Y%m%d) -d "t="$(date +%R) -d "v1="$PV_ENERGY -d "v2="$PV_POWER -d "v3="$ENERGY -d "v4="$CONSUMPTION_POWER -d "v6="$VOLTAGE -H "X-Pvoutput-Apikey: "$PVOUTPUT_APIKEY -H "X-Pvoutput-SystemId: "$PVOUTPUT_SYSID https://pvoutput.org/service/r2/addstatus.jsp | sudo tee -a $LOG_FILE
else
	curl -d "d="$(date +%Y%m%d) -d "t="$(date +%R) -d "v2="$PV_POWER -d "v3="$ENERGY -d "v4="$CONSUMPTION_POWER -d "v6="$VOLTAGE -H "X-Pvoutput-Apikey: "$PVOUTPUT_APIKEY -H "X-Pvoutput-SystemId: "$PVOUTPUT_SYSID https://pvoutput.org/service/r2/addstatus.jsp | sudo tee -a $LOG_FILE
fi
printf "\n" | sudo tee -a $LOG_FILE
echo -e "TOTAL=$TOTAL\nPVOutputENERGY=$PVOutputENERGY\nPVOutputENERGYUSED=$PVOutputENERGYUSED\nPV=$PV" > $VAR_FILE
