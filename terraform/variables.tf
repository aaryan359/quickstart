variable "aws_region" {
  description = "AWS region for the quickstart deployment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for AWS resource names."
  type        = string
  default     = "iii-quickstart"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "Availability zone used by both subnets."
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "EC2 instance type for each VM."
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_name" {
  description = "Existing AWS EC2 key pair name for SSH access."
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation for SSH access, for example 1.2.3.4/32."
  type        = string
}

variable "repo_url" {
  description = "Git URL for the quickstart repository cloned by EC2 startup scripts."
  type        = string
}

variable "repo_ref" {
  description = "Git branch or tag to deploy."
  type        = string
  default     = "main"
}
