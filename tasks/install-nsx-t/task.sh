#!/bin/bash

set -e

export TASKS_DIR=$(dirname $BASH_SOURCE)
export PIPELINE_DIR=$(cd $TASKS_DIR/../../ && pwd)
export FUNCTIONS_DIR=$(cd $PIPELINE_DIR/functions && pwd)

source $FUNCTIONS_DIR/copy_ovas.sh
source $FUNCTIONS_DIR/create_ansible_cfg.sh
source $FUNCTIONS_DIR/create_answerfile.sh
source $FUNCTIONS_DIR/create_hosts.sh
source $FUNCTIONS_DIR/create_extra_yaml_args.sh

DEBUG=""
if [ "$ENABLE_ANSIBLE_DEBUG" == "true" ]; then
  DEBUG="-vvv"
fi

# Check if NSX MGR is up or not
nsx_mgr_up_status=$(curl -s -o /dev/null -I -w "%{http_code}" -k  https://${NSX_T_MANAGER_IP}:443/login.jsp || true)

# Deploy the ovas if its not up
if [ $nsx_mgr_up_status -ne 200 ]; then
  echo "NSX Mgr not up yet, deploying the ovas followed by configuration of the NSX-T Mgr!!" 
  NSX_MGR_OVA_DEPLOYED=false
else
  echo "NSX Mgr up already, skipping deploying of the ovas!!"
  NSX_MGR_OVA_DEPLOYED=true
fi

create_hosts
create_answerfile
create_ansible_cfg
create_extra_yaml_args
create_customize_ova_params

cp hosts answerfile.yml ansible.cfg extra_yaml_args.yml customize_ova_vars.yml nsxt-ansible/.
cd nsxt-ansible

echo ""


# Deploy the ovas if its not up
if [ "$NSX_MGR_OVA_DEPLOYED" != "true" ]; then
	install_ovftool
	copy_ovas_to_OVA_ISO_PATH
	create_customize_ova_params

	ansible-playbook $DEBUG -i localhost customize_ovas.yml -e @customize_ova_vars.yml
    ansible-playbook $DEBUG -i hosts deploy_ovas.yml -e @extra_yaml_args.yml
fi

NO_OF_CONTROLLERS=$(curl -k -u "admin:$NSX_T_MANAGER_ADMIN_PWD" \
                    https://${NSX_T_MANAGER_IP}/api/v1/cluster/nodes \
                    | jq '.results[].controller_role.type' | wc -l )
if [ "$NO_OF_CONTROLLERS" -lt 2 ]; then
  ansible-playbook $DEBUG -i hosts configure_controllers.yml -e @extra_yaml_args.yml
  echo ""
fi

ansible-playbook $DEBUG -i hosts deployNsx.yml -e @extra_yaml_args.yml
STATUS=$?

echo ""


if [ -z "$SUPPORT_NSX_VMOTION" -o "$SUPPORT_NSX_VMOTION" == "false" ]; then
  echo "Skipping vmks configuration for NSX-T Mgr!!" 
  echo 'configure_vmks: False' >> answerfile.yml
  
else
  echo "Allowing vmks configuration for NSX-T Mgr!!" 
  echo 'configure_vmks: True' >> answerfile.yml
fi

echo ""

