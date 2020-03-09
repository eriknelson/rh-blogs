#!/bin/bash
_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
openssl s_client -showcerts -servername server \
  -connect "$REGISTRY_ROUTE:443" > /tmp/private-registry.crt
sudo cp /tmp/private-registry.crt /etc/pki/ca-trust/source/anchors/private-registry.crt
sudo update-ca-trust
