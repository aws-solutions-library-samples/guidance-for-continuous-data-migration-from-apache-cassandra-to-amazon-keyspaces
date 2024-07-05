#!/bin/bash

# Get the parameters from stack_resource_output file
ec2_id=$(cat stack_resources_output | grep kafkaclinetinstance | awk '{print $2}')
cassandraec2one=$(cat stack_resources_cassandra_output | grep CassandraInstanceOne | awk '{print $2}')
cassandraec2two=$(cat stack_resources_cassandra_output | grep CassandraInstanceTwo | awk '{print $2}')
cassandraec2three=$(cat stack_resources_cassandra_output | grep CassandraInstanceThree | awk '{print $2}')
vpc_id=$(cat stack_resources_output | grep keyspacesVPCId | awk '{print $2}')
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
 
# Delete Cassandra kafka client instance
delete_ec2=$(aws ec2 terminate-instances --instance-ids "$ec2_id")

# Delete Cassandra cluster EC2 instances
delete_nodeone=$(aws ec2 terminate-instances --instance-ids "$cassandraec2one")
delete_nodetwo=$(aws ec2 terminate-instances --instance-ids "$cassandraec2two")
delete_nodethree=$(aws ec2 terminate-instances --instance-ids "$cassandraec2three")

# Delete Amazon Keyspaces Vpc endpoint
delete_vpc_endpnts=$(aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$vpc_id")

# Delete MSK connect plugin and connector
plugin_arn=$(aws kafkaconnect --region $AWS_REGION list-custom-plugins | grep customPluginArn | grep kafka-keyspaces-sink-plugin | awk '{print $2}' | tr -d '"' | tr -d ',')
keyspaces_connect_arn=$(aws kafkaconnect --region $AWS_REGION list-connectors | grep kafka-AmazonKeyspaces-sink-connector | grep connectorArn | awk '{print $2}' | tr -d '"' | tr -d ',')
cassandra_connect_arn=$(aws kafkaconnect --region $AWS_REGION list-connectors | grep kafka-cassandra-sink-connector | grep connectorArn | awk '{print $2}' | tr -d '"' | tr -d ',')

# if $keyspaces_connect_arn
delete_keyspaces_connector=$(aws kafkaconnect delete-connector --connector-arn "$keyspaces_connect_arn")
# fi

# if $cassandra_connect_arn
delete_cassandra_connector=$(aws kafkaconnect delete-connector --connector-arn "$cassandra_connect_arn")
# fi

# if $plugin_arn
#delete_custom_plugin=$(aws kafkaconnect delete-custom-plugin --custom-plugin-arn "$plugin_arn")
# fi

ec2_status_query="aws ec2 describe-instances --query "Reservations[*].Instances[*].InstanceId" --filters "Name=instance-state-name,Values=terminated" --region $AWS_REGION --output text"


aws s3 rm s3://msk-ks-cass-$AWS_ACCOUNT_ID --recursive

sleep 60

aws s3 rb s3://msk-ks-cass-$AWS_ACCOUNT_ID

# set Keyspaces user name

USER_NAME="ks-user"

# Delete all inline policies of ks-user
INLINE_POLICIES=$(aws iam list-user-policies --user-name $USER_NAME --query "PolicyNames" --output text)
for policy_name in $INLINE_POLICIES; do
  aws iam delete-user-policy --user-name $USER_NAME --policy-name $policy_name
done


# Delete service-specific credentials of ks-user
SERVICE_CREDS=$(aws iam list-service-specific-credentials --user-name $USER_NAME --query "ServiceSpecificCredentials[*].ServiceSpecificCredentialId" --output text)
for service_cred in $SERVICE_CREDS; do
  aws iam delete-service-specific-credential --user-name $USER_NAME --service-specific-credential-id $service_cred
done

# delete the IAM user
aws iam delete-user --user-name $USER_NAME

# delete custom Kafka sink plugin
delete_custom_plugin=$(aws kafkaconnect delete-custom-plugin --custom-plugin-arn "$plugin_arn")

# delete cassandra cluster stack
aws cloudformation delete-stack --stack-name cass-cluster-stack

# sleep for 120 seconds to change all cassandra instances status to Terminated
sleep 120

# Now delete all VPC, MSK and IAM stack
aws cloudformation delete-stack --stack-name msk-ks-stack

