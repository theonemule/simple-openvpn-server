#!/usr/bin/env bash

set -euo pipefail

# defaults
ADMINPASSWORD="secret"
DNS1="1.1.1.1"
DNS2="9.9.9.9"
PROTOCOL="udp"
EMAIL=""
PORT="1194"
HOST="$(curl -4fsSL https://api.ipify.org || true)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENVPN_GROUP="openvpn-admin"
SERVER_DIR="/etc/openvpn/server"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CLIENTS_DIR="/etc/openvpn/clients"

for i in "$@"; do
    case $i in
        --adminpassword=*)
            ADMINPASSWORD="${i#*=}"
            ;;
        --dns1=*)
            DNS1="${i#*=}"
            ;;
        --dns2=*)
            DNS2="${i#*=}"
            ;;
        --vpnport=*)
            PORT="${i#*=}"
            ;;
        --protocol=*)
            PROTOCOL="${i#*=}"
            ;;
        --host=*)
            HOST="${i#*=}"
            ;;
        --email=*)
            EMAIL="${i#*=}"
            ;;
        *)
            ;;
    esac
done

if [[ "${ADMINPASSWORD}" == "secret" ]]; then
    echo "fatal: password is not set"
    exit 1
fi

if [[ "${PROTOCOL}" != "udp" && "${PROTOCOL}" != "tcp" ]]; then
    echo "fatal: protocol must be udp or tcp"
    exit 1
fi

if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
    echo "fatal: vpn port must be a valid integer from 1-65535"
    exit 1
fi

if [[ -z "${HOST}" ]]; then
    echo "fatal: host is not set and could not be auto-detected"
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Sorry, you need to run this as root"
    exit 2
fi

if [[ ! -e /dev/net/tun ]]; then
    echo "The TUN device is not available. Enable TUN before running this script."
    exit 3
fi

if [[ ! -e /etc/os-release ]]; then
    echo "Cannot determine operating system"
    exit 4
fi

. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "This installer is supported on Ubuntu only. Found: ${PRETTY_NAME:-unknown}"
    exit 5
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    openvpn easy-rsa iptables curl openssl fcgiwrap ca-certificates \
    certbot python3-certbot-nginx apache2-utils nginx

install -d -m 0750 -o root -g root "${SERVER_DIR}" "${CLIENTS_DIR}" "${EASYRSA_DIR}"

# Reinitialize PKI each install run to keep behavior predictable.
rm -rf "${EASYRSA_DIR}"
cp -R /usr/share/easy-rsa "${EASYRSA_DIR}"
chown -R root:root "${EASYRSA_DIR}"

cd "${EASYRSA_DIR}"
./easyrsa init-pki
./easyrsa --batch build-ca nopass
./easyrsa --batch build-server-full server nopass
./easyrsa gen-crl

cp pki/ca.crt "${SERVER_DIR}/ca.crt"
cp pki/issued/server.crt "${SERVER_DIR}/server.crt"
cp pki/private/server.key "${SERVER_DIR}/server.key"
cp pki/crl.pem "${SERVER_DIR}/crl.pem"

# tls-crypt is preferred over tls-auth for metadata protection.
openvpn --genkey secret "${SERVER_DIR}/tc.key"

# Ensure group exists before any ownership assignments that use it.
groupadd -f "${OPENVPN_GROUP}"

chown root:root "${SERVER_DIR}/ca.crt" "${SERVER_DIR}/server.crt" "${SERVER_DIR}/server.key" "${SERVER_DIR}/crl.pem"
chown root:"${OPENVPN_GROUP}" "${SERVER_DIR}/tc.key"
chmod 0640 "${SERVER_DIR}"/*.crt "${SERVER_DIR}/server.key" "${SERVER_DIR}"/tc.key "${SERVER_DIR}"/crl.pem
chown root:"${OPENVPN_GROUP}" "${SERVER_DIR}"
chmod 0750 "${SERVER_DIR}"
chown nobody:nogroup "${SERVER_DIR}/crl.pem"

cat > "${SERVER_DIR}/server.conf" <<EOF
port ${PORT}
proto ${PROTOCOL}
dev tun
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${DNS1}"
push "dhcp-option DNS ${DNS2}"
keepalive 10 120
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/status.log
verb 3
explicit-exit-notify 1
remote-cert-tls client
auth SHA256
tls-version-min 1.2
tls-crypt tc.key
crl-verify crl.pem
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
cipher AES-256-GCM
EOF

cat > /etc/openvpn/client-common.txt <<EOF
client
dev tun
proto ${PROTOCOL}
remote ${HOST} ${PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
tls-version-min 1.2
verb 3
setenv opt block-outside-dns
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
cipher AES-256-GCM
EOF

# Enable forwarding persistently.
cat > /etc/sysctl.d/99-openvpn-forwarding.conf <<EOF
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

WAN_IFACE="$(ip -4 route list default | awk '{print $5}' | head -n1)"
if [[ -z "${WAN_IFACE}" ]]; then
    echo "fatal: unable to detect default network interface"
    exit 6
fi

cat > /usr/local/sbin/openvpn-iptables.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o ${WAN_IFACE} -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${WAN_IFACE} -j MASQUERADE
iptables -C INPUT -p ${PROTOCOL} --dport ${PORT} -j ACCEPT 2>/dev/null || \
  iptables -I INPUT -p ${PROTOCOL} --dport ${PORT} -j ACCEPT
iptables -C FORWARD -s 10.8.0.0/24 -j ACCEPT 2>/dev/null || \
  iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
EOF
chmod 0755 /usr/local/sbin/openvpn-iptables.sh

cat > /etc/systemd/system/openvpn-iptables.service <<EOF
[Unit]
Description=Apply OpenVPN iptables rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/openvpn-iptables.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

usermod -a -G "${OPENVPN_GROUP}" www-data

chown -R root:"${OPENVPN_GROUP}" "${EASYRSA_DIR}" "${CLIENTS_DIR}"
find "${EASYRSA_DIR}" -type d -exec chmod 2770 {} \;
find "${EASYRSA_DIR}" -type f -exec chmod 0660 {} \;
if [[ -f "${EASYRSA_DIR}/easyrsa" ]]; then
    chmod 0770 "${EASYRSA_DIR}/easyrsa"
fi
find "${CLIENTS_DIR}" -type d -exec chmod 2770 {} \;
find "${CLIENTS_DIR}" -type f -exec chmod 0660 {} \;

if [[ -f /etc/nginx/sites-available/default ]]; then
    cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
fi
install -m 0644 "${SCRIPT_DIR}/default" /etc/nginx/sites-available/default
sed -i "s/server_name[[:space:]]\+example.com;/server_name ${HOST};/" /etc/nginx/sites-available/default

install -d -m 0755 /var/www/html
install -m 0755 "${SCRIPT_DIR}/index.sh" /var/www/html/index.sh
install -m 0755 "${SCRIPT_DIR}/download.sh" /var/www/html/download.sh
chown -R www-data:www-data /var/www/html

htpasswd -b -c /etc/nginx/.htpasswd admin "${ADMINPASSWORD}"

systemctl daemon-reload
systemctl enable --now fcgiwrap
systemctl enable --now openvpn-iptables.service
systemctl enable --now openvpn-server@server.service

if [[ -n "${EMAIL}" && "${HOST}" != *":"* && "${HOST}" != *"/"* ]]; then
    certbot --nginx --agree-tos --redirect --keep-until-expiring --non-interactive \
        -m "${EMAIL}" -d "${HOST}" || echo "warning: certbot failed; HTTPS certificate not configured"
else
    echo "warning: skipping certbot because --email was not provided"
fi

nginx -t
systemctl restart nginx

echo "OpenVPN + web admin install complete."
