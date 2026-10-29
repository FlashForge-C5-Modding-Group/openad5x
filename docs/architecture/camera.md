# Camera

## What stock does

`firmwareExe` has its own streamer built in, using mjpg-streamer code: V4L2 capture, `GET /?action=stream`, `Server: MJPG-Streamer/0.2`, port 8080 and camera hot-plug. Its command line for an external `/usr/prog/mjpg-streamer/bin/mjpg_streamer` is dead code: that program is in no AD5X package (factory image, 3.1.0 update, rootfs, 3.1.5, 3.1.6). With `firmwareExe` stopped there is no camera until one is started.

## FlashForge's mjpg-streamer

FlashForge ships `mjpg-streamer.zip` separately. It was built with Ingenic XBurst2 GCC 7.2.0 and glibc 2.29, has flags `0x70001405` (the same as `firmwareExe`) and its own libjpeg 9e, and uses the printer's libc, libdl and libpthread.

It is installed unchanged at `/usr/prog/mjpg-streamer` (files 644, directories, binaries and `.so` files 755). Its `start_webcam.sh` and `.orig` are not used; it is unknown which one is stock, and the `.orig` needs `v4l2-ctl`, which the printer does not have.

## The drop-in

`startup.d/30-camera.sh` runs `firmwareExe`'s own command without the cloud snapshot output file:

```sh
LD_LIBRARY_PATH=/usr/prog/mjpg-streamer mjpg_streamer \
  -i "input_uvc.so -d <camera> -r 1280x720 -f 30" \
  -o "output_http.so -w /usr/prog/mjpg-streamer/www --port 8080"
```

- **Finding the camera:** it scans `/sys/class/video4linux` for the `uvcvideo` driver at index 0 (index 1 is metadata). It skips `video2`, which is the X2600's decoder (`felix-vdec`).
- **Hot-plug:** it waits for a camera and starts again after an unplug (a 5 s loop).
- **Log:** `/usr/data/logs/mjpg-streamer.log`. The `UVCIOC_CTRL_ADD/MAP` "Inappropriate ioctl" lines are harmless (Logitech extension controls).
- **Kernel:** `uvcvideo` is built in. The tested camera is a Logitech Brio 101.

## Web

nginx passes `/webcam/` to `127.0.0.1:8080`. `moonraker.conf` has a `[webcam printer]` section (`mjpegstreamer`, `/webcam/?action=stream`, `/webcam/?action=snapshot`), so Fluidd shows the stream.

Tested on 2026-10-18: Fluidd shows the camera, and after a power cycle `30-camera` started at boot, the camera was `/dev/video0` and port 8080 was up.

An own `ustreamer` build (`ustreamer-ff`) is on hold and not used.
