#!/bin/bash


subnet_one=$(cat stack_resources_output | grep PrivateSubnetOne | awk '{print $2}')
subnet_two=$(cat stack_resources_output | grep PrivateSubnetTwo | awk '{print $2}')
subnet_three=$(cat stack_resources_output | grep PrivateSubnetThree | awk '{print $2}')
msk_sg=$(cat stack_resources_output | grep MSKSecurityGroupID | awk '{print $2}')

connect_arn=$(aws kafkaconnect --region $AWS_REGION list-custom-plugins | grep customPluginArn | grep kafka-keyspaces-sink-plugin | awk '{print $2}')
msk_arn=$(cat stack_resources_output | grep SolMSKClusterArn | awk '{print $2}')
msk_bootstrap_brokers=$(aws kafka get-bootstrap-brokers --cluster-arn $msk_arn | grep 'BootstrapBrokerString'| awk '{print $2}'| head -n 1)
msk_role_arn=$(cat stack_resources_output | grep MSKconnectRoleID | awk '{print $2}')

sed -i -e "s/subnet1/$subnet_one/" msk-keyspaces-connector.json
sed -i -e "s/subnet2/$subnet_two/" msk-keyspaces-connector.json
sed -i -e "s/subnet3/$subnet_three/" msk-keyspaces-connector.json
sed -i -e "s#plugin_arn#$connect_arn#g" msk-keyspaces-connector.json
sed -i -e "s#bootstrap_brokers#$msk_bootstrap_brokers#g" msk-keyspaces-connector.json
sed -i -e "s/msk_sg/$msk_sg/" msk-keyspaces-connector.json
sed -i -e "s#msk_role#$msk_role_arn#" msk-keyspaces-connector.json
sed -i -e "s/keyspaces_dc/$AWS_REGION/" msk-keyspaces-connector.json
sed -i -e "s/cntpt_dc/$AWS_REGION/" msk-keyspaces-connector.json

