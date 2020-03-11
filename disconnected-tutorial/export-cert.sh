#!/bin/bash
_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
openssl s_client -showcerts -servername server \
  -connect "$REGISTRY_ROUTE:443" > $_dir/private-registry.crt
