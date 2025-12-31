#!/bin/bash
set -euo pipefail

############################################
# Access AWS credentials from environment variables
############################################
: "${AWS_ACCESS_KEY_ID:?Missing AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Missing AWS_SECRET_ACCESS_KEY}"
: "${AWS_DEFAULT_REGION:?Missing AWS_DEFAULT_REGION}"

AWS="aws --region $AWS_DEFAULT_REGION"

############################################
# Initialize a session using your default profile
############################################
# Already handled by AWS CLI with exported env variables

############################################
# Function to retrieve VPC IDs based on CIDR block
############################################
get_vpc_id() {
  local CIDR="$1"
  $AWS ec2 describe-vpcs \
    --query "Vpcs[?CidrBlock=='$CIDR'].VpcId" \
    --output text
}

############################################
# Define CIDR blocks for Lab and Shared VPCs
############################################
LAB_VPC_CIDR="10.0.0.0/16"
SHARED_VPC_CIDR="10.0.5.0/16"

############################################
# Retrieve VPC IDs
############################################
LAB_VPC_ID=$(get_vpc_id "$LAB_VPC_CIDR")
SHARED_VPC_ID=$(get_vpc_id "$SHARED_VPC_CIDR")

############################################
# Print VPC IDs
############################################
echo "Lab VPC ID: $LAB_VPC_ID"
echo "Shared VPC ID: $SHARED_VPC_ID"

############################################
# Check if VPC IDs were found
############################################
if [[ -z "$LAB_VPC_ID" || -z "$SHARED_VPC_ID" ]]; then
  echo "ERROR: Lab or Shared VPC not found"
  exit 1
fi

############################################
# Create VPC peering connection
############################################
PEERING_ID=$(aws ec2 describe-vpc-peering-connections \
  --query "VpcPeeringConnections[?RequesterVpcInfo.VpcId=='$LAB_VPC_ID' && AccepterVpcInfo.VpcId=='$SHARED_VPC_ID'].VpcPeeringConnectionId" \
  --output text)

if [[ -z "$PEERING_ID" ]]; then
  PEERING_ID=$(aws ec2 create-vpc-peering-connection \
    --vpc-id "$LAB_VPC_ID" \
    --peer-vpc-id "$SHARED_VPC_ID" \
    --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=Lab-Peer}]" \
    --query "VpcPeeringConnection.VpcPeeringConnectionId" \
    --output text)
  echo "Created peering connection: $PEERING_ID"
else
  echo "Using existing peering connection: $PEERING_ID"
fi

############################################
# List all VPCs for debugging purposes
############################################
$AWS ec2 describe-vpcs --query "Vpcs[].{ID:VpcId,CIDR:CidrBlock}" --output table

############################################
# Step 1: Retrieve the AWS Account ID
############################################
ACCOUNT_ID=$($AWS sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

############################################
# Step 2: Retrieve all VPCs in the account
############################################
$AWS ec2 describe-vpcs --query "Vpcs[].VpcId" --output table

############################################
# Step 3: Retrieve all route tables in the account
############################################
$AWS ec2 describe-route-tables --query "RouteTables[].{RT:RouteTableId,VPC:VpcId}" --output table

############################################
# Step 4: Retrieve all VPC peering connections in the account
############################################
$AWS ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[].{ID:VpcPeeringConnectionId,Status:Status.Code}" --output table

############################################
# Step 2: Accept the VPC Peering Connection
############################################
STATUS=$($AWS ec2 describe-vpc-peering-connections \
  --vpc-peering-connection-ids "$PEERING_ID" \
  --query "VpcPeeringConnections[0].Status.Code" --output text)

if [[ "$STATUS" == "pending-acceptance" ]]; then
  $AWS ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PEERING_ID"
  echo "Peering accepted: $PEERING_ID"
fi

############################################
# Step 3: Retrieve Route Tables for both VPCs
############################################
LAB_RTS=$($AWS ec2 describe-route-tables --filters Name=vpc-id,Values="$LAB_VPC_ID" --query "RouteTables[].RouteTableId" --output text)
SHARED_RTS=$($AWS ec2 describe-route-tables --filters Name=vpc-id,Values="$SHARED_VPC_ID" --query "RouteTables[].RouteTableId" --output text)

############################################
# Step 4: Add routes to the route tables
############################################
add_routes() {
  local RTS="$1"
  local DEST="$2"
  for RT in $RTS; do
    $AWS ec2 create-route --route-table-id "$RT" --destination-cidr-block "$DEST" --vpc-peering-connection-id "$PEERING_ID" 2>/dev/null || true
  done
}

add_routes "$LAB_RTS" "$SHARED_VPC_CIDR"
add_routes "$SHARED_RTS" "$LAB_VPC_CIDR"

############################################
# Step 5: Create CloudWatch Log Group for Flow Logs
############################################
LOG_GROUP="ShareVPCFlowLogs"
$AWS logs create-log-group --log-group-name "$LOG_GROUP" 2>/dev/null || true

############################################
# Step 6: Create Flow Logs
############################################
FLOW_ROLE="vpc-flow-logs-Role"
$AWS ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids "$LAB_VPC_ID" "$SHARED_VPC_ID" \
  --traffic-type ALL \
  --log-group-name "$LOG_GROUP" \
  --deliver-logs-permission-arn "arn:aws:iam::$ACCOUNT_ID:role/$FLOW_ROLE" \
  2>/dev/null || true

############################################
# Function to retrieve flow logs from the specified log group
############################################
get_flow_logs() {
  local LOG_GROUP_NAME="$1"
  local START_TIME="$2"
  local END_TIME="$3"

  QUERY_ID=$($AWS logs start-query \
    --log-group-name "$LOG_GROUP_NAME" \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    --query-string "fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, protocol, action | sort @timestamp desc | limit 100" \
    --query 'queryId' --output text)

  while true; do
    STATUS=$($AWS logs get-query-results --query-id "$QUERY_ID" --query 'status' --output text)
    [[ "$STATUS" == "Complete" ]] && break
    echo "Waiting for query to complete..."
    sleep 1
  done

  $AWS logs get-query-results --query-id "$QUERY_ID" --output json
}

############################################
# Fetch flow logs
############################################
END_TIME=$(date +%s)
START_TIME=$((END_TIME - 3600))
FLOW_LOGS=$(get_flow_logs "$LOG_GROUP" "$START_TIME" "$END_TIME")
echo "VPC Flow Logs Analysis:"
echo "$FLOW_LOGS" | jq -r '.results[] | "Timestamp: \(.[] | select(.field=="@timestamp").value), Source: \(.[] | select(.field=="srcAddr").value), Destination: \(.[] | select(.field=="dstAddr").value), SrcPort: \(.[] | select(.field=="srcPort").value), DstPort: \(.[] | select(.field=="dstPort").value), Protocol: \(.[] | select(.field=="protocol").value), Action: \(.[] | select(.field=="action").value)"'

############################################
# Function to retrieve CloudWatch log streams
############################################
LOG_STREAMS=$($AWS logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime \
  --descending \
  --limit 5 \
  --query "logStreams[].logStreamName" \
  --output text)

############################################
# Function to get log events from a specific log stream
############################################
for STREAM in $LOG_STREAMS; do
  echo "Log events from stream: $STREAM"
  $AWS logs get-log-events --log-group-name "$LOG_GROUP" --log-stream-name "$STREAM" --start-from-head --limit 5 --output json
done
