#!/bin/bash

#The admin interface for OpenVPN

echo "Content-type: text/html"
echo ""
echo "<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Simple OpenVPN Server</title>
</head>
<body>"

echo "<h1>Simple OpenVPN Server</h1>"

eval `echo "${QUERY_STRING}"|tr '&' ';'`

IP=$(wget -4qO- "http://whatismyip.akamai.com/")

newclient () {
	# Generates the custom client.ovpn
	cp /etc/openvpn/client-common.txt /etc/openvpn/clients/$1.ovpn
	echo "<ca>" >> /etc/openvpn/clients/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/ca.crt >> /etc/openvpn/clients/$1.ovpn
	echo "</ca>" >> /etc/openvpn/clients/$1.ovpn
	echo "<cert>" >> /etc/openvpn/clients/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> /etc/openvpn/clients/$1.ovpn
	echo "</cert>" >> /etc/openvpn/clients/$1.ovpn
	echo "<key>" >> /etc/openvpn/clients/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/private/$1.key >> /etc/openvpn/clients/$1.ovpn
	echo "</key>" >> /etc/openvpn/clients/$1.ovpn
	echo "<tls-auth>" >> /etc/openvpn/clients/$1.ovpn
	cat /etc/openvpn/ta.key >> /etc/openvpn/clients/$1.ovpn
	echo "</tls-auth>" >> /etc/openvpn/clients/$1.ovpn
}

cd /etc/openvpn/easy-rsa/

case $option in
	"add") #Add a client
		./easyrsa build-client-full $client nopass
		# Generates the custom client.ovpn
		newclient "$client"
		echo "<h3>Certificate for client <span style='color:red'>$client</span> added.</h3>"
	;;
	"revoke") #Revoke a client
		echo "<span style='display:none'>"
		./easyrsa --batch revoke $client
		./easyrsa gen-crl
		echo "</span>"
		rm -rf pki/reqs/$client.req
		rm -rf pki/private/$client.key
		rm -rf pki/issued/$client.crt
		rm -rf /etc/openvpn/crl.pem
		cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
		# CRL is read with each client connection, when OpenVPN is dropped to nobody
		echo "<h3>Certificate for client <span style='color:red'>$client</span> revoked.</h3>"
	;;
esac

NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
	echo "<h3>You have no existing clients.<h3>"
else
	while read c; do
		if [[ $(echo $c | grep -c "^V") = '1' ]]; then
			clientName=$(echo $c | cut -d '=' -f 2)
			echo "<p><a href='index.sh?option=revoke&client=$clientName'>Revoke</a> <a target='_blank' href='download.sh?client=$clientName'>Download</a> $clientName</p>"
		fi
	done </etc/openvpn/easy-rsa/pki/index.txt
fi

echo "
<form action='index.sh' method='get'>
<input type='hidden' name='option' value='add'>
New Client: <input type='text' name='client'><input type='submit' value='Add'>
</form>
"

echo "</body></html>"
exit 0
