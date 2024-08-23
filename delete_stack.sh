#!/bin/bash

# Get the parameters from stack_resource_output file
ec2_id=$(cat stack_resources_output | grep kafkaclinetinstance | awk '{print $2}')
cassandraec2one=$(cat stack_resources_cassandra_output | grep CassandraInstanceOne | awk '{print $2}')
cassandraec2two=$(cat stack_resources_cassandra_output | grep CassandraInstanceTwo | awk '{print $2}')
cassandraec2three=$(cat stack_resources_cassandra_output | grep CassandraInstanceThree | awk '{print $2}')
vpc_id=$(cat stack_resources_output | grep keyspacesVPCId | awk '{print $2}')
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Function to disable API termination
disable_api_termination() {
  instance_id=$1
  echo "Disabling API termination for instance $instance_id"
  aws ec2 modify-instance-attribute --instance-id "$instance_id" --no-disable-api-termination
}

# Disable API termination for all instances
disable_api_termination "$ec2_id"
disable_api_termination "$cassandraec2one"
disable_api_termination "$cassandraec2two"
disable_api_termination "$cassandraec2three"

# Delete Cassandra kafka client instance
echo "Terminating Cassandra Kafka client instance $ec2_id"
delete_ec2=$(aws ec2 terminate-instances --instance-ids "$ec2_id")

# Delete Cassandra cluster EC2 instances
echo "Terminating Cassandra cluster EC2 instances"
delete_nodeone=$(aws ec2 terminate-instances --instance-ids "$cassandraec2one")
delete_nodetwo=$(aws ec2 terminate-instances --instance-ids "$cassandraec2two")
delete_nodethree=$(aws ec2 terminate-instances --instance-ids "$cassandraec2three")

# Delete Amazon Keyspaces VPC endpoint
echo "Deleting Amazon Keyspaces VPC endpoint $vpc_id"
delete_vpc_endpnts=$(aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$vpc_id")

# Delete MSK connect plugin and connector
plugin_arn=$(aws kafkaconnect --region $AWS_REGION list-custom-plugins | grep customPluginArn | grep kafka-keyspaces-sink-plugin | awk '{print $2}' | tr -d '"' | tr -d ',')
keyspaces_connect_arn=$(aws kafkaconnect --region $AWS_REGION list-connectors | grep kafka-AmazonKeyspaces-sink-connector | grep connectorArn | awk '{print $2}' | tr -d '"' | tr -d ',')
cassandra_connect_arn=$(aws kafkaconnect --region $AWS_REGION list-connectors | grep kafka-cassandra-sink-connector | grep connectorArn | awk '{print $2}' | tr -d '"' | tr -d ',')

# Delete Keyspaces connector
echo "Deleting Keyspaces connector $keyspaces_connect_arn"
delete_keyspaces_connector=$(aws kafkaconnect delete-connector --connector-arn "$keyspaces_connect_arn")

# Delete Cassandra connector
echo "Deleting Cassandra connector $cassandra_connect_arn"
delete_cassandra_connector=$(aws kafkaconnect delete-connector --connector-arn "$cassandra_connect_arn")


echo "Deleting S3 bucket contents for msk-ks-cass-$AWS_ACCOUNT_ID"
aws s3 rm s3://msk-ks-cass-$AWS_ACCOUNT_ID --recursive

sleep 60

echo "Deleting S3 bucket msk-ks-cass-$AWS_ACCOUNT_ID"
aws s3 rb s3://msk-ks-cass-$AWS_ACCOUNT_ID

# Set Keyspaces user name
USER_NAME="ks-user"

# Detach all managed policies from ks-user
echo "Detaching managed policies from user $USER_NAME"
MANAGED_POLICIES=$(aws iam list-attached-user-policies --user-name $USER_NAME --query "AttachedPolicies[*].PolicyArn" --output text)
for policy_arn in $MANAGED_POLICIES; do
  aws iam detach-user-policy --user-name $USER_NAME --policy-arn $policy_arn
done

sleep 10

# Delete all inline policies of ks-user
echo "Deleting inline policies of user $USER_NAME"
INLINE_POLICIES=$(aws iam list-user-policies --user-name $USER_NAME --query "PolicyNames" --output text)
for policy_name in $INLINE_POLICIES; do
  aws iam delete-user-policy --user-name $USER_NAME --policy-name $policy_name
done

sleep 10

# Delete service-specific credentials of ks-user
echo "Deleting service-specific credentials of user $USER_NAME"
SERVICE_CREDS=$(aws iam list-service-specific-credentials --user-name $USER_NAME --query "ServiceSpecificCredentials[*].ServiceSpecificCredentialId" --output text)
for service_cred in $SERVICE_CREDS; do
  aws iam delete-service-specific-credential --user-name $USER_NAME --service-specific-credential-id $service_cred
done

sleep 10

# Delete the IAM user
echo "Deleting IAM user $USER_NAME"
aws iam delete-user --user-name $USER_NAME

# Delete custom Kafka sink plugin
echo "Deleting custom Kafka sink plugin $plugin_arn"
delete_custom_plugin=$(aws kafkaconnect delete-custom-plugin --custom-plugin-arn "$plugin_arn")

# Delete Cassandra cluster stack
echo "Deleting Cassandra cluster stack cass-cluster-stack"
aws cloudformation delete-stack --stack-name cass-cluster-stack

# Sleep for 120 seconds to allow all Cassandra instances to terminate
echo "Waiting 120 seconds for Cassandra instances to terminate"
sleep 120

# Now delete all VPC, MSK, and IAM stack
echo "Deleting stack msk-ks-stack"
aws cloudformation delete-stack --stack-name msk-ks-stack

# Message to check CloudFormation console
echo "Stack deletion initiated for msk-ks-stack. Please check the AWS CloudFormation console for the deletion status."

# Delete EC2 key pair
echo "Deleting EC2 key pair msk-ks-cass-kp"
aws ec2 delete-key-pair --key-name "msk-ks-cass-kp"
