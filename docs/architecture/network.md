# Network

How the stock firmware brings up the network. Settings are the `network` section of `/usr/prog/config/Adventurer5M.json`, and saved Wi-Fi networks are in `/usr/prog/wifi/wpa_supplicant.conf`.

Only one mode is active. They are checked in this order at boot:

| Mode | Stock function | What it runs |
|---|---|---|
| Hotspot | `wifiHotspotStatus` | `ifconfig wlan0 up`, `ifconfig wlan0 192.168.0.240`, `udhcpd -I 192.168.0.240`, `hostapd -B /usr/prog/wifi/rtl_hostapd_2G.conf` |
| Wi-Fi | `wifiStationStatus` | `wpa_supplicant -d -Dnl80211 -iwlan0 -c/usr/prog/wifi/wpa_supplicant.conf -B`, then `wpa_cli -i wlan0 enable_network all`, then an address on `wlan0` |
| Ethernet | `ethernetStatus` | `ifconfig eth0 up`. The cable state is `/sys/class/net/eth0/carrier`. Then an address on `eth0` |

## Getting an address

For Wi-Fi and Ethernet:

| Setting | What runs |
|---|---|
| `isUdhcpc` | `udhcpc -i <iface>` |
| `isManual` | `ifconfig <iface> <configIp> netmask <configNetmask>`, `route add default gw <configGateway>`, and `nameserver <configDns>` in `/etc/resolv.conf` |

## Cable changes

- Ethernet cable plugged in: `killall udhcpc`, flush the address, DHCP again.
- Ethernet cable pulled: `killall udhcpc`, flush the address.

The `eth0` MAC address is set earlier by `app_startup.sh`, from `/usr/prog/MAC`.

Adding and saving Wi-Fi networks (`wpa_cli add_network`, `save_config`) is a job for the touchscreen menu, not for startup.

## SFTP

Stock dropbear starts `/usr/libexec/sftp-server`, which the read-only root does not have. `06-sftp.sh` copies `/usr/sbin/dropbear` to `/usr/data/openad5x/bin/dropbear-sftp`, changes the one `/usr/libexec/sftp-server` string in the copy to `/opt/libexec/sftp-server` (Entware's, from `openssh-sftp-server`; the same length, so the file size stays the same), bind-mounts the copy over `/usr/sbin/dropbear` and restarts `S50dropbear`. It waits for `/opt` to be mounted, and does nothing if the string is not found. The stock AD5X dropbear has that string once, at offset 220360. Not yet run on a printer.
