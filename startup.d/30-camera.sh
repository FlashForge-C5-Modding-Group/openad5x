#!/bin/sh
# Camera: FlashForge's own mjpg-streamer, same command as firmwareExe
# (without output_file snapshots), port 8080

MJ_DIR=/usr/prog/mjpg-streamer

[ -x $MJ_DIR/mjpg_streamer ] || { echo "not installed"; exit 0; }

# USB camera's capture node: uvcvideo driver, index 0 (index 1 is metadata)
find_camera() {
	for v in /sys/class/video4linux/video*; do
		[ "$(basename "$(readlink -f "$v/device/driver")")" = uvcvideo ] || continue
		[ "$(cat "$v/index" 2>/dev/null)" = 0 ] || continue
		echo "/dev/${v##*/}"
		return 0
	done
	return 1
}

# waits for a camera (plug in any time), starts again after an unplug
(
	while true; do
		if CAMERA=$(find_camera); then
			echo "camera $CAMERA"
			LD_LIBRARY_PATH=$MJ_DIR $MJ_DIR/mjpg_streamer \
				-i "input_uvc.so -d $CAMERA -r 1280x720 -f 30" \
				-o "output_http.so -w $MJ_DIR/www --port 8080"
		fi
		sleep 5
	done
) > /usr/data/logs/mjpg-streamer.log 2>&1 &
echo "started"
