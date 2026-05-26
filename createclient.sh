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

run_easyrsa() {
        if [[ -x "./easyrsa" ]]; then
                ./easyrsa "$@"
        else
                bash ./easyrsa "$@"
        fi
}

newclient() {
        local client_name="$1"
        local output_file="${CLIENTS_DIR}/${client_name}.ovpn"
        local ca_file="${EASYRSA_DIR}/pki/ca.crt"
        local cert_file="${EASYRSA_DIR}/pki/issued/${client_name}.crt"
        local key_file="${EASYRSA_DIR}/pki/private/${client_name}.key"
        local tls_key_file="${SERVER_DIR}/tc.key"

        for required_file in \
                "${ca_file}" \
                "${cert_file}" \
                "${key_file}" \
                "${tls_key_file}"; do
                if [[ ! -r "${required_file}" ]]; then
                        echo "Required file is missing or unreadable: ${required_file}"
                        return 1
                fi
        done

        cp /etc/openvpn/client-common.txt "${output_file}"
        {
                echo "<ca>"
                cat "${ca_file}"
                echo "</ca>"
                echo "<cert>"
                cat "${cert_file}"
                echo "</cert>"
                echo "<key>"
                cat "${key_file}"
                echo "</key>"
                echo "<tls-crypt>"
                cat "${tls_key_file}"
                echo "</tls-crypt>"
        } >> "${output_file}"
}

add_or_revoke() {
        cd "${EASYRSA_DIR}"

        case "${OPTION}" in
                add)
                        run_easyrsa --batch build-client-full "${CLIENT}" nopass
                        newclient "${CLIENT}"
                        echo "Certificate for client ${CLIENT} added"
                        ;;
                revoke)
                        echo "Revoking client ${CLIENT} ..."
                        run_easyrsa --batch revoke "${CLIENT}"
                        run_easyrsa gen-crl
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
 
