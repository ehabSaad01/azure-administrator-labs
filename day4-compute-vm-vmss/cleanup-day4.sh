#!/usr/bin/env bash
set -euo pipefail
RESOURCE_GROUP="rg-day4-compute"
az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
echo "Delete requested for ${RESOURCE_GROUP}."
