#!/bin/bash -e

HCS="uhci ohci ehci xhci"
DEVS="mouse kbd tablet tmon"
TESTS="disconnect offline_disconnect offline_online_disconnect"

STARTUP_DELAY="5"
CONNECT_DELAY="1"
DISCONNECT_DELAY="1"
OFFLINE_DELAY="2"

QEMU_BIN_PATH="../qemu/build/"
QEMU_PATH="../qemu/"
REPORT_PATH="./disconnect_test/"

mkdir -p $REPORT_PATH

get_keys() {
	CHAR=$1; shift
	case "$CHAR" in
	" ")
		KEYCODES="spc"
		;;
	".")
		KEYCODES="dot"
		;;
	"/")
		KEYCODES="slash"
		;;
	":")
		KEYCODES="shift semicolon"
		;;
	"-")
		KEYCODES="minus"
		;;
	";")
		KEYCODES="ret"
		;;
	*)
		KEYCODES="$CHAR"
		;;
	esac

	COMMA=""
	for KEYCODE in $KEYCODES; do
		echo "$COMMA{\"type\":\"qcode\",\"data\":\"$KEYCODE\"}"
		COMMA=","
	done
}

qemu_run() {
	HC=$1; shift
	LOG_FILE=$1; shift

	echo "[  run qemu] $HC" >&2
	case "$HC" in
	"uhci")
		HC_FLAGS="-usb"
		;;
	"ohci")
		HC_FLAGS="-device pci-ohci,id=hc"
		;;
	"ehci")
		HC_FLAGS="-device usb-ehci,id=hc"
		;;
	"xhci")
		HC_FLAGS="-device nec-usb-xhci,id=hc"
		;;
	*)
		echo "Unknown HC: $HC"
		exit 1
		;;
	esac

	exec $QEMU_BIN_PATH/x86_64-softmmu/qemu-system-x86_64 \
		-qmp unix:${SOCKET_FILE},server,nowait \
		-serial stdio \
		-boot d \
		-cdrom image.iso \
		$HC_FLAGS \
		-enable-kvm >$LOG_FILE 2>&1
}

qemu_add() {
	DEV_ID="dev-$1"; shift
	DEV_DRIVER="usb-$1"; shift
	echo "[   connect] $DEV_ID ($DEV_DRIVER)" >&2
	echo "device_add driver=$DEV_DRIVER id=$DEV_ID"
}

qemu_remove() {
	DEV_ID="dev-$1"; shift
	echo "[disconnect] $DEV_ID" >&2
	echo "device_del id=$DEV_ID"
}

qemu_type() {
	STRING=$1; shift
	LEN=${#STRING}
	LEN=$[$LEN -1]
	echo "[      type] $STRING" >&2

	for IDX in $(seq 0 $LEN); do
		KEYS=$(get_keys "${STRING:$IDX:1}" | tr '\n' '&' | sed 's/&//g')
		echo "send-key keys=[$KEYS]"
	done
}

qemu_cmd() {
	SOCKET_FILE=$1; shift
	"qemu_$@" | python2 "$QEMU_PATH/scripts/qmp/qmp-shell" $SOCKET_FILE >/dev/null
}

checkpoint() {
	RANGE_FILE=$1; shift
	LOG_FILE=$1; shift
	POINT_NAME=$1; shift
	LINE_COUNT=$(wc -l <$LOG_FILE)

	echo "$LINE_COUNT $POINT_NAME" >>$RANGE_FILE
}

judge_no_crash() {
	HC=$1; shift;
	DEV=$1; shift;
	TEST=$1; shift;
	RANGE_FILE=$1; shift;
	LOG_FILE=$1; shift;
	DISECT_FILE=$1; shift;
	FAIL_FILE=$1; shift;

	if egrep -i "(dumping task)|page_fault|crash|(assertion fail)|(spurious interrupt)" $DISECT_FILE >/dev/null; then
		echo "Something crashed." >>$FAIL_FILE
	fi
}

test_disconnect() {
	RANGE_FILE=$1; shift;
	LOG_FILE=$1; shift;
	SOCKET_FILE=$1; shift;
	FAIL_FILE=$1; shift;
	DEV_ID=$1; shift;
	DEV=$1; shift;

	# connect device
	qemu_cmd $SOCKET_FILE add $DEV_ID $DEV
	sleep $CONNECT_DELAY

	checkpoint $RANGE_FILE $LOG_FILE disconnect_device

	# disconnect device
	qemu_cmd $SOCKET_FILE remove $DEV_ID
	sleep $DISCONNECT_DELAY
}

judge_disconnect() {
	judge_no_crash $@
}

test_offline_disconnect() {
	RANGE_FILE=$1; shift;
	LOG_FILE=$1; shift;
	SOCKET_FILE=$1; shift;
	FAIL_FILE=$1; shift;
	DEV_ID=$1; shift;
	DEV=$1; shift;

	# connect device
	qemu_cmd $SOCKET_FILE add $DEV_ID $DEV
	sleep $CONNECT_DELAY

	checkpoint $RANGE_FILE $LOG_FILE offline_device

	# offline device
	ADDRESS=$(grep -oP "Function \`(.+)' added to category" $LOG_FILE | tail -n1 | grep -oP "/hw/.+/usb\d+-[lfhs]s") || true
	if [ -z "$ADDRESS" ]; then
		echo "Could not find device function to offline." >>$FAIL_FILE
		return
	fi

	qemu_cmd $SOCKET_FILE type "devctl offline $ADDRESS;"
	sleep $OFFLINE_DELAY

	checkpoint $RANGE_FILE $LOG_FILE disconnect_device

	# disconnect device
	qemu_cmd $SOCKET_FILE remove $DEV_ID
	sleep $DISCONNECT_DELAY
}

judge_offline_disconnect() {
	judge_no_crash $@

	HC=$1; shift;
	DEV=$1; shift;
	TEST=$1; shift;
	RANGE_FILE=$1; shift;
	LOG_FILE=$1; shift;
	DISECT_FILE=$1; shift;
	FAIL_FILE=$1; shift;

	grep -vi "is now offline" $DISECT_FILE >/dev/null || echo "Device did not go offline." >>$FAIL_FILE
}

test_offline_online_disconnect() {
	RANGE_FILE=$1; shift;
	LOG_FILE=$1; shift;
	SOCKET_FILE=$1; shift;
	FAIL_FILE=$1; shift;
	DEV_ID=$1; shift;
	DEV=$1; shift;

	# connect device
	qemu_cmd $SOCKET_FILE add $DEV_ID $DEV
	sleep $CONNECT_DELAY

	checkpoint $RANGE_FILE $LOG_FILE offline_device

	# offline device
	ADDRESS=$(grep -oP "Function \`(.+)' added to category" $LOG_FILE | tail -n1 | grep -oP "/hw/.+/usb\d+-[lfhs]s") || true
	if [ -z "$ADDRESS" ]; then
		echo "Could not find device function to offline." >>$FAIL_FILE
		return
	fi

	qemu_cmd $SOCKET_FILE type "devctl offline $ADDRESS;"
	sleep $OFFLINE_DELAY

	checkpoint $RANGE_FILE $LOG_FILE online_device
	qemu_cmd $SOCKET_FILE type "devctl online $ADDRESS;"
	sleep $OFFLINE_DELAY

	checkpoint $RANGE_FILE $LOG_FILE disconnect_device

	# disconnect device
	qemu_cmd $SOCKET_FILE remove $DEV_ID
	sleep $DISCONNECT_DELAY
}

judge_offline_online_disconnect() {
	judge_no_crash $@

	HC=$1; shift;
	DEV=$1; shift;
	TEST=$1; shift;
	RANGE_FILE=$1; shift;
	LOG_FILE=$1; shift;
	DISECT_FILE=$1; shift;
	FAIL_FILE=$1; shift;

	grep -vi "is now offline" $DISECT_FILE >/dev/null || echo "Device did not go offline." >>$FAIL_FILE
	grep -vi "is now online" $DISECT_FILE >/dev/null || echo "Device did not go online." >>$FAIL_FILE
}

disect_log() {
	HC=$1; shift;
	DEV=$1; shift;
	TEST=$1; shift;
	RANGE_FILE=$1; shift;
	LOG_FILE=$1; shift;
	DISECT_FILE=$1; shift;

	rm -f $DISECT_FILE
	echo "HC:     $HC" >>$DISECT_FILE
	echo "DEV:    $DEV" >>$DISECT_FILE
	echo "TEST:   $TEST" >>$DISECT_FILE
	echo "" >>$DISECT_FILE

	PREV_LINE=none
	while read CHECKPOINT
	do
		set $CHECKPOINT
		CP_LINE=$1; shift
		CP_NAME=$1; shift

		if [ ! $PREV_LINE == none ]; then
			sed -n "$PREV_LINE,$CP_LINE p" $LOG_FILE >>$DISECT_FILE
			echo "" >>$DISECT_FILE
			echo "" >>$DISECT_FILE
			echo "" >>$DISECT_FILE
		fi
		echo "==================================================" >>$DISECT_FILE
		echo "  CHECKPOINT: $CP_NAME" >>$DISECT_FILE
		echo "==================================================" >>$DISECT_FILE
		echo "" >>$DISECT_FILE

		PREV_LINE=$CP_LINE
	done <$RANGE_FILE
}

try_dev() {
	HC=$1; shift
	DEV=$1; shift

	LOG_FILE="$REPORT_PATH/${HC}-${DEV}.log"
	SOCKET_FILE="disconnect-test-${HC}-${DEV}"
	DEV_ID=1

	qemu_run $HC $LOG_FILE &
	sleep $STARTUP_DELAY

	for TEST in $TESTS; do
		TEST_CMD=test_$TEST
		RANGE_FILE="$REPORT_PATH/${HC}-${DEV}-${TEST//_/-}.range"
		FAIL_FILE="$REPORT_PATH/${HC}-${DEV}-${TEST//_/-}.fail"
		rm -f $RANGE_FILE $FAIL_FILE

		checkpoint $RANGE_FILE $LOG_FILE start
		echo "[test start] $TEST" >&2

		$TEST_CMD $RANGE_FILE $LOG_FILE $SOCKET_FILE $FAIL_FILE $DEV_ID $DEV

		checkpoint $RANGE_FILE $LOG_FILE end
		echo "[  test end] $TEST" >&2

		DEV_ID=$[$DEV_ID +1]
	done

	echo "[ halt qemu] $HC" >&2
	kill %1
	wait %1

	echo "" >&2

	for TEST in $TESTS; do
		RANGE_FILE="$REPORT_PATH/${HC}-${DEV}-${TEST//_/-}.range"
		FAIL_FILE="$REPORT_PATH/${HC}-${DEV}-${TEST//_/-}.fail"
		DISECT_FILE="$REPORT_PATH/${HC}-${DEV}-${TEST//_/-}"
		JUDGE_CMD=judge_$TEST

		PASS=1

		disect_log $HC $DEV $TEST $RANGE_FILE $LOG_FILE $DISECT_FILE

		if [ ! -e $FAIL_FILE ]; then
			$JUDGE_CMD $HC $DEV $TEST $RANGE_FILE $LOG_FILE $DISECT_FILE $FAIL_FILE
		fi

		if [ -e $FAIL_FILE ]; then
			PASS=0
		fi

		rm -f $DISECT_FILE.swp

		if [ $PASS == 1 ]; then
			echo "[--  OK  --] $TEST" >&2
			echo "TEST PASS" >>$DISECT_FILE.swp
		else
			echo "[## FAIL ##] $TEST" >&2
			echo "TEST FAILURE" >>$DISECT_FILE.swp
			cat $FAIL_FILE >>$DISECT_FILE.swp
		fi

		echo "" >>$DISECT_FILE.swp
		cat $DISECT_FILE >>$DISECT_FILE.swp
		mv $DISECT_FILE.swp $DISECT_FILE
		rm -f $RANGE_FILE $FAIL_FILE

		FINAL_REPORT="${REPORT_PATH}/${HC}/${DEV}/${TEST//_/-}"
		mkdir -p $(dirname $FINAL_REPORT)
		mv $DISECT_FILE $FINAL_REPORT
	done

	rm -f $LOG_FILE
}

for HC in $HCS; do
	for DEV in $DEVS; do
		echo "" >&2
		echo "" >&2
		echo "==================================================" >&2
		echo "$HC $DEV" >&2
		echo "==================================================" >&2
		try_dev $HC $DEV
	done
done

