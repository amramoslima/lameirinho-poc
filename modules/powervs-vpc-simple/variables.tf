##################################################################
# Lameirinho — Module variables (powervs-vpc-simple)
##################################################################

variable "powervs_zone" {
  type = string
}

variable "prefix" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "powervs_resource_group_name" {
  type = string
}

variable "external_access_ip" {
  type    = string
  default = null
}

variable "transit_gateway_global" {
  type    = bool
  default = false
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "vpc_subnet_cidrs" {
  type = object({
    primary   = string
    optional1 = optional(string, null)
    optional2 = optional(string, null)
  })
}

variable "vpc_intel_image" {
  type = string
}

variable "network_services_vsi_profile" {
  type    = string
  default = "cxf-2x4"
}

variable "configure_dns_forwarder" {
  type    = bool
  default = true
}

variable "configure_ntp_forwarder" {
  type    = bool
  default = true
}

variable "dns_forwarder_config" {
  type = object({
    dns_servers = string
  })
  default = {
    dns_servers = "161.26.0.7; 161.26.0.8; 9.9.9.9;"
  }
}

variable "site_to_site_vpn" {
  type = object({
    enable                     = bool
    existing_vpn_gateway_id    = optional(string, null)
    existing_vpn_connection_id = optional(string, null)
    peer_name                  = optional(string, "on-prem")
    peer_address               = optional(string, "")
    preshared_key              = optional(string, "")
    on_premises_cidrs          = optional(list(string), [])
    additional_local_cidrs     = optional(list(string), [])
    ike_version                = optional(number, 2)
    ike_auth_alg               = optional(string, "sha256")
    ike_enc_alg                = optional(string, "aes256")
    ike_dh_group               = optional(number, 14)
    ipsec_auth_alg             = optional(string, "sha256")
    ipsec_enc_alg              = optional(string, "aes256")
    ipsec_pfs                  = optional(string, "group_14")
  })
  default   = { enable = false }
  sensitive = false
}

variable "powervs_network" {
  type = object({
    name = string
    cidr = string
  })
  default = {
    name = "pvs-net"
    cidr = "172.16.2.0/24"
  }
}

variable "ibmi_instance" {
  description = <<-EOT
    IBM i 7.5 Power Virtual Server instance configuration.
    sys_type: s1022 (Power10/11). Note: "s1122" is not a valid IBM PowerVS model.
    memory  : 8 GB minimum for PoC; 16 GB recommended for production interactive workloads.
  EOT
  type = object({
    name         = optional(string, "ibmi-instance")
    proc_type    = optional(string, "shared")
    processors   = optional(string, "0.25")
    memory       = optional(number, 16)
    sys_type     = optional(string, "s1022")
    storage_tier = optional(string, "tier3")
    boot_size    = optional(number, 100)
    image_id     = optional(string, "")
  })
  default = {}
}

variable "configure_network_services" {
  description = "Run Ansible to configure Squid/DNS/NTP on the network-services VSI. Set false for initial deploy when VPN/Floating IP is not yet active."
  type        = bool
  default     = true
}

variable "existing_monitoring_instance_crn" {
  type    = string
  default = null
}
