# AWS Deployment Prerequisites
This folder contains a set of terraform scripts which provisions your demo/POC AWS account with a set of pre-requisite steps needed to deploy a valtix firewall appliance.

## Increase ElasticIP Limits
A new AWS account by default has a limit of 5 elastic IPs which can be created in it. Before you deploy a valtix firewall in your AWS account, you need to request an increase in the elastic IP limit set by AWS. Each instance of the valtix firewall consumes an elastic ip. An AWS account by default gets 5 elastic ips assigned by aws. You may request to increase this limit. The process usually takes only a few minutes. 

The demo/POC scenario will consume atleast 2 elastic ips. If your account has at least 2 free elastic IPs, then you may proceed with the next steps before waiting for the limits to be increased.

# Quick Start Steps

## Terraform
Run the terraform scripts provided in this directory to create a new VPC and other requirements to get started with the Valtix demo/POC.

The script creates the following resources: VPC, Subnets, Route Tables, Internet Gateway, S3 Bucket, Security Groups, IAM User, IAM Role and IAM Policy.

Edit the **values** file to provide values for the following variables:

- *aws_region* - AWS region name (e.g. us-east-1)
- *zones* - Number of availability zones you want to create resources in and use the valtix firewall
- *access_key* - AWS access key of the IAM user which will be used to create resources.
- *secret_key* - AWS secret for the above IAM user
- *prefix* - All the resources are named/tagged with the prefix provided here. Provide an easy to remember value.

Now execute the following steps:

```
terraform init
terraform plan -var-file values
terraform apply -var-file values
```

## Cleaning up resources
Once all the firewalls are deleted from the valtix controller, and you are done with the demo/POC, you may clean up the resources created in your AWS account using:
```
terraform destroy -var-file values
```

# Details on what the terraform script does

For the example resources here, the prefix **valtixpoc** is used. 

## S3 Bucket
The Valtix firewall uses a S3 bucket to store techsupport information and also the packet capture files (pcap) if configured on the firewall. The script creates a bucket named **valtixpoc-techsupport**.

## IAM Role for Valtix Firewall
Valtix firewalls need write access to the above S3 bucket to upload techsupport information. The S3 bucket is also used to upload PCAP files if pcap capture is enabled in the firewall configuration. To write to the S3 bucket, an IAM role with write access to the above S3 bucket is required. This role is attached to the valtix-firewall when the firewall is created. The script creates an IAM role (called **valtixpoc_fw_role**) and assigns the following IAM policy to it. This allows write access to the above S3 buckets in your account:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "s3:*",
            "Effect": "Allow",
            "Resource": "arn:aws:s3:::valtixpoc-techsupport/*"
        }
    ]
}
```

## IAM User for the Valtix Controller
The Valtix controller accesses your demo/POC AWS account to create firewall instances and network load balancers. We need an IAM user that has API access to the EC2 and ELB services. This user must also be able to assign IAM roles to the instances that are created by the controller.

The script creates an IAM user **valtixpoc_user** with the required API access and assigns the following policy to this user:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "ec2:*",
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "elasticloadbalancing:*",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "<arn of the above IAM role>"
        }
    ]
}
```

ARN of the IAM role looks like `arn:aws:iam::12345678:role/valtixpoc_fw_role`

## VPC
The script creates a new VPC (called **valtixpoc_vpc**) to host the firewall and all your demo apps/instances. It uses the CIDR 10.0.0.0/16 as the address space.

## Internet Gateway
It creates an Internet Gateway and attach it to the VPC. This is used by the firewall to send/receive traffic for the customer/demo apps.

## Subnets
An AWS VPC has a default subnet. The script does not use that. Instead it creates 3 subnets:

- subnet **valtixpoc_backend** with CIDR 10.0.1.0/24
- subnet **valtixpoc_frontend** with CIDR 10.0.2.0/24
- subnet **valtixpoc_mgmt** with CIDR 10.0.3.0/24

**valtixpoc_mgmt** and **valtixpoc_frontend** are public subnets, whereas **valtixpoc_backend** is a private subnet that hosts the customer/demo apps. The Valtix firewall is created with 3 network interfaces and assigned to the above subnets. The interface attached to **valtixpoc_frontend** subnet receives all the user traffic destined to the customer/demo apps, which is then processed by firewall and forwarded to the apps via the interface attached to **valtixpoc_backend** subnet.

The interaface attached to the **valtixpoc_mgmt** subnet is used by the firewall to communicate with the valtix controller. The interface in this subnet gets assigned an elastic ip.

## Route Tables
Its recommended to not make any changes to the default route table of the VPC as all the subnets fall back to use that route table. The default route table has routes to allow traffic only within the VPC and does not have a route to go out to the internet. The **valtixpoc_mgmt** and **valtixpoc_frontend** subnets need outbound routes to the internet. The script creates 2 route tables:

- Route table **valtixpoc_frontend** associated with the subnet **valtixpoc_frontend**. A route is added to this table for 0.0.0.0/0 with next hop as the internet gateway created earlier.
- Route table **valtixpoc_mgmt** associated with the subnet **valtixpoc_mgmt**. A route is added to this table for 0.0.0.0/0 with next hop as the internet gateway created earlier.

# Security Groups

The script creates 3 security groups:

- The security group **valtixpoc_frontend** is assigned to the interface in the subnet **valtixpoc_frontend** that receives all the user traffic destined to the customer/demo apps. It opens appropriate ports to receive application traffic. Port 80 and port 444 are opened in the inbound rules section. No new outbound rules are added as no traffic is initiated by the firewall on this interface.

- The security group **valtixpoc_backend** is assigned to the interface in the subnet **valtixpoc_backend**. The Valtix firewall initiates traffic via this interface to reach the customer/demo apps. So this security group needs to allow all outbound traffic. Traffic is typically not initiated to this interface/security-group. So no inbound rules are added. For the outbound rules you may modify this script to be more specific and allow only the ports the apps are expecting traffic. But usually this is not required and you can leave it to default which is to allow all traffic to the backend.

- The security group **valtixpoc_mgmt** is assigned to the interface in the subnet **valtixpoc_mgmt**. The firewall uses this out-of-band interface to communicate with the controller. So the rules to allow controller communication traffic must be opened. By default there is a rule to allow all the traffic. You can leave it like that or delete that rule and open specific ports. The Valtix firewall needs access to the TCP Ports 53, 80, 443, 8091-8092 and UDP Ports 53. TCP Ports 8091-8092 are used by controller and 53 for DNS.

- The security group **valtixpoc_customer_apps** is assigned to instances that run the demo/customer apps. This must open all the ports that these instances require to communicate with each other. This security group is not used by valtix firewall and this is specific to customer/demo needs only.