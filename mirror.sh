#!/bin/bash
_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
oc adm catalog mirror \
  --insecure=true \
  $REGISTRY_ROUTE/appregistries/redhat-operators:v1 \
  $REGISTRY_ROUTE
