#!/bin/sh
# GrumpyScreen (grumpy-ff build) on the touchscreen

GS_DIR=/usr/data/grumpyscreen

[ -x $GS_DIR/start.sh ] || { echo "not installed"; exit 0; }

# AFC installed: MMU panel on, unless another backend was chosen
if [ -d /usr/data/AFC-Klipper-Add-On ] && grep -q '^backend: none' $GS_DIR/grumpyscreen.cfg; then
	sed -i '/^\[mmu\]/,/^\[/ s/^backend: none/backend: afc/' $GS_DIR/grumpyscreen.cfg
	echo "mmu backend: afc"
fi

# right way up on the AD5X; pellcorp's default (3) is for the K1
DISPLAY_ROTATE=0 $GS_DIR/start.sh > /usr/data/logs/grumpyscreen.log 2>&1 &
echo "started"
