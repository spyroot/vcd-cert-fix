#!/bin/bash
# Copyright 2019 VMware, Inc.  All rights reserved.

LOG_DIR="/opt/vmware/var/log/vcd"
LOG_FILE="$LOG_DIR/generate-certificates.log"

kspass=$1

exec &>>$LOG_FILE

log() {
	information=$1
	current_date=$(date +'%F %T')
	echo "$current_date | $information" >>$LOG_FILE
}

touch $LOG_FILE

log "Creating SSL directory..."

log "Generating certificate and key for Postgres and Nginx..."

# Export these here so they're available when vcd_ova.cnf is evaluated
export SAN_HOSTNAME=$(hostname)
log "System hostname is: $SAN_HOSTNAME"
export SAN_HOSTNAME_PREFIX=${SAN_HOSTNAME%%.*}
export SAN_IP0=$(/opt/vmware/bin/ovfenv -k vami.ip0.VMware_vCloud_Director)
log "System ip0 is: $SAN_IP0"
export SAN_IP1=$(/opt/vmware/bin/ovfenv -k vami.ip1.VMware_vCloud_Director)

SSL_DIR=/opt/vmware/appliance/etc/ssl
mkdir -p $SSL_DIR

OPENSSL=/usr/bin/openssl
if [[ ! -f $SSL_DIR/vcd_ova.csr || ! -f $SSL_DIR/vcd_ova.key ]]; then
	$OPENSSL req -new -days 900 \
		-newkey rsa:2048 -nodes -keyout $SSL_DIR/vcd_ova.key \
		-out $SSL_DIR/vcd_ova.csr \
		-config $SSL_DIR/vcd_ova.cnf
fi

$OPENSSL x509 \
	-signkey $SSL_DIR/vcd_ova.key \
	-in $SSL_DIR/vcd_ova.csr \
	-req -days 900 \
	-out $SSL_DIR/vcd_ova.crt \
	-extfile $SSL_DIR/vcd_ova.cnf \
	-extensions v3_req

# Set key permissions to make postgres happy
/usr/bin/chown root:users $SSL_DIR/vcd_ova.key $SSL_DIR/vcd_ova.crt
/usr/bin/chmod 0640 $SSL_DIR/vcd_ova.key $SSL_DIR/vcd_ova.crt

log "Restarting Postgres and Nginx..."
systemctl restart vpostgres #configure-postgresql.sh will also restart vpostgres, but this script may run outside of firstboot
systemctl restart nginx

log "Generating certificates and keys for VCD..."
KEYSTORE=/opt/vmware/vcloud-director/certificates.ks
/opt/vmware/vcloud-director/bin/cell-management-tool generate-certs -j -p -o $KEYSTORE -x 900 -w $kspass
