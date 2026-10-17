#!/bin/sh
# Moonraker on FlashForge's Python 3.8.2

MR_DIR=/usr/data/moonraker
MR_ENV=/usr/data/moonraker-env

[ -f $MR_DIR/moonraker/moonraker.py ] || { echo "not installed"; exit 0; }

PYTHONPATH=$MR_ENV/site-packages \
LD_LIBRARY_PATH=$MR_ENV/lib:/usr/prog/Python-3.8.2/lib:/usr/prog/openssl-1.0.2d/lib:/usr/prog/libffi-3.4.4/lib \
SSL_CERT_FILE=$MR_ENV/site-packages/certifi/cacert.pem \
/usr/prog/Python-3.8.2/bin/python3 $MR_DIR/moonraker/moonraker.py -d /usr/data \
	> /usr/data/logs/moonraker.out 2>&1 &
echo "started"
