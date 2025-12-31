import boto3
import time
import datetime 
import os
# Access AWS credentials from environment variables
aws_access_key_id = os.getenv('AWS_ACCESS_KEY_ID')
aws_secret_access_key = os.getenv('AWS_SECRET_ACCESS_KEY')
aws_default_region = os.getenv('AWS_DEFAULT_REGION')
if not aws_default_region:
    raise RuntimeError("AWS_DEFAULT_REGION is not set")

session = boto3.Session(
    aws_access_key_id=aws_access_key_id,
    aws_secret_access_key=aws_secret_access_key,
    region_name=aws_default_region
)


# Initialize a session using your default profile
ec2_client = session.client('ec2')
logs_client = session.client('logs')
sts_client = session.client('sts')

# Function to retrieve VPC IDs based on CIDR block
def get_vpc_id(cidr_block):
    vpcs = ec2_client.describe_vpcs()['Vpcs']
    for vpc in vpcs:
        if vpc['CidrBlock'] == cidr_block:
            return vpc['VpcId']
    return None


# Define CIDR blocks for Lab and Shared VPCs
lab_vpc_cidr = '10.0.0.0/16'
shared_vpc_cidr = '10.0.5.0/16'


# Retrieve VPC IDs
lab_vpc_id = get_vpc_id(lab_vpc_cidr)
shared_vpc_id = get_vpc_id(shared_vpc_cidr)


# Print VPC IDs
print(f"Lab VPC ID: {lab_vpc_id}")
print(f"Shared VPC ID: {shared_vpc_id}")



# Check if VPC IDs were found
if not lab_vpc_id or not shared_vpc_id:
    print("Lab VPC or Shared VPC not found. Please check the CIDR blocks.")
else:
    
# Create VPC peering connection
    try:
        peering_connection = ec2_client.create_vpc_peering_connection(
            VpcId=lab_vpc_id,
            PeerVpcId=shared_vpc_id
        )
        peering_connection_id = peering_connection['VpcPeeringConnection']['VpcPeeringConnectionId']
        print(f"VPC Peering created: {peering_connection_id}")
    
    except ec2_client.exceptions.ClientError as e:
        if 'VpcPeeringConnectionAlreadyExists' in str(e):
            existing = ec2_client.describe_vpc_peering_connections(
                Filters=[
                    {'Name': 'requester-vpc-info.vpc-id', 'Values': [lab_vpc_id]},
                    {'Name': 'accepter-vpc-info.vpc-id', 'Values': [shared_vpc_id]}
                ]
            )
            connections = existing.get('VpcPeeringConnections', [])
            if not connections:
                raise RuntimeError("Existing VPC peering not found")
            peering_connection_id = connections[0]['VpcPeeringConnectionId']
            
            print(f"Using existing VPC Peering: {peering_connection_id}")
        else:
            raise



# List all VPCs for debugging purposes
print("Listing all VPCs:")

vpcs = ec2_client.describe_vpcs()['Vpcs']
for vpc in vpcs:
    print(f"VPC ID: {vpc['VpcId']}, CIDR Block: {vpc['CidrBlock']}")
    # Assuming route tables need to be configured here...
    # Add your code for route table updates and flow logs here.

# Step 1: Retrieve the AWS Account ID
account_id = sts_client.get_caller_identity()['Account']
print(f"AWS Account ID: {account_id}")



# Step 2: Retrieve all VPCs in the account
vpcs = ec2_client.describe_vpcs()['Vpcs']
vpc_ids = [vpc['VpcId'] for vpc in vpcs]
print("VPC IDs:")
for vpc_id in vpc_ids:
    print(f" - {vpc_id}")
    print()




# Step 3: Retrieve all route tables in the account
route_tables = ec2_client.describe_route_tables()['RouteTables']
print("Route Tables:")
for rt in route_tables:
    print(f" - Route Table ID: {rt['RouteTableId']}, VPC ID: {rt['VpcId']}")



# Step 4: Retrieve all VPC peering connections in the account
peering_connections = ec2_client.describe_vpc_peering_connections()['VpcPeeringConnections']
print("VPC Peering Connections:")
for pc in peering_connections:
    print(f" - Peering Connection ID: {pc['VpcPeeringConnectionId']}, Status: {pc['Status']['Code']}, VPCs: {pc['AccepterVpcInfo']['VpcId']} <-> {pc['RequesterVpcInfo']['VpcId']}")

# Assign Lab VPC based on its CIDR block
lab_vpc = next((vpc for vpc in vpcs if vpc['CidrBlock'] == '10.0.0.0/16'), None)
if lab_vpc:
    lab_vpc_id = lab_vpc['VpcId']
    print(f"Lab VPC ID: {lab_vpc_id}")
else:
    lab_vpc_id = None
    print("Lab VPC not found.")
    
    




# Assign Shared VPC based on its CIDR block
shared_vpc = next((vpc for vpc in vpcs if vpc['CidrBlock'] == shared_vpc_cidr), None)
if shared_vpc:
    shared_vpc_id = shared_vpc['VpcId']
    print(f"Shared VPC ID: {shared_vpc_id}")
else:
    shared_vpc_id = None
    print("Shared VPC not found.")


if not lab_vpc_id or not shared_vpc_id:
    raise RuntimeError("VPC IDs not resolved — stopping execution")
# Step 2: Accept the VPC Peering Connection
try:
    ec2_client.get_waiter('vpc_peering_connection_exists').wait(
    VpcPeeringConnectionIds=[peering_connection_id]
    )

    ec2_client.accept_vpc_peering_connection(
        VpcPeeringConnectionId=peering_connection_id
    )
    print(f"VPC Peering accepted: {peering_connection_id}")

except ec2_client.exceptions.ClientError as e:
    if 'OperationNotPermitted' in str(e):
        print("VPC Peering already accepted")
    else:
        raise



# Step 3: Retrieve Route Tables for both VPCs
route_tables_lab = ec2_client.describe_route_tables(
    Filters=[{'Name': 'vpc-id', 'Values': [lab_vpc_id]}]
)['RouteTables']

route_tables_shared = ec2_client.describe_route_tables(
    Filters=[{'Name': 'vpc-id', 'Values': [shared_vpc_id]}]
)['RouteTables']


# Step 4: Add routes to the route tables
def add_routes(vpc_id, destination_cidr):
    route_tables = ec2_client.describe_route_tables(
        Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}]
    )['RouteTables']

    for rt in route_tables:
        try:
            ec2_client.create_route(
                RouteTableId=rt['RouteTableId'],
                DestinationCidrBlock=destination_cidr,
                VpcPeeringConnectionId=peering_connection_id
            )
            print(f"Route added: {rt['RouteTableId']} -> {destination_cidr}")

        except ec2_client.exceptions.ClientError as e:
            if 'RouteAlreadyExists' in str(e):
                print(f"Route already exists: {rt['RouteTableId']}")
            else:
                raise


print("Adding routes...")

if lab_vpc_id and shared_vpc_id:
    add_routes(lab_vpc_id, shared_vpc_cidr)
    add_routes(shared_vpc_id, lab_vpc_cidr)
else:
    raise RuntimeError("Route creation skipped — missing VPC IDs")

print("VPC Peering & routing configuration completed")


# Step 5: Create CloudWatch Log Group for Flow Logs
flow_logs_role = 'vpc-flow-logs-Role'

log_group_name = 'ShareVPCFlowLogs'

try:
    logs_client.create_log_group(LogGroupName=log_group_name)
    print(f"Created log group: {log_group_name}")
except logs_client.exceptions.ResourceAlreadyExistsException:
    print(f"Log group already exists: {log_group_name}")





# Step 6: Create Flow Logs
try:
    iam = session.client('iam')
    iam.get_role(RoleName=flow_logs_role)
    flow_log_response = ec2_client.create_flow_logs(
        ResourceIds=[lab_vpc_id, shared_vpc_id],
        ResourceType='VPC',
        TrafficType='ALL',
        LogGroupName=log_group_name,
        DeliverLogsPermissionArn=f'arn:aws:iam::{account_id}:role/{flow_logs_role}'
    )

    if flow_log_response.get('Unsuccessful'):
        print("Some flow logs failed:", flow_log_response['Unsuccessful'])
    else:
        print("Flow Logs created:", flow_log_response['FlowLogIds'])

except ec2_client.exceptions.ClientError as e:
    print(f"Flow logs error: {e.response['Error']['Message']}")

time.sleep(60)

# Function to retrieve flow logs from the specified log group
def get_flow_logs(log_group_name, start_time, end_time):
    query = """
    fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, protocol, action
    | sort @timestamp desc
    | limit 100
    """

    start_query = logs_client.start_query(
        logGroupName=log_group_name,
        startTime=start_time,
        endTime=end_time,
        queryString=query
    )

    query_id = start_query['queryId']
    response = None

    for _ in range(30):  # max 30 seconds
        time.sleep(1)
        response = logs_client.get_query_results(queryId=query_id)
        if response['status'] == 'Complete':
            return response['results']

    raise TimeoutError("CloudWatch query timed out")

end_time = int(datetime.datetime.now().timestamp())
start_time = end_time - 3600

# Fetch flow logs
try:
    flow_logs = get_flow_logs(log_group_name, start_time, end_time)
except TimeoutError:
    print("No flow logs available yet")
    flow_logs = []


# Print retrieved flow logs
print("VPC Flow Logs Analysis:")
for log in flow_logs:
    record = {item['field']: item['value'] for item in log}

    print(
        f"Timestamp: {record.get('@timestamp')}, "
        f"Source IP: {record.get('srcAddr')}, "
        f"Destination IP: {record.get('dstAddr')}, "
        f"Source Port: {record.get('srcPort')}, "
        f"Destination Port: {record.get('dstPort')}, "
        f"Protocol: {record.get('protocol')}, "
        f"Action: {record.get('action')}"
    )

# Function to retrieve CloudWatch log streams
def get_log_streams(log_group_name):
    try:
        response = logs_client.describe_log_streams(
            logGroupName=log_group_name,
            orderBy='LastEventTime',
            descending=True,
            limit=5  # Limit the number of log streams to retrieve
        )
        log_streams = response['logStreams']
        if log_streams:
            print(f"Log streams in log group {log_group_name}:")
            for stream in log_streams:
                print(f"Log Stream: {stream['logStreamName']}, Last Event: {stream['lastIngestionTime']}")
        else:
            print("No log streams found.")
    except Exception as e:
        print(f"Error retrieving log streams: {e}")
    return log_streams if 'log_streams' in locals() else []

# Function to get log events from a specific log stream
def get_log_events(log_group_name, log_stream_name):
    try:
        response = logs_client.get_log_events(
            logGroupName=log_group_name,
            logStreamName=log_stream_name,
            startFromHead=True
        )
        events = response['events']
        print(f"Log events from {log_stream_name}:")
        for event in events:
            print(f"Timestamp: {event['timestamp']}, Message: {event['message']}")
    except Exception as e:
        print(f"Error retrieving log events: {e}")
        
# Get Log Streams from the specified log group
log_streams = get_log_streams(log_group_name) 
log_stream_name = log_streams[0]['logStreamName'] if log_streams else None # You can get the name from the log streams list
if log_stream_name:
    get_log_events(log_group_name, log_stream_name)
    
    

