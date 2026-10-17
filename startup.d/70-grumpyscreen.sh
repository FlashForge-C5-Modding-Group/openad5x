#!/bin/sh
# GrumpyScreen (grumpy-ff build) on the touchscreen

GS_DIR=/usr/data/grumpyscreen

[ -x $GS_DIR/start.sh ] || { echo "not installed"; exit 0; }

# right way up on the AD5X; pellcorp's default (3) is for the K1
DISPLAY_ROTATE=0 $GS_DIR/start.sh > /usr/data/logs/grumpyscreen.log 2>&1 &
echo "started"
