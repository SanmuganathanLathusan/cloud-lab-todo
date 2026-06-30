#!/bin/bash

# ==========================================
# Cloud Computing Lab 08
# CLI Deployment Script
# Student: YOUR NAME
# Student ID: YOUR ID
# ==========================================

set -e

REGION="ap-south-1"
CLUSTER_NAME="cloud-lab-cluster-cli"

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/cloud-lab-todo:latest"

echo "Using image:"
echo "$IMAGE_URI"

############################################
# Create ECS Cluster
############################################

aws ecs create-cluster \
  --cluster-name "$CLUSTER_NAME" \
  --region "$REGION"

############################################
# Create CloudWatch Log Group
############################################

aws logs create-log-group \
  --log-group-name /ecs/todo-task-cli \
  --region "$REGION" || true

############################################
# Create ECS Task Execution Role
############################################

cat > ecs-task-assume-role.json <<EOF
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":{
        "Service":"ecs-tasks.amazonaws.com"
      },
      "Action":"sts:AssumeRole"
    }
  ]
}
EOF

ROLE_ARN=$(aws iam create-role \
  --role-name ecs-task-execution-role-cli \
  --assume-role-policy-document file://ecs-task-assume-role.json \
  --query Role.Arn \
  --output text)

aws iam attach-role-policy \
  --role-name ecs-task-execution-role-cli \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

echo "Execution Role:"
echo "$ROLE_ARN"

############################################
# Create Task Definition
############################################

cat > task-definition.json <<EOF
{
  "family":"todo-task-cli",
  "networkMode":"awsvpc",
  "requiresCompatibilities":["FARGATE"],
  "cpu":"256",
  "memory":"512",
  "executionRoleArn":"$ROLE_ARN",
  "containerDefinitions":[
    {
      "name":"todo-container",
      "image":"$IMAGE_URI",
      "essential":true,
      "portMappings":[
        {
          "containerPort":3000,
          "hostPort":3000,
          "protocol":"tcp"
        }
      ],
      "logConfiguration":{
        "logDriver":"awslogs",
        "options":{
          "awslogs-group":"/ecs/todo-task-cli",
          "awslogs-region":"ap-south-1",
          "awslogs-stream-prefix":"ecs"
        }
      }
    }
  ]
}
EOF

TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://task-definition.json \
  --region "$REGION" \
  --query taskDefinition.taskDefinitionArn \
  --output text)

echo "Task Definition:"
echo "$TASK_DEF_ARN"

############################################
# Get Default VPC
############################################

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query 'Subnets[*].SubnetId' \
  --output text)

############################################
# Create Security Group for ALB
############################################

SG_ID=$(aws ec2 create-security-group \
  --group-name todo-alb-sg \
  --description "ALB Security Group" \
  --vpc-id "$VPC_ID" \
  --query GroupId \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

############################################
# Create ALB
############################################

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name todo-alb-cli \
  --subnets $SUBNET_IDS \
  --security-groups "$SG_ID" \
  --scheme internet-facing \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB:"
echo "$ALB_DNS"

############################################
# Create Target Group
############################################

TG_ARN=$(aws elbv2 create-target-group \
  --name todo-targets \
  --protocol HTTP \
  --port 3000 \
  --vpc-id "$VPC_ID" \
  --target-type ip \
  --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

############################################
# Create Listener
############################################

aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN"

############################################
# ECS Security Group
############################################

ECS_SG=$(aws ec2 create-security-group \
  --group-name todo-ecs-sg \
  --description "ECS Security Group" \
  --vpc-id "$VPC_ID" \
  --query GroupId \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$ECS_SG" \
  --protocol tcp \
  --port 3000 \
  --source-group "$SG_ID"

############################################
# Create ECS Service
############################################

aws ecs create-service \
  --cluster "$CLUSTER_NAME" \
  --service-name todo-service-cli \
  --task-definition "$TASK_DEF_ARN" \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$ECS_SG],assignPublicIp=ENABLED}" \
  --load-balancers targetGroupArn="$TG_ARN",containerName=todo-container,containerPort=3000 \
  --region "$REGION"

############################################
# Verify Deployment
############################################

echo ""
echo "Listing Tasks..."

aws ecs list-tasks \
  --cluster "$CLUSTER_NAME"

echo ""
echo "Load Balancer URL:"
echo "http://$ALB_DNS"

echo ""
echo "To test:"
echo "curl http://$ALB_DNS"

echo ""
echo "View Logs:"
echo "aws logs tail /ecs/todo-task-cli --follow"
