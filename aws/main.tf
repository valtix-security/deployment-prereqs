# Copyright 2019 Valtix Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# The script creates the resources for a customer's green field
# deployments of valtix firewall
# Create IAM user with ec2, elb permissions that's used by valtix
# controller to create firewall in the customer's account
# Create an IAM role that has access to S3 buckets to write
# techsupport/pcap files. The role is assigned to the firewall when the
# controller creates it.
# Create a VPC, internet gateway,
# 2 public subnets have default route via the internet gateway.
# 2 public subnets, 1 private subnet in each zone
# 4 security groups: 3 are used by valtix firewall and 1 is assigned to
# the customer apps/instances.
# Frontend security group opens ports to allow traffic from internet
# towards the firewall
# Mgmt security group allows traffic to go out from firewall to the
# controller
# Backend security group allows traffic from the firewall to customer
# apps/instances
# Customer-apps security group is assigned to the customer ec2 instances
# and must allow ports so the backend-firewall can forward traffic to
# these instances.

provider "aws" {
  access_key = var.access_key
  secret_key = var.secret_key
  region = var.aws_region
}

# Declare the data source
data "aws_availability_zones" "available" {}


resource "aws_s3_bucket" "techsupport" {
  bucket = format("%s-techsupport", replace(var.prefix, "_", "-"))
  acl = "private"
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${var.prefix}_vpc"
  }
}

# create internet gw and attach it to the vpc
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name = "${var.prefix}_igw"
  }
}

# Three Subnets backend/frontend/mgmt
# frontend would host the NLB, has default route to the igw
# used by valtix firewall to receive traffic from the internet.
# mgmt subnet has default route to the igw and allows outbound
# traffic to communicate with the controller.
# backend subnet hosts all the customer apps. valtix fw has an interface
# here to communicate with customer apps
# subnets are created in each of the zones
# 10.0.1.0 backend, 10.0.2.0 frontend, 10.0.3.0 mgmt
# and it continues in other zones in increments of 3

resource "aws_subnet" "backend" {
  vpc_id = aws_vpc.default.id
  count = var.zones
  cidr_block = "10.0.${count.index * 3 + 1}.0/24"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"

  tags = {
    Name = "${var.prefix}_z${count.index + 1}_backend"
  }
}

resource "aws_subnet" "frontend" {
  vpc_id = aws_vpc.default.id
  count = var.zones
  cidr_block = "10.0.${(count.index * 3) + 2}.0/24"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"

  tags = {
    Name = "${var.prefix}_z${count.index + 1}_frontend"
  }
}

resource "aws_subnet" "mgmt" {
  vpc_id = aws_vpc.default.id
  count = var.zones
  cidr_block = "10.0.${count.index *3 + 3}.0/24"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"

  tags = {
    Name = "${var.prefix}_z${count.index + 1}_mgmt"
  }
}

# dont use default route table for any route changes. create subnet
# specific route table for any route info

# mgmt route table associated with mgmt subnet and has a default route
# to point to the igw

resource "aws_route_table" "mgmt" {
  vpc_id = aws_vpc.default.id
  count = var.zones

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.prefix}_z${count.index + 1}_mgmt"
  }
}

# frontend route table associated with frontend subnet and has a default
# route to point to the igw

resource "aws_route_table" "frontend" {
  vpc_id = aws_vpc.default.id
  count = var.zones

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.prefix}_z${count.index + 1}_mgmt"
  }
}

# associate mgmt route table with mgmt subnet

resource "aws_route_table_association" "mgmt" {
  count = var.zones
  subnet_id = aws_subnet.mgmt[count.index].id
  route_table_id = aws_route_table.mgmt[count.index].id
}

# associate frontend route table with frontend subnet

resource "aws_route_table_association" "frontend" {
  count = var.zones
  subnet_id = aws_subnet.frontend[count.index].id
  route_table_id = aws_route_table.frontend[count.index].id
}

# security groups for frontend, backend, mgmt and customer_apps

# frontend is connected to the NLB and also to the incoming interface on
# the valtix fw. inbound rules setup to open 80 and 443.
# no outbound rules. so traffic cannot be initiated by firewall to go
# out on the frontend interface.

resource "aws_security_group" "frontend" {
  name = "${var.prefix}_frontend"
  vpc_id = aws_vpc.default.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.prefix}_frontend"
  }
}

# backend sg is applied on the interface on valtix firewall thats
# connected to the customer apps. firewall acting as a proxy initiates
# the traffic to reach customer apps. so by default opens all the ports.
# customer can restrict this to open only outbound specific ports to the
# apps. traffic is not initiated towards this interface. so there are no
# inbound rules.

resource "aws_security_group" "backend" {
  name = "${var.prefix}_backend"
  vpc_id = aws_vpc.default.id
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.prefix}_backend"
  }
}

# mgmt sg is applied to the mgmt interface on the valtix fw. traffic is
# not initiated towards this interface. so there are not inbound rules.
# fw communicates with the controller on this interface/sg. so outbound
# rules must be enabled to allow traffic to reach controller. this is
# setup to open ports 8091-8092. since the controller runs on ALB on
# aws, we can't open to a specific destination ip address.
# So the destination ip is setup to 0.0.0.0

resource "aws_security_group" "mgmt" {
  name = "${var.prefix}_mgmt"
  vpc_id = aws_vpc.default.id
  egress {
    from_port = 8091
    to_port = 8092
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 53
    to_port = 53
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 53
    to_port = 53
    protocol = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.prefix}_mgmt"
  }
}

# customer_apps sg is used by the instances running the customer apps.
# by default this is setup to open ports 80 and 443. customer must add
# ports when the new apps are launched on other ports. since the
# customer apps are expected to be in a private subnet, there is not
# reachability to the subnet from outside the vpc. Outbound rules are
# opened wide for intra-vpc communications. Customer can change/restrict
# as required.
resource "aws_security_group" "customer_apps" {
  name = "${var.prefix}_customer_apps"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.prefix}_customer_apps"
  }
}


# create a user and generate access_key and secret. this will be used by
# the valtix controller to manage customer account. this user needs to
# have access to ec2 and elb and must be able to pass the role created
# above (valtix_fw_role) to the firewall instances that it creates

resource "aws_iam_user" "valtix_user" {
  name = "${var.prefix}_user"
}

resource "aws_iam_access_key" "valtix_user" {
  user    = "${aws_iam_user.valtix_user.name}"
}

resource "aws_iam_user_policy" "valtix_user" {
  name = "valtix_user_policy"
  user = "${aws_iam_user.valtix_user.name}"

  policy = <<EOF
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
            "Effect":"Allow",
            "Action":"iam:PassRole",
            "Resource":"${aws_iam_role.valtix_fw_role.arn}"
       },
       {
            "Effect": "Allow",
            "Action": "iam:CreateServiceLinkedRole",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
                }
            }
       }
   ]
}
EOF
}

# create a role that will be used by valtix firewall with permissions to
# write techsupport/pcap files to s3 buckets
resource "aws_iam_role" "valtix_fw_role" {
  name = "${var.prefix}_fw_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# create a policy that gives write access to the firewall to dump pcaps
# and techsupport info. This is set for all full s3 access and can be
# changed to give write access only to a certain bucket
resource "aws_iam_policy" "valtix_s3_access" {
  name = "${var.prefix}_s3_access"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "s3:*",
      "Effect": "Allow",
      "Resource":"${aws_s3_bucket.techsupport.arn}/*"
    }
  ]
}
EOF
}

# attach the policy to the role
resource "aws_iam_role_policy_attachment" "role_policy" {
  role = "${aws_iam_role.valtix_fw_role.name}"
  policy_arn = "${aws_iam_policy.valtix_s3_access.arn}"
}

# for instances to use the role, an instance profile must be created and
# instance profile name used on the instance's iam role
# however on the firewall iam role text box you can provide the role
# name or the arn of either the role or the instance profile
resource "aws_iam_instance_profile" "valtix_fw_role" {
  name = "${var.prefix}_fw_role"
  role = "${aws_iam_role.valtix_fw_role.name}"
}
