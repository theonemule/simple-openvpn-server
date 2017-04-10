#!/bin/bash
#Downloads the config file for the client.

eval `echo "${QUERY_STRING}"|tr '&' ';'`
client=$(echo $client | tr -d '\r')
echo "Content-type: text/plain"
echo "Content-Disposition: attachment; filename=\"$client.ovpn\""
echo ""
while read c; do
	echo $c
done </etc/openvpn/clients/$client.ovpn
exit 0