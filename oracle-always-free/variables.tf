# oci account, values in terraform.tfvars (git ignored), see terraform.tfvars.example

variable "tenancy_ocid" {
  description = "OCID of the tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment the resources are created in, the tenancy OCID for the root compartment"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user the API key belongs to"
  type        = string
}

variable "fingerprint" {
  description = "fingerprint of the API key"
  type        = string
}

variable "private_key_path" {
  description = "path to the private API key (.pem)"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "eu-frankfurt-1"
}

variable "ssh_public_key" {
  description = "public SSH key for the instances, empty generates one"
  type        = string
  default     = ""
}

# instances

variable "instance_shape" {
  type    = string
  default = "VM.Standard.A1.Flex" # or VM.Standard.E2.1.Micro
}

variable "instance_ocpus" {
  type    = number
  default = 1
}

variable "instance_shape_config_memory_in_gbs" {
  type    = number
  default = 6
}

# availability domains, oci-retry.sh writes the free ones to ad.auto.tfvars
variable "instance0_ad" {
  type    = number
  default = 1
}

variable "instance1_ad" {
  type    = number
  default = 1
}
