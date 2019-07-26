# AWS Deployment Prerequisites

# Increase ElasticIP Limits
Each instance of the valtix firewall consumes an elastic ip. An account
by default gets 5 elastic ips assigned by aws. Request to increase this
limit. This usually takes only a few minutes. For the demo/poc we will
consume atleast 2 elastic ips. If you have 2 free elastic ips then you
can continue without waiting for the limits to be increased.

# Quick Start

## Terraform
Run terraform script provided here to create new VPC and other
requirements to get started with valtix.

Script creates VPC, Subnets, Route Tables, Internet Gateway,
S3 Bucket, Security Groups, IAM User, IAM Role, IAM Policy

Edit **values** file to provide values for the variables:

*aws_region* - AWS region name (e.g. us-east-1)
*zones* - Number of zones you want to create resources and use
firewall
*access_key* - AWS access key and secret used to create the
resources.
*secret_key* - Secret key of the above user
*prefix* - All the resources are named/tagged with the prefix
provided here

```
terraform init
terraform plan -var-file values
terraform apply -var-file values
```

## Destroy all the resources
Once all the firewalls are deleted from the valtix controller
```
terraform destroy -var-file values
```

# Long Story and Details on what the terraform script does

# S3 Bucket
Valtix firewall uses S3 bucket to store techsupport information and also
packet capture files (pcap) if configured on the firewall. Create a
bucket **valtix-techsupport**.

# IAM Role for Valtix Firewall
Valtix firewalls need write acces to a S3 bucket to dump techsupport
information.
S3 bucket is also used to dump PCAP files if pcap capture is enabled
in the configuration.
An IAM role with write access to an S3 bucket is required. You
must create a role with full access to S3 or access to a specific
bucket.
Create a role on AWS console (valtix_fw_role) and assign the
following policy:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "s3:*",
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
```

Or to give write access only to **valtix-techsupport** bucket
that's created above:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "s3:*",
            "Effect": "Allow",
            "Resource": "arn:aws:s3:::valtix-techsupport/*"
        }
    ]
}
```

The policy can be assigned either inline or create a new policy and
then assign that policy to this role.
Once the role is created, copy the arn of this role, the arn will be
used by the IAM user in the next step.

# IAM User for Valtix Controller
Valtix controller accesses customers AWS account to create firewall
instances and network load balancers. Customers must provide
a user that has programmatic access with permissions for ec2 and
elb. The user must also be able to assign IAM roles to the instances
that are created by the controller.

Create IAM user 'valtix_user' with programmatic access and assign the
following policy for EC2 service:
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
            "Resource": "arn:aws:iam::12345678:role/valtix_fw_role"
        }
    ]
}
```

Edit the last section in *iam:PassRole* and change the *Resource* to
the arn of the IAM role (valtix_fw_role) that's created in the above
[section](#IAM-Role-for-Valtix-Firewall)

# VPC
Don't use the VPC wizard. Goto VPCs list on the aws console and create
a new VPC.

Create a new VPC (valtix_vpc) to host the firewall and all the customer
apps/instances. Use the CIDR 10.0.0.0/16 as the address space.

# Internet Gateway
Create an Internet Gateway and attach it to the VPC. This is used by
the firewall to send/receive traffic for the customer apps.

# Subnets
VPC creates a default subnet. We will not use that subnet here. Create
3 subnets:

subnet **valtix_backend** with CIDR 10.0.1.0/24
subnet **valtix_frontend** with CIDR 10.0.2.0/24
subnet **valtix_mgmt** with CIDR 10.0.3.0/24

valtix_mgmt and valtix_frontend are public subnets. valtix_backed is
a private subnet that hosts the customer apps.

Valtix firewall is created with 3 network interfaces and assigned to
the above subnets.

valtix_frontend receives all the user traffic of the customer apps,
processed by firewall and forwarded to the apps via the valtix_backend
subnet.

valtix_mgmt subnet is used by the firewall to communicate with the
valtix controller. The interface in this subnet gets assigned an
elastic ip.

# Route Tables
Its always recommended to not make any changes to the default route
table of the VPC as all the subnets fall back to use that route table.
The default route table has routes to allow traffic only within the VPC
and does not have a route to go out to the internet. Mgmt and Frontend
subnets need a route to go to the internet. So create 2 route tables:

Route table **valtix_frontend** and associate this with the subnet
**valtix_frontend**.
Add a route to this table for 0.0.0.0/0 with next hop as the internet
gateway created earlier.

Route table **valtix_mgmt** and associate this with the subnet
**valtix_mgmt**.
Add a route to this table for 0.0.0.0/0 with next hop as the internet
gateway created earlier.

# Security Groups
Every network interface on aws must be assigned a security group.
Create 3 security groups:

Group **valtix_frontend** assigned to the interface in the subnet
**valtix_frontend**. This receives all the user traffic of the customer
apps. So ports must be opened to receive the traffic. Its recommened
to open atleast port 80 and port 444 in inbound rules.
Outbound rules can be removed as no traffic is initiated by the
firewall on this interface. Security group by defaul has a rule to
allow all outbound traffic. You can either leave it there or delete it.

Group **valtix_backed** assigned to interface in the subnet
**valtix_backend**. Firewall initiates traffic via this interface to
reach the customer apps. So the security group must allow all outbound
traffic. Traffic is typically not initiated to hit this
interface/security-group. So there is no need to have any inbound
rules. For the outbound rules you can be more specific and allow only
the ports the apps are expecting. But usually this is not required and
can leave it to default to open all the traffic.

Group **valtix_mgmt** assigned to interface in the subnet **valtix_mgmt**.
Firewall uses this out-of-band interface to communicate with the
controller. So rules to allow this traffic must be opened. By default
there is a rule to allow all the traffic. You can leave it like that
or delete that rule and open specific ports. Firewall needs access
to the TCP Ports 53, 80, 443, 8091-8092 and UDP Ports 53.

TCP Ports 8091-8092 are used by controller and 53 for DNS.

Group **valtix_customer_apps** assigned to instances that run customer apps.
This must open all the ports that instances require to communicate with
each other. This sg is not used by valtix firewall and this is
specific to customer needs only.
