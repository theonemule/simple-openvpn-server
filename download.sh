#!/usr/bin/env bash

set -uo pipefail

CLIENT=""
CLIENTS_DIR="/etc/openvpn/clients"

urldecode() {
	local data="${1//+/ }"
	printf '%b' "${data//%/\\x}"
}

for pair in ${QUERY_STRING//&/ }; do
	key="${pair%%=*}"
	val="${pair#*=}"
	decoded="$(urldecode "${val}")"
	if [[ "${key}" == "client" ]]; then
		CLIENT="${decoded}"
	fi
done

if ! [[ "${CLIENT}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
	echo "Status: 400 Bad Request"
	echo "Content-type: text/plain"
	echo ""
	echo "Invalid client name"
	exit 0
fi

FILE_PATH="${CLIENTS_DIR}/${CLIENT}.ovpn"
if [[ ! -f "${FILE_PATH}" ]]; then
	echo "Status: 404 Not Found"
	echo "Content-type: text/plain"
	echo ""
	echo "Client profile not found"
	exit 0
fi

echo "Content-type: text/plain"
echo "Content-Disposition: attachment; filename=\"${CLIENT}.ovpn\""
echo ""
cat "${FILE_PATH}"

exit 0