#!/bin/bash

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
  - apt update
  - apt install -y vault
  - systemctl enable vault
  - systemctl start vault
  - systemctl status vault

