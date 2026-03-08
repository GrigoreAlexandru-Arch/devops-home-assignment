variable "aws_region" {
  description = "The AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "ssh_allowed_ip" {
  description = "The IP for local SSH access"
  type        = string
}

variable "ssh_key_path" {
  description = "Path to the public SSH key used for EC2 access"
  type        = string
}

variable "instance_type" {
  description = "The EC2 instance type for Sentry"
  type        = string
  default     = "r6i.xlarge"
}

variable "volume_size" {
  description = "The size of the root EBS volume in GB"
  type        = number
  default     = 200
}
