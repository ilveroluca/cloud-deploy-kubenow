#!/usr/bin/env bash

# provider speciffic
export KUBENOW_TERRAFORM_FOLDER="$PORTAL_APP_REPO_FOLDER/KubeNow/kvm"

"$PORTAL_APP_REPO_FOLDER/cloud_portal/shared/destroy.sh"
