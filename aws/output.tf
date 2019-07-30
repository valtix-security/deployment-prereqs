output "vpc" {
    value = "${aws_vpc.default.tags.Name} / ${aws_vpc.default.id}"
}

output "subnets-backend" {
    value = {for index, subnet in aws_subnet.backend[*]: "az${index + 1}" => subnet.tags.Name}
}

output "subnets-frontend" {
    value = {for index, subnet in aws_subnet.frontend[*]: "az${index + 1}" => subnet.tags.Name}
}

output "subnets-mgmt" {
    value = {for index, subnet in aws_subnet.mgmt[*]: "az${index + 1}" => subnet.tags.Name}
}

output "security-groups" {
    value = <<EOT
{
  "backend" = "${aws_security_group.backend.name}"
  "frontend" = "${aws_security_group.frontend.name}"
  "mgmt" = "${aws_security_group.mgmt.name}"
  "customer_apps" = "${aws_security_group.customer_apps.name}"
}
EOT
}

output "az-names" {
    value = {for index, az in data.aws_availability_zones.available.names: "az${index + 1}" => az if index < var.zones}
}

output "iam-user-credentials" {
    value = "${aws_iam_user.valtix_user.name} / ${aws_iam_access_key.valtix_user.id} / ${aws_iam_access_key.valtix_user.secret}"
}

output "iam-role-for-firewall" {
    value = "${aws_iam_role.valtix_fw_role.name}"
}

output "s3-bucket-techsupport" {
  value = aws_s3_bucket.techsupport.id
}
