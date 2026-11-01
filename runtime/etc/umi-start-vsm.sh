#!/bin/sh
sleep 6
lxc-attach -n android -- /system/bin/sh -c "(/vendor/bin/vndservicemanager /dev/vndbinder >/dev/null 2>&1 &)"
sleep 3
systemctl restart lightdm || true
