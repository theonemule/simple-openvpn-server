#!/usr/bin/env bash

set -uo pipefail

EASYRSA_DIR="/etc/openvpn/easy-rsa"
SERVER_DIR="/etc/openvpn/server"
CLIENTS_DIR="/etc/openvpn/clients"
OPTION=""
CLIENT=""
MESSAGE=""

urldecode() {
		local data="${1//+/ }"
		printf '%b' "${data//%/\\x}"
}

is_valid_client() {
		[[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]
}

run_easyrsa() {
		if [[ -x "./easyrsa" ]]; then
				./easyrsa "$@"
		else
				bash ./easyrsa "$@"
		fi
}

build_client_profile() {
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
						echo "missing_or_unreadable:${required_file}" >&2
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

handle_action() {
		if [[ -z "${OPTION}" || -z "${CLIENT}" ]]; then
				return
		fi

		if ! is_valid_client "${CLIENT}"; then
				MESSAGE="Invalid client name"
				return
		fi

		cd "${EASYRSA_DIR}" || return

		case "${OPTION}" in
				add)
						if run_easyrsa --batch build-client-full "${CLIENT}" nopass >/dev/null 2>&1; then
								if build_client_profile "${CLIENT}" 2>/dev/null; then
										MESSAGE="Certificate for client ${CLIENT} added"
								else
										rm -f "${CLIENTS_DIR}/${CLIENT}.ovpn"
										MESSAGE="Failed to build client profile ${CLIENT} (check tc.key permissions)"
								fi
						else
								MESSAGE="Failed to add client ${CLIENT}"
						fi
						;;
				revoke)
						if run_easyrsa --batch revoke "${CLIENT}" >/dev/null 2>&1; then
								run_easyrsa gen-crl >/dev/null 2>&1
								rm -f "pki/reqs/${CLIENT}.req" "pki/private/${CLIENT}.key" "pki/issued/${CLIENT}.crt"
								rm -f "${CLIENTS_DIR}/${CLIENT}.ovpn"
								cp "${EASYRSA_DIR}/pki/crl.pem" "${SERVER_DIR}/crl.pem"
								chown nobody:nogroup "${SERVER_DIR}/crl.pem"
								chmod 0640 "${SERVER_DIR}/crl.pem"
								MESSAGE="Certificate for client ${CLIENT} revoked"
						else
								MESSAGE="Failed to revoke client ${CLIENT}"
						fi
						;;
				*)
						MESSAGE="Unknown action"
						;;
		esac
}

for pair in ${QUERY_STRING//&/ }; do
		key="${pair%%=*}"
		val="${pair#*=}"
		decoded="$(urldecode "${val}")"
		case "${key}" in
				option)
						OPTION="${decoded}"
						;;
				client)
						CLIENT="${decoded}"
						;;
				*)
						;;
		esac
done

handle_action

echo "Content-type: text/html"
echo ""
cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>OpenVPN Admin</title>
	<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
	<style>
		body { background: linear-gradient(120deg, #e6f4ea, #f8fbff); min-height: 100vh; }
		.card { border: 0; box-shadow: 0 0.5rem 1.25rem rgba(20, 40, 80, 0.1); }
	</style>
</head>
<body>
	<main class="container py-5">
		<div class="card p-4 mb-4">
			<h1 class="h4 mb-3">Simple OpenVPN Server</h1>
			<p class="text-secondary mb-0">Client certificate management</p>
		</div>
HTML

if [[ -n "${MESSAGE}" ]]; then
		echo "<div class='alert alert-info'>${MESSAGE}</div>"
fi

echo "<div class='card p-4 mb-4'><h2 class='h5 mb-3'>Clients</h2>"
active_clients=0
while read -r line; do
		if [[ "${line}" =~ ^V ]]; then
				client_name="$(echo "${line}" | cut -d '=' -f 2)"
				if [[ "${client_name}" != "server" ]]; then
						active_clients=1
						echo "<div class='d-flex justify-content-between align-items-center border-bottom py-2'>"
						echo "<span>${client_name}</span>"
						echo "<span>"
						echo "<a class='btn btn-sm btn-outline-danger me-2' href='index.sh?option=revoke&client=${client_name}'>Revoke</a>"
						echo "<a class='btn btn-sm btn-outline-primary' target='_blank' href='download.sh?client=${client_name}'>Download</a>"
						echo "</span>"
						echo "</div>"
				fi
		fi
done < "${EASYRSA_DIR}/pki/index.txt"

if [[ "${active_clients}" -eq 0 ]]; then
		echo "<p class='text-secondary mb-0'>No clients found.</p>"
fi

cat <<'HTML'
		</div>

		<div class="card p-4">
			<h2 class="h5 mb-3">Create client</h2>
			<form action="index.sh" method="get" class="row g-2">
				<input type="hidden" name="option" value="add">
				<div class="col-sm-8">
					<input class="form-control" type="text" name="client" placeholder="client-name" required>
				</div>
				<div class="col-sm-4">
					<button class="btn btn-success w-100" type="submit">Add client</button>
				</div>
			</form>
		</div>
	</main>
</body>
</html>
HTML

exit 0