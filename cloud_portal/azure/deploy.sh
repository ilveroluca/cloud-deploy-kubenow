#!/usr/bin/env bash
set -e

# provider specific
export PROVIDER="azure"

"$PORTAL_APP_REPO_FOLDER/cloud_portal/shared/deploy.sh"