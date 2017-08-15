#!/usr/bin/env bash
set -e

# set pwd (to make sure all variable files end up in the deployment reference dir)
mkdir -p $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE
cd $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE

# presetup (generate key kubeadm token etc.)
$PORTAL_APP_REPO_FOLDER'/bin/pre-setup'
export TF_VAR_kubeadm_token=$(cat $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/kubeadm_token')
export PRIVATE_KEY=$PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/vre.key'
export TF_VAR_ssh_key=$PORTAL_DEPLOYMENTS_ROOT/$PORTAL_DEPLOYMENT_REFERENCE'/vre.key.pub'

#
# hardcoded params
#

# gce and ostack
export TF_VAR_KuberNow_image="kubenow-v020a1"

# aws read image id from file depending on region selected
export TF_VAR_kubenow_image_id=$( grep "$TF_VAR_aws_region" "$PORTAL_APP_REPO_FOLDER/aws-images-$TF_VAR_KuberNow_image"  | awk '{print $1}' )


# gce
# workaround: -the credentials are provided as an environment variable, but KubeNow terraform
# scripts need a file. Creates an credentialsfile from the environment variable
if [ -n "$GOOGLE_CREDENTIALS" ]; then
  echo $GOOGLE_CREDENTIALS > "$PORTAL_DEPLOYMENTS_ROOT/$PORTAL_DEPLOYMENT_REFERENCE/gce_credentials_file.json"
  export TF_VAR_gce_credentials_file="$PORTAL_DEPLOYMENTS_ROOT/$PORTAL_DEPLOYMENT_REFERENCE/gce_credentials_file.json"
fi

# gce - make sure image is available in google project
if [ $KUBENOW_TERRAFORM_FOLDER = $PORTAL_APP_REPO_FOLDER'/KubeNow/gce' ]
then
   ansible-playbook -e "credentials_file_path=\"$TF_VAR_gce_credentials_file\"" "$PORTAL_APP_REPO_FOLDER/KubeNow/playbooks/import-gce-image.yml"
fi

# ostack
# make sure image is available in openstack
if [ $KUBENOW_TERRAFORM_FOLDER = "$PORTAL_APP_REPO_FOLDER/KubeNow/openstack" ] && [ -n "$LOCAL_DEPLOYMENT" ]
then
   ansible-playbook "$PORTAL_APP_REPO_FOLDER/KubeNow/playbooks/import-openstack-image.yml"
fi

# gce and aws
export TF_VAR_master_disk_size="50"
export TF_VAR_node_disk_size="100"
export TF_VAR_edge_disk_size="50"

# read cloudflare credentials from the cloned submodule private repo
if [ -z "$TF_VAR_cf_token" ]; then
   source $PORTAL_APP_REPO_FOLDER'/'phenomenal-cloudflare/cloudflare_token_phenomenal.cloud.sh
fi
export TF_VAR_cf_subdomain=$TF_VAR_cluster_prefix
domain=$TF_VAR_cf_subdomain'.'$TF_VAR_cf_zone

# Deploy cluster with terraform
terraform get $KUBENOW_TERRAFORM_FOLDER
terraform apply --state=$PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/terraform.tfstate' $KUBENOW_TERRAFORM_FOLDER

# Provision nodes with ansible
export ANSIBLE_HOST_KEY_CHECKING=False
nodes_count=$(($TF_VAR_node_count+$TF_VAR_edge_count+1)) # +1 because master is also one node
ansible_inventory_file=$PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/inventory'

# deploy KubeNow core stack
ansible-playbook -i $ansible_inventory_file \
                 --key-file $PRIVATE_KEY \
                 -e "nodes_count=$nodes_count" \
                 -e "cf_mail=$TF_VAR_cf_mail" \
                 -e "cf_token=$TF_VAR_cf_token" \
                 -e "cf_zone=$TF_VAR_cf_zone" \
                 -e "cf_subdomain=$TF_VAR_cf_subdomain" \
                 $PORTAL_APP_REPO_FOLDER'/KubeNow/playbooks/install-core.yml'

# wait for all pods in core stack to be ready
ansible-playbook -i $ansible_inventory_file \
                 --key-file $PRIVATE_KEY \
                 $PORTAL_APP_REPO_FOLDER'/playbooks/wait_for_all_pods_ready.yml'

# deploy phenomenal-pvc
ansible-playbook -i $ansible_inventory_file \
                 --key-file $PRIVATE_KEY \
                 "$PORTAL_APP_REPO_FOLDER/playbooks/phenomenal_pvc/main.yml"

# deploy jupyter
ansible-playbook -i $ansible_inventory_file \
                 -e "domain=$domain" \
                 -e "jupyter_chart_version=0.1.1" \
                 -e "jupyter_image_tag=:v387f29b6ca83_cv0.4.7" \
                 -e "jupyter_password=$TF_VAR_jupyter_password" \
                 -e "jupyter_pvc=galaxy-pvc" \
                 -e "jupyter_resource_req_cpu=200m" \
                 -e "jupyter_resource_req_memory=1G" \
                 --key-file $PRIVATE_KEY \
                 $PORTAL_APP_REPO_FOLDER'/playbooks/jupyter.yml'
                 
# deploy luigi
ansible-playbook -i $ansible_inventory_file \
                 -e "domain=$domain" \
                 --key-file $PRIVATE_KEY \
                 $PORTAL_APP_REPO_FOLDER'/playbooks/luigi/main.yml'

# deploy galaxy
$PORTAL_APP_REPO_FOLDER'/bin/generate-galaxy-api-key'
galaxy_api_key=$(cat $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/galaxy_api_key')
ansible-playbook -i $ansible_inventory_file \
                 -e "domain=$domain" \
                 -e "galaxy_chart_version=0.3.0" \
                 -e "galaxy_image_tag=:rc_v17.05-pheno_cv1.1.93" \
                 -e "galaxy_admin_password=$TF_VAR_galaxy_admin_password" \
                 -e "galaxy_admin_email=$TF_VAR_galaxy_admin_email" \
                 -e "galaxy_api_key=$galaxy_api_key" \
                 -e "galaxy_pvc=galaxy-pvc" \
                 -e "postgres_pvc=false" \
                 --key-file $PRIVATE_KEY \
                 $PORTAL_APP_REPO_FOLDER'/playbooks/galaxy.yml'
                                                              
# wait until jupyter is up and do git clone data into the container
ansible-playbook -i $ansible_inventory_file \
                 --key-file $PRIVATE_KEY \
                 $PORTAL_APP_REPO_FOLDER'/playbooks/git_clone_mtbls233.yml'
                                                       
# wait for jupyter notebook http response != Bad Gateway
jupyter_url="http://notebook.$domain"
ansible-playbook -i $ansible_inventory_file \
                 -e "name=jupyter-notebook" \
                 -e "url=$jupyter_url" \
                 $PORTAL_APP_REPO_FOLDER'/playbooks/wait_for_http_not_down.yml'
                 
# wait for luigi http response != Bad Gateway
luigi_url="http://luigi.$domain"
ansible-playbook -i $ansible_inventory_file \
                 -e "name=luigi" \
                 -e "url=$luigi_url" \
                 $PORTAL_APP_REPO_FOLDER'/playbooks/wait_for_http_not_down.yml'
                 
# wait for galaxy http response 200 OK
galaxy_url="http://galaxy.$domain"
ansible-playbook -i $ansible_inventory_file \
                 -e "name=galaxy" \
                 -e "url=$galaxy_url" \
                 $PORTAL_APP_REPO_FOLDER'/playbooks/wait_for_http_ok.yml'
