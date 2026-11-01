#!/bin/sh
# Start the DSP RPC daemons and the userspace QRTR name service inside the
# Android container.  Without qrtr-ns the QMI service table is empty and the
# camera provider hangs in qrtr_recvmsg().
sleep 4
lxc-attach -n android -- /system/bin/sh -c "(/vendor/bin/qrtr-ns -f >/dev/null 2>&1 &); (/vendor/bin/adsprpcd >/dev/null 2>&1 &); (/vendor/bin/cdsprpcd >/dev/null 2>&1 &)"
