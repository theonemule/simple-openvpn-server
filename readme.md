# Simple OpenVPN Server

This project provides a lightweight OpenVPN server installer and a web-based client profile manager.

The repository has been updated for current OpenVPN and Ubuntu practices:

- Target OS: Ubuntu 24.04 LTS
- OpenVPN server layout: `/etc/openvpn/server/server.conf`
- Modern TLS controls: `tls-crypt`, `tls-version-min 1.2`, AEAD-first ciphers
- Systemd-native service management
- Input validation improvements for CGI scripts
- Updated Azure ARM template API versions and VM image defaults

## Quick Start (Ubuntu 24.04)

Optionally, deploy directly from Azure Portal:

<h2><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftheonemule%2Fsimple-openvpn-server%2Fmaster%2Fopenvpn-template.json" target="_blank">Deploy to Azure</a></h2>

1. SSH to your Ubuntu server and become root.

   ```bash
   sudo -i
   ```

2. Clone this repository.

   ```bash
   git clone https://github.com/theonemule/simple-openvpn-server.git
   cd simple-openvpn-server
   ```

3. Run the installer.

   ```bash
   ./openvpn.sh --adminpassword='strong-password' --host='vpn.example.com' --email='you@example.com'
   ```

4. Open the admin portal.

   - URL: `https://vpn.example.com`
   - Username: `admin`
   - Password: value passed to `--adminpassword`

## Installer Options

`./openvpn.sh [options]`

- `--adminpassword=` admin password for the web UI (required)
- `--host=` public host or IP used in generated client profiles
- `--email=` email for Let's Encrypt certificate requests
- `--vpnport=` OpenVPN port (default: `1194`)
- `--protocol=` `udp` or `tcp` (default: `udp`)
- `--dns1=` primary DNS pushed to clients (default: `1.1.1.1`)
- `--dns2=` secondary DNS pushed to clients (default: `9.9.9.9`)

If `--email` is omitted, the installer skips Certbot and leaves web TLS unconfigured.

## What the Installer Configures

- Installs required packages: OpenVPN, easy-rsa, nginx, fcgiwrap, certbot
- Creates PKI under `/etc/openvpn/easy-rsa`
- Writes OpenVPN server config to `/etc/openvpn/server/server.conf`
- Enables IPv4 forwarding using `/etc/sysctl.d/99-openvpn-forwarding.conf`
- Creates persistent NAT/forward rules via a systemd unit
- Deploys CGI admin scripts to `/var/www/html`

## Managing Client Profiles

Use the web UI or run the helper script directly on the server.

```bash
sudo ./createclient.sh add alice
sudo ./createclient.sh revoke alice
```

Generated client files are stored in `/etc/openvpn/clients`.

## Azure Deployment

Use `openvpn-template.json` to deploy a VM and run the installer via Custom Script Extension.

Template defaults are updated to:

- Ubuntu 24.04 image reference
- Newer Azure API versions
- Correct NSG protocol rules for HTTP/HTTPS/OpenVPN

## Security Notes

- This project uses `nopass` client keys for compatibility with automated profile generation.
- The web process needs access to Easy-RSA material to issue/revoke certificates.
- For production hardening, consider moving certificate issuance out of CGI and into a separate privileged service.

## Client Apps

- Windows/macOS/Linux: [OpenVPN Connect](https://openvpn.net/client/)
- iOS: [OpenVPN Connect for iOS](https://apps.apple.com/app/openvpn-connect-openvpn-app/id590379981)
- Android: [OpenVPN Connect for Android](https://play.google.com/store/apps/details?id=net.openvpn.openvpn)
