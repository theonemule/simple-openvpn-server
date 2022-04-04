#!/bin/bash
# Run this script to create .ovpn file or revoke client manually.
# Arguments:
#   $1 = "add" or "revoke"
#   $2 = client name. for example: "myvpn" will generate myvpn.ovpn file in /etc/openvpn/clients
# change the IP (line 9) dns name appropriately for your environment.
###############################################################################################

IP=mydns.eastus2.cloudappazure.com
option=$1
client=$2

echo "Arguments: "
echo "Option: $option"
echo "Client: $client"
echo ""

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

addOrRevoke() {
    cd /etc/openvpn/easy-rsa/

    case $option in
            "add") #Add a client
                    ./easyrsa build-client-full $client nopass
                    # Generates the custom client.ovpn
                    newclient "$client"
                    echo "Certificate for client: $client added"
            ;;
            "revoke") #Revoke a client
                    echo "Revoking client $client ..."
                    ./easyrsa --batch revoke $client
                    ./easyrsa gen-crl
                    rm -rf pki/reqs/$client.req
                    rm -rf pki/private/$client.key
                    rm -rf pki/issued/$client.crt
                    rm -rf /etc/openvpn/crl.pem
                    rm /etc/openvpn/clients/$client.ovpn
                    cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
                    # CRL is read with each client connection, when OpenVPN is dropped to nobody
                    echo "Certificate for client: $client revoked."
            ;;
    esac
}

clientList() {
    NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
    if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
            echo "You have no existing clients."
    else
            echo "Clients in /etc/openvpn/easy-rsa/pki/index.txt ..."
            while read c; do
                    if [[ $(echo $c | grep -c "^V") = '1' ]]; then
                            clientName=$(echo $c | cut -d '=' -f 2)
                            if [[ "$clientName" != "server" ]] ; then
                                    echo "$clientName"
                            fi
                    fi
            done </etc/openvpn/easy-rsa/pki/index.txt
    fi
}

# list clients prior to adding or removing
clientList

if [[ "$option" == 'add' ]] || [[ "$option" == "revoke" ]]; then
        addOrRevoke
fi

# list clients after adding or removing 
clientList

exit 0
 
