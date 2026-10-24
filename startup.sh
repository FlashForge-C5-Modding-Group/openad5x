#!/bin/sh
# openad5x startup: toolhead board, Klipper, network, clock, then startup.d

CFG=/usr/prog/config/Adventurer5M.json
WIFI=/usr/prog/wifi
EBOARD=/dev/ttyS5
EBOARD_FLASH=/usr/data/kalico-fw/eboard.flash
IAP=/usr/prog/PROGRAM/control/1.1.1/IAPCommand
DROPIN_DIR=/usr/data/openad5x/startup.d
DROPIN_LOGS=/usr/data/logs/openad5x

log() { echo "openad5x: $*"; }

net_get() {
	sed -n '/"network"/,/}/s/.*"'"$1"'" *: *"\{0,1\}\([^",]*\).*/\1/p' "$CFG" | head -n 1
}

eboard_start() {
	stty -F $EBOARD 115200 cs8 -parenb -cstopb -crtscts clocal raw -echo || return 1
	exec 3<>$EBOARD
	ack=$(printf '\006')
	tries=0
	while [ $tries -lt 20 ]; do
		ready=
		i=0
		while [ $i -lt 10 ]; do
			if IFS= read -r -t 1 line <&3; then
				case "$line" in *Ready*) ready=1; break ;; esac
			fi
			i=$((i + 1))
		done
		if [ -z "$ready" ]; then
			log "eboard: no Ready, application already running"
			exec 3<&-
			return 0
		fi
		# one-time flash: the bootloader only accepts IAPCommand while it waits here
		if [ -f "$EBOARD_FLASH" ]; then
			hex=$(cat "$EBOARD_FLASH")
			rm -f "$EBOARD_FLASH"
			exec 3<&-
			mkdir -p $DROPIN_LOGS
			log "eboard: flashing $hex"
			$IAP "$hex" $EBOARD > $DROPIN_LOGS/eboard-flash.log 2>&1
			log "eboard: IAPCommand exit $?"
			stty -F $EBOARD 115200 cs8 -parenb -cstopb -crtscts clocal raw -echo
			exec 3<>$EBOARD
			continue
		fi
		printf '\101' >&3
		j=0
		while [ $j -lt 20 ]; do
			if IFS= read -r -n 1 -t 1 c <&3 && [ "$c" = "$ack" ]; then
				log "eboard: application started"
				exec 3<&-
				return 0
			fi
			j=$((j + 1))
		done
		tries=$((tries + 1))
	done
	log "eboard: no ACK"
	exec 3<&-
	return 1
}

set_address() {
	if [ "$(net_get isManual)" = true ]; then
		ifconfig "$1" "$(net_get configIp)" netmask "$(net_get configNetmask)"
		gw=$(net_get configGateway)
		[ -n "$gw" ] && route add default gw "$gw"
		dns=$(net_get configDns)
		[ -n "$dns" ] && echo "nameserver $dns # $1" > /etc/resolv.conf
	else
		udhcpc -b -i "$1" -p /var/run/udhcpc.pid
	fi
}

start_hotspot() {
	ifconfig wlan0 down
	ifconfig wlan0 up
	sleep 1
	ifconfig wlan0 192.168.0.240
	mkdir -p /var/lib/misc/
	touch /var/lib/misc/udhcpd.leases
	udhcpd -I 192.168.0.240
	hostapd -B $WIFI/rtl_hostapd_2G.conf
}

start_wifi() {
	ip addr flush dev eth0
	ifconfig wlan0 down
	killall wpa_supplicant udhcpc 2>/dev/null
	ifconfig wlan0 up
	wpa_supplicant -d -Dnl80211 -iwlan0 -c$WIFI/wpa_supplicant.conf -B
	wpa_cli -i wlan0 enable_network all
	set_address wlan0
}

eth_carrier() { cat /sys/class/net/eth0/carrier 2>/dev/null; }

eth_watch() {
	last=$(eth_carrier)
	while true; do
		sleep 2
		now=$(eth_carrier)
		[ "$now" = "$last" ] && continue
		killall udhcpc 2>/dev/null
		ip addr flush dev eth0
		if [ "$now" = 1 ]; then
			log "eth0: cable plugged in"
			set_address eth0
		else
			log "eth0: cable pulled"
		fi
		last=$now
	done
}

start_ethernet() {
	ifconfig eth0 up
	sleep 1
	[ "$(eth_carrier)" = 1 ] && set_address eth0
	eth_watch &
}

network_start() {
	if [ "$(net_get wifiHotspotStatus)" = true ]; then
		log "network: hotspot"
		start_hotspot
	elif [ "$(net_get wifiStationStatus)" = true ]; then
		log "network: wifi"
		start_wifi
	elif [ "$(net_get ethernetStatus)" = true ]; then
		log "network: ethernet"
		start_ethernet
	else
		log "network: none enabled"
	fi
}

clock_sync() {
	i=0
	while [ $i -lt 60 ]; do
		/usr/prog/ntpclient -c 1 -s -h pool.ntp.org >/dev/null 2>&1
		if [ "$(date +%Y)" -ge 2024 ]; then
			log "clock: $(date)"
			return 0
		fi
		sleep 5
		i=$((i + 1))
	done
	log "clock: not set"
}

run_dropins() {
	[ -d "$DROPIN_DIR" ] || return 0
	mkdir -p "$DROPIN_LOGS"
	for script in "$DROPIN_DIR"/*.sh; do
		[ -f "$script" ] || continue
		name=$(basename "$script" .sh)
		sh "$script" > "$DROPIN_LOGS/$name.log" 2>&1
		log "startup.d: $name exit $?"
	done
}

eboard_start
if [ -x /usr/data/kalico/start.sh ]; then
	setsid /usr/data/kalico/start.sh > /dev/null 2>&1 < /dev/null &
else
	/usr/prog/klipper/start.sh &
fi
network_start
clock_sync &
run_dropins
