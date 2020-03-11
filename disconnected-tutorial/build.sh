#!/bin/bash
_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

oc adm catalog build \
  --appregistry-endpoint https://quay.io/cnr \
  --appregistry-org redhat-operators \
  --insecure=true \
  --to=$REGISTRY_ROUTE/appregistries/redhat-operators:v1
