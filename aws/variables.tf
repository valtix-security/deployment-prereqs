variable "access_key" {
  description = "customer access key"
}

variable "secret_key" {
  description = "customer secret key"
}

variable "aws_region" {
  description = "AWS region to launch servers."
}

variable "zones" {
  description = "Number of zones the resources must be created, zone names are dynamically obtained from aws region"
}

variable "prefix" {
   description = "All the resource will be created with this prefix e.g: valtix_poc"
}
