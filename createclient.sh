#!/usr/bin/env bash

set -euo pipefail

OPTION="${1:-}"
CLIENT="${2:-}"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
SERVER_DIR="/etc/openvpn/server"
CLIENTS_DIR="/etc/openvpn/clients"

if [[ "$EUID" -ne 0 ]]; then
        echo "Run this script as root"
        exit 1
fi

if [[ -z "${OPTION}" || -z "${CLIENT}" ]]; then
        echo "Usage: $0 <add|revoke> <client-name>"
        exit 1
fi

if ! [[ "${CLIENT}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "Client name may only contain letters, numbers, dots, underscores, and dashes"
        exit 1
fi

newclient() {
        local client_name="$1"
        local output_file="${CLIENTS_DIR}/${client_name}.ovpn"

        cp /etc/openvpn/client-common.txt "${output_file}"
        {
                echo "<ca>"
                cat "${EASYRSA_DIR}/pki/ca.crt"
                echo "</ca>"
                echo "<cert>"
                cat "${EASYRSA_DIR}/pki/issued/${client_name}.crt"
                echo "</cert>"
                echo "<key>"
                cat "${EASYRSA_DIR}/pki/private/${client_name}.key"
                echo "</key>"
                echo "<tls-crypt>"
                cat "${SERVER_DIR}/tc.key"
                echo "</tls-crypt>"
        } >> "${output_file}"
}

add_or_revoke() {
        cd "${EASYRSA_DIR}"

        case "${OPTION}" in
                add)
                        ./easyrsa --batch build-client-full "${CLIENT}" nopass
                        newclient "${CLIENT}"
                        echo "Certificate for client ${CLIENT} added"
                        ;;
                revoke)
                        echo "Revoking client ${CLIENT} ..."
                        ./easyrsa --batch revoke "${CLIENT}"
                        ./easyrsa gen-crl
                        rm -f "pki/reqs/${CLIENT}.req" "pki/private/${CLIENT}.key" "pki/issued/${CLIENT}.crt"
                        rm -f "${CLIENTS_DIR}/${CLIENT}.ovpn"
                        cp "${EASYRSA_DIR}/pki/crl.pem" "${SERVER_DIR}/crl.pem"
                        chown nobody:nogroup "${SERVER_DIR}/crl.pem"
                        chmod 0640 "${SERVER_DIR}/crl.pem"
                        echo "Certificate for client ${CLIENT} revoked"
                        ;;
                *)
                        echo "Option must be 'add' or 'revoke'"
                        exit 1
                        ;;
        esac
}

client_list() {
        local count
        count="$(tail -n +2 "${EASYRSA_DIR}/pki/index.txt" | grep -c "^V" || true)"

        if [[ "${count}" == "0" ]]; then
                echo "You have no existing clients"
                return
        fi

        echo "Clients in ${EASYRSA_DIR}/pki/index.txt ..."
        while read -r c; do
                if [[ "${c}" =~ ^V ]]; then
                        client_name="$(echo "${c}" | cut -d '=' -f 2)"
                        if [[ "${client_name}" != "server" ]]; then
                                echo "${client_name}"
                        fi
                fi
        done < "${EASYRSA_DIR}/pki/index.txt"
}

client_list
add_or_revoke
client_list

exit 0
 
