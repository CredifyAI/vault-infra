#cloud-config

package_update: true
package_upgrade: true

packages:
  - wget
  - gpg
  - apt-transport-https
  - ca-certificates
  - software-properties-common

runcmd:
  - wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
  - apt update -y
  - sudo apt-get install -y certbot python3-certbot vault
  - certbot certonly --standalone -d vault.lokesh.cloud --non-interactive --agree-tos -m chlokesh1306@gmail.com --pre-hook "systemctl stop vault" --post-hook "systemctl start vault && cp /etc/letsencrypt/live/vault.lokesh.cloud/fullchain.pem /opt/vault/tls/tls.crt && cp /etc/letsencrypt/live/vault.lokesh.cloud/privkey.pem /opt/vault/tls/tls.key"
  - systemctl enable vault
  - systemctl start vault
  - systemctl status vault
