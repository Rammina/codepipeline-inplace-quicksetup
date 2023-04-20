#!/bin/bash

sudo yum update -y
sudo yum install -y ruby wget

cd /home/ec2-user   
sudo wget https://aws-codedeploy-us-east-1.s3.amazonaws.com/latest/install   
chmod +x install     
sudo ./install auto

sudo service codedeploy-agent start  

status=$(sudo service codedeploy-agent status)  
if [[ $status == *"running"* ]]  
then   
  echo "CodeDeploy agent service is running!"   
else   
  echo "CodeDeploy agent service is not running :("   
fi 