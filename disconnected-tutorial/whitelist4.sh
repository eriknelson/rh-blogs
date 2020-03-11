#!/bin/bash
_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export WHITELIST_PATCH="{\"spec\":{\"registrySources\":{\"insecureRegistries\":[\"$REGISTRY_ROUTE\"]}}}"
oc patch images.config.openshift.io/cluster -p="$WHITELIST_PATCH" --type=merge
