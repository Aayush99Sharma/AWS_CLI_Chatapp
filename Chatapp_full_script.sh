#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Load environment variables
source ./env.sh

# Step 1: Create VPC
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --region $REGION --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=VPC}]" --query 'Vpc.VpcId' --output text)
echo "VPC created with ID: $VPC_ID"

# Step 2: Create Subnets
echo "Creating Subnets..."
SUBNET_PUBLIC_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET1_CIDR --availability-zone $ZONE1 --region $REGION --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=PublicSubnet1}]" --query 'Subnet.SubnetId' --output text)
SUBNET_PUBLIC_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET2_CIDR --availability-zone $ZONE2 --region $REGION --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=PublicSubnet2}]" --query 'Subnet.SubnetId' --output text)
SUBNET_PRIVATE_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET1_CIDR --availability-zone $ZONE2 --region $REGION --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=PrivateSubnet1}]" --query 'Subnet.SubnetId' --output text)
SUBNET_PRIVATE_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET2_CIDR --availability-zone $ZONE1 --region $REGION --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=PrivateSubnet2}]" --query 'Subnet.SubnetId' --output text)
echo "Subnets created: $SUBNET_PUBLIC_1, $SUBNET_PUBLIC_2, $SUBNET_PRIVATE_1, $SUBNET_PRIVATE_2"

# Step 3: Create Route Tables
echo "Creating Route Tables..."
ROUTE_TABLE_PUBLIC=$(aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=PublicRouteTable}]" --query 'RouteTable.RouteTableId' --output text)
ROUTE_TABLE_PRIVATE=$(aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=PrivateRouteTable}]" --query 'RouteTable.RouteTableId' --output text)
echo "Route tables created: Public - $ROUTE_TABLE_PUBLIC, Private - $ROUTE_TABLE_PRIVATE"

# Step 4: Associate Route Tables with Subnets
echo "Associating Route Tables with Subnets..."
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_PUBLIC --subnet-id $SUBNET_PUBLIC_1 --region $REGION
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_PUBLIC --subnet-id $SUBNET_PUBLIC_2 --region $REGION
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_PRIVATE --subnet-id $SUBNET_PRIVATE_1 --region $REGION
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_PRIVATE --subnet-id $SUBNET_PRIVATE_2 --region $REGION
echo "Route tables associated with respective subnets"

# Step 5: Create and Attach Internet Gateway
echo "Creating and attaching Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway --region $REGION --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=InternetGateway}]" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION
aws ec2 create-route --route-table-id $ROUTE_TABLE_PUBLIC --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION
echo "Internet Gateway created and attached with ID: $IGW_ID"

# Step 6: Create NAT Gateway
echo "Allocating Elastic IP for NAT Gateway..."
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --region $REGION --query 'AllocationId' --output text)

echo "Creating NAT Gateway..."
NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id $SUBNET_PUBLIC_1 --allocation-id $EIP_ALLOC_ID --region $REGION --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=NATGateway}]" --query 'NatGateway.NatGatewayId' --output text)
echo "NAT Gateway creation in progress. Waiting for completion..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID --region $REGION
aws ec2 create-route --route-table-id $ROUTE_TABLE_PRIVATE --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID --region $REGION
echo "NAT Gateway created and attached with ID: $NAT_GW_ID"

# Step 7: Create AMIs
#echo "Creating AMIs for frontend and backend instances..."
#FRONTEND_AMI=$(aws ec2 create-image --instance-id $FRONTEND_INSTANCE_ID --name "Frontend_AMI" --description "Frontend server AMI" --region $REGION --query 'ImageId' --output text)
#BACKEND_AMI=$(aws ec2 create-image --instance-id $BACKEND_INSTANCE_ID --name "Backend_AMI" --description "Backend server AMI" --region $REGION --query 'ImageId' --output text)
#echo "AMIs created: Frontend AMI - $FRONTEND_AMI, Backend AMI - $BACKEND_AMI"

# Step 8: Create Key Pairs
#echo "Creating Key Pairs..."
#aws ec2 create-key-pair --key-name "FrontendKey" --query 'KeyMaterial' --output text > FrontendKey.pem
#sudo chmod 400 FrontendKey.pem
#aws ec2 create-key-pair --key-name "BackendKey" --query 'KeyMaterial' --output text > BackendKey.pem
#sudo chmod 400 BackendKey.pem
#echo "Key pairs created and permissions set"

# Frontend Security Group
FRONTEND_SG=$(aws ec2 create-security-group --group-name Frontend_SG --description "Frontend security group" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION

aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION

aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG --protocol tcp --port 8000 --cidr 0.0.0.0/0 --region $REGION

echo "Frontend Security Group created with ID: $FRONTEND_SG"

# Backend Security Group
BACKEND_SG=$(aws ec2 create-security-group --group-name Backend_SG --description "Backend security group" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $BACKEND_SG --protocol tcp --port 8000 --source-group $FRONTEND_SG --region $REGION

aws ec2 authorize-security-group-ingress --group-id $BACKEND_SG --protocol tcp --port 22 --source-group $FRONTEND_SG --region $REGION

aws ec2 authorize-security-group-ingress --group-id $BACKEND_SG --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION

aws ec2 authorize-security-group-ingress --group-id $BACKEND_SG --protocol tcp --port 8000 --cidr 0.0.0.0/0 --region $REGION

# Allow traffic from backend to frontend
aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG --protocol tcp --port 22 --source-group $BACKEND_SG --region $REGION
echo "Backend Security Group created with ID: $BACKEND_SG"

# Step 9: Launch EC2 Instances
echo "Launching Frontend and Backend instances..."
echo "Launching Frontend instance..."
FRONTEND_INSTANCE_ID=$(aws ec2 run-instances --image-id $FRONTEND_AMI --count 1 --instance-type t2.micro --key-name $FRONTEND_KEY --security-group-ids $FRONTEND_SG --subnet-id $SUBNET_PUBLIC_1 --region $REGION --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":8}}]' --query 'Instances[0].InstanceId' --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Frontend_Instance}]" --output text)
echo "Frontend instance launched with ID: $FRONTEND_INSTANCE_ID"
# Backend instance
BACKEND_INSTANCE_ID=$(aws ec2 run-instances --image-id $BACKEND_AMI --count 1 --instance-type t2.micro --key-name $BACKEND_KEY --subnet-id $SUBNET_PRIVATE_1 --security-group-ids $BACKEND_SG --region $REGION --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Backend_Instance}]" --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":8}}]" --output text)
echo "Backend instance launched with ID: $BACKEND_INSTANCE_ID"
echo "EC2 instances launched"

# Step 10: Set up RDS Instance
echo "Creating security group and subnet group for RDS..."
RDS_SG=$(aws ec2 create-security-group --group-name RDS_SG --description "RDS security group" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $RDS_SG --protocol tcp --port 3306 --source-group $BACKEND_SG --region $REGION

#Allow MySQL/Aurora (Port 3306) from Database security group  at backend:
aws ec2 authorize-security-group-ingress --group-id $BACKEND_SG --protocol tcp --port 3306 --source-group $RDS_SG --region $REGION

# Creating Subnet group
echo "Creating Subnet group..."
aws rds create-db-subnet-group --db-subnet-group-name DBSubnetGroup --db-subnet-group-description "DB subnet group for RDS" --subnet-ids $SUBNET_PRIVATE_1 $SUBNET_PRIVATE_2 --region $REGION

echo "Launching RDS instance..."
aws rds create-db-instance --db-instance-identifier $RDS_INSTANCE_NAME --db-instance-class $RDS_INSTANCE_TYPE --engine mysql --allocated-storage 20 --master-username $DB_USERNAME --master-user-password $DB_PASSWORD --vpc-security-group-ids $RDS_SG --db-subnet-group-name DBSubnetGroup --backup-retention-period 7 --no-publicly-accessible --deletion-protection --region $REGION --output text
echo "RDS instance created with security configurations"

echo "Fetching RDS Instance endpoint..."
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_NAME --query 'DBInstances[0].Endpoint.Address' --output text)
echo "RDS Endpoint Address: $RDS_ENDPOINT"

echo "Infrastructure setup completed successfully!"

echo "Creating launch templates for frontend and backend..."
aws ec2 create-launch-template --launch-template-name $FRONTEND_LAUNCH_TEM \
--launch-template-data "{
    \"ImageId\": \"$FRONTEND_AMI\",
    \"InstanceType\": \"t3.micro\",
    \"KeyName\": \"$FRONTEND_KEY\",
    \"NetworkInterfaces\": [
        {
            \"AssociatePublicIpAddress\": true,
            \"DeviceIndex\": 0,
            \"Groups\": [\"$FRONTEND_SG\"]
        }
    ]
}"

aws ec2 create-launch-template --launch-template-name $BACKEND_LAUNCH_TEM \
--launch-template-data "{
    \"ImageId\": \"$BACKEND_AMI\",
    \"InstanceType\": \"t3.micro\",
    \"KeyName\": \"$BACKEND_KEY\",
    \"NetworkInterfaces\": [
        {
            \"AssociatePublicIpAddress\": false,
            \"DeviceIndex\": 0,
            \"Groups\": [\"$BACKEND_SG\"]
        }
    ]
}"

# Step 3: Create Target Groups for Frontend and Backend
echo "Creating target groups..."
FRONTEND_TG_ARN=$(aws elbv2 create-target-group --name new-frontend-tg --protocol HTTP --port 80 --vpc-id "$VPC_ID" --target-type instance --query "TargetGroups[0].TargetGroupArn" --output text)

BACKEND_TG_ARN=$(aws elbv2 create-target-group --name new-backend-tg --protocol HTTP --port 8000 --vpc-id "$VPC_ID" --target-type instance --query "TargetGroups[0].TargetGroupArn" --output text)

# Step 4: Create Security Groups for Load Balancers
echo "Creating security groups for load balancers..."
FRONTEND_LB_SG=$(aws ec2 create-security-group --group-name Frontend_LB_SG --description "Frontend Load Balancer Security Group" --vpc-id "$VPC_ID" --query "GroupId" --output text)
BACKEND_LB_SG=$(aws ec2 create-security-group --group-name Backend_LB_SG --description "Backend Load Balancer Security Group" --vpc-id "$VPC_ID" --query "GroupId" --output text)

# Allow inbound traffic on port 80 (HTTP) for frontend and backend load balancers
aws ec2 authorize-security-group-ingress --group-id $FRONTEND_LB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $FRONTEND_LB_SG --protocol tcp --port 8000 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $FRONTEND_LB_SG --protocol tcp --port 80 --source-group $FRONTEND_SG
aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG --protocol tcp --port 80 --source-group $FRONTEND_LB_SG
aws ec2 authorize-security-group-ingress --group-id $BACKEND_LB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $BACKEND_LB_SG --protocol tcp --port 8000 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $BACKEND_SG --protocol tcp --port 8000 --source-group $BACKEND_LB_SG

# Allow internal communication on port 80 for backend load balancer
aws ec2 authorize-security-group-ingress --group-id "$BACKEND_LB_SG" --protocol tcp --port 80 --source-group "$FRONTEND_LB_SG"

# Step 5: Create Load Balancers
echo "Creating load balancers..."

# Frontend Load Balancer (Public ALB)
FRONTEND_LB_ARN=$(aws elbv2 create-load-balancer --name frontend-load-balancer --type application --scheme internet-facing --security-groups "$FRONTEND_LB_SG" --subnets "$SUBNET_PUBLIC_1" "$SUBNET_PUBLIC_2" --query "LoadBalancers[0].LoadBalancerArn" --output text)

# Backend Load Balancer (Internal ALB)
BACKEND_LB_ARN=$(aws elbv2 create-load-balancer --name backend-load-balancer --type application --scheme internal --security-groups "$BACKEND_LB_SG" --subnets "$SUBNET_PRIVATE_1" "$SUBNET_PRIVATE_2" --query "LoadBalancers[0].LoadBalancerArn" --output text)

# Step 6: Create Listeners and Associate Target Groups
echo "Creating listeners and associating target groups..."

# Frontend Load Balancer Listener
aws elbv2 create-listener --load-balancer-arn "$FRONTEND_LB_ARN" --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn="$FRONTEND_TG_ARN"

# Backend Load Balancer Listener
aws elbv2 create-listener --load-balancer-arn "$BACKEND_LB_ARN" --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn="$BACKEND_TG_ARN"

# Step 7: Create Auto Scaling Groups
echo "Creating auto scaling groups..."
# For Frontend
aws autoscaling create-auto-scaling-group --auto-scaling-group-name New_Frontend_ASG --launch-template "LaunchTemplateName=$FRONTEND_LAUNCH_TEM,Version=1" --min-size 1 --max-size 3 --desired-capacity 1 --target-group-arns $FRONTEND_TG_ARN --vpc-zone-identifier "$SUBNET_PUBLIC_1,$SUBNET_PUBLIC_2" --health-check-type ELB --health-check-grace-period 300
echo "Created auto scaling groups for frontend"

# Fro Backend
aws autoscaling create-auto-scaling-group --auto-scaling-group-name New_Backend_ASG --launch-template "LaunchTemplateName=$BACKEND_LAUNCH_TEM,Version=1" --min-size 1 --max-size 3 --desired-capacity 1 --target-group-arns $BACKEND_TG_ARN --vpc-zone-identifier "$SUBNET_PRIVATE_1,$SUBNET_PRIVATE_2" --health-check-type ELB --health-check-grace-period 300
echo "Created auto scaling groups for backend"

# Step 8: Set Target Tracking Policy for Frontend and Backend ASG
aws autoscaling put-scaling-policy --auto-scaling-group-name New_Frontend_ASG --policy-name "TargetTrackingPolicy" \
--policy-type TargetTrackingScaling --target-tracking-configuration "{
    \"PredefinedMetricSpecification\": {\"PredefinedMetricType\": \"ASGAverageCPUUtilization\"},
    \"TargetValue\": 50.0,
    \"DisableScaleIn\": true
}"

aws autoscaling put-scaling-policy --auto-scaling-group-name New_Backend_ASG --policy-name "TargetTrackingPolicy" \
--policy-type TargetTrackingScaling --target-tracking-configuration "{
    \"PredefinedMetricSpecification\": {\"PredefinedMetricType\": \"ASGAverageCPUUtilization\"},
    \"TargetValue\": 50.0,
    \"DisableScaleIn\": true
}"

echo "Launch templates, auto scaling groups, load balancers, and target groups have been successfully configured!"

