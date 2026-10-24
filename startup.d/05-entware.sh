#!/bin/sh
# Entware: files in /usr/data/bin/opt, bind-mounted on /opt
# Its binaries are legacy NaN, so the kernel's NaN check is relaxed first

OPT_STORE=/usr/data/bin/opt

[ -x $OPT_STORE/bin/opkg ] || { echo "not installed"; exit 0; }

case "$(ls /usr/prog/PROGRAM/kernel/ 2>/dev/null | head -n 1)" in
	2.0.1) busybox devmem 0x00a130d1 8 1 ;;
	*) echo "unknown kernel package, legacy NaN not enabled"; exit 1 ;;
esac

grep -q ' /opt ' /proc/mounts || mount --bind $OPT_STORE /opt || exit 1
[ -x /opt/etc/init.d/rc.unslung ] && /opt/etc/init.d/rc.unslung start
echo "started"
