#
# Variables Configuration
#

variable "aws_region" {
  default     = "ap-northeast-3"
  type        = string
  description = "aws region"
}

variable "tags" {
  type = map(any)
  default = {
    owner     = "gs.lee@hashicorp.com"
    se-region = "south korea apj"
    purpose   = "demo consul service mesh"
    ttl       = 72
    terraform = true
  }
}

variable "publickey_file" {
  default = ".ssh/sample_rsa.pub"
}

variable "my_ip" {
  default = "14.39.92.145/32"
}

variable "prefix" {
  default = "gs"
}