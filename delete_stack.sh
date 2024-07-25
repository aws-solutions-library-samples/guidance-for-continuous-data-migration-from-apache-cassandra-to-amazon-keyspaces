#!/bin/bash

# Get the parameters from stack_resource_output file
vpc_id=$(cat stack_resources_output | grep keyspacesVPCId | awk '{print $2}')
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
 

# Delete Amazon Keyspaces Vpc endpoint
echo "Deleting Amazon Keyspaces VPC Endpoint"
delete_vpc_endpnts=$(aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$vpc_id")

# Delete MSK connect plugin and connector
plugin_arn=$(aws kafkaconnect --region $AWS_REGION list-custom-plugins | grep customPluginArn | grep kafka-keyspaces-sink-plugin | awk '{print $2}' | tr -d '"' | tr -d ',')
keyspaces_connect_arn=$(aws kafkaconnect --region $AWS_REGION list-connectors | grep kafka-AmazonKeyspaces-sink-connector | grep connectorArn | awk '{print $2}' | tr -d '"' | tr -d ',')
cassandra_connect_arn=$(aws kafkaconnect --region $AWS_REGION list-connectors | grep kafka-cassandra-sink-connector | grep connectorArn | awk '{print $2}' | tr -d '"' | tr -d ',')

# if $keyspaces_connect_arn
echo "Deleting Keyspaces Sink Connector"
delete_keyspaces_connector=$(aws kafkaconnect delete-connector --connector-arn "$keyspaces_connect_arn")
# fi

# if $cassandra_connect_arn
echo "Deleting Cassandra Sink Connector"
delete_cassandra_connector=$(aws kafkaconnect delete-connector --connector-arn "$cassandra_connect_arn")
# fi

# if $plugin_arn
#delete_custom_plugin=$(aws kafkaconnect delete-custom-plugin --custom-plugin-arn "$plugin_arn")
# fi


# Removing S3 bucket
echo "Removing S3 bucket and its files"
aws s3 rm s3://msk-ks-cass-$AWS_ACCOUNT_ID --recursive

sleep 60

aws s3 rb s3://msk-ks-cass-$AWS_ACCOUNT_ID

# set Keyspaces user name

USER_NAME="ks-user"

echo "Deleting Keyspaces user and detaching managed policies"
# Delete all managed policies of ks-user
MANAGED_POLICIES=$(aws iam list-attached-user-policies --user-name $USER_NAME --query "AttachedPolicies[].PolicyArn" --output text)

if [ -z "$MANAGED_POLICIES" ]; then
  echo "No managed policies to detach from user $USER_NAME."
else
  for policy_arn in $MANAGED_POLICIES; do
    aws iam detach-user-policy --user-name $USER_NAME --policy-arn $policy_arn
  done
fi

# Delete service-specific credentials of ks-user
SERVICE_CREDS=$(aws iam list-service-specific-credentials --user-name $USER_NAME --query "ServiceSpecificCredentials[*].ServiceSpecificCredentialId" --output text)
for service_cred in $SERVICE_CREDS; do
  aws iam delete-service-specific-credential --user-name $USER_NAME --service-specific-credential-id $service_cred
done

# delete the IAM user
aws iam delete-user --user-name $USER_NAME

# delete custom Kafka sink plugin
echo "deleting kafka plugin"
delete_custom_plugin=$(aws kafkaconnect delete-custom-plugin --custom-plugin-arn "$plugin_arn")

# delete cassandra cluster stack
echo "Deleting Cassandra Cloudformation stack"
aws cloudformation delete-stack --stack-name cass-cluster-stack

# sleep for 120 seconds to change all cassandra instances status to Terminated
sleep 120

# Now delete all VPC, MSK and IAM stack
echo "Deleting MSK cloudformation stack"
aws cloudformation delete-stack --stack-name msk-ks-stack

# Now delete the EC2 Keypair
echo "Deleting EC2 keypair"
aws ec2 delete-key-pair --key-name msk-ks-cass-kp
