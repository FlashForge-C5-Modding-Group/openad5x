#!/bin/sh
# nginx: Fluidd on port 80, API passed to Moonraker

NGINX_DIR=/usr/data/nginx

[ -x $NGINX_DIR/nginx ] || { echo "not installed"; exit 0; }

mkdir -p /usr/data/tmp
$NGINX_DIR/nginx -p $NGINX_DIR -c $NGINX_DIR/nginx.conf && echo "started"
