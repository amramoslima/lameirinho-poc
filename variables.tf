##################################################################
# Lameirinho — Variables
##################################################################

#####################################################
# Required Parameters
#####################################################

variable "ibmcloud_api_key" {
  description = "The IBM Cloud platform API key needed to deploy IAM enabled resources."
  type        = string
  sensitive   = true
}

variable "prefix" {
  description = "A unique identifier for resources. Must begin with a lowercase letter and end with a lowercase letter or number. Must contain only lowercase letters, numbers, and - characters. Prefixes must be 16 or fewer characters."
  type        = string

  validation {
    condition     = length(var.prefix) <= 16 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.prefix))
    error_message = "Prefix must be 2-16 characters, start/end with a lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "powervs_zone" {
  description = "IBM Cloud PowerVS data center location (e.g. eu-de-1, us-south, dal10, lon04)."
  type        = string
}

variable "powervs_resource_group_name" {
  description = "Existing IBM Cloud resource group name for PowerVS resources."
  type        = string
}

variable "ssh_public_key" {
  description = "RSA public SSH key (2048 or 4096 bits) used for VSI and PowerVS instance access. Must not already exist in the deployment region."
  type        = string
}

variable "ssh_private_key" {
  description = "RSA private SSH key (matching ssh_public_key) used to configure network services via Ansible. Not stored or uploaded."
  type        = string
  sensitive   = true
}

#####################################################
# VPC — Networking
#####################################################

variable "vpc_subnet_cidrs" {
  description = <<-EOT
    CIDR blocks for the VPC subnets.
    - primary  : mandatory — hosts the network-services VSI, VPN gateway and VPE. All edge/network services reside here.
    - optional1: set to null to skip creation.
    - optional2: set to null to skip creation.
    CIDRs must not overlap with each other or with the PowerVS subnet.
  EOT
  type = object({
    primary   = string
    optional1 = optional(string, null)
    optional2 = optional(string, null)
  })
  default = {
    primary   = "10.30.10.0/24"
    optional1 = null
    optional2 = null
  }
}

variable "transit_gateway_global" {
  description = "Allow Transit Gateway connections to networks outside the associated region."
  type        = bool
  default     = false
}

#####################################################
# VPN Site-to-Site
#####################################################

variable "site_to_site_vpn" {
  description = <<-EOT
    Configuration for the IBM Cloud VPN Gateway (site-to-site, policy-based).

    ── Existing gateway (reuse mode) ──────────────────────────────────────
    - existing_vpn_gateway_id  : ID of an existing IBM Cloud VPN Gateway to reuse.
                                  When set, no new gateway, IKE policy, IPSec policy
                                  or connection is created. The on_premises_cidrs are
                                  still used to set VPC address prefixes and TGW prefix
                                  filters so that PowerVS → on-premises routing works.
    - existing_vpn_connection_id: ID of the existing VPN Gateway connection.
                                  Used only for informational outputs when reusing a gateway.

    ── New gateway (create mode — used when existing_vpn_gateway_id is null) ──
    - peer_name        : human-readable label for the on-premises gateway (used in resource names).
    - peer_address     : public IP address of the on-premises VPN device.
    - preshared_key    : pre-shared key for IKE negotiation (sensitive).

    ── Common to both modes ───────────────────────────────────────────────
    - on_premises_cidrs: list of on-premises CIDR blocks reachable through the tunnel.
                         These CIDRs are automatically:
                           • added as peer_cidrs on the VPN connection (create mode only)
                           • added as VPC address prefixes so the Transit Gateway
                             can advertise them to the PowerVS workspace
                           • added as prefix filters (permit) on the TGW VPC connection,
                             enabling PowerVS → on-premises routing

    ── Tunnel / crypto settings (create mode only) ────────────────────────
    - ike_version      : IKE version (1 or 2). Defaults to 2.
    - ike_auth_alg     : IKE authentication algorithm. Default: sha256.
    - ike_enc_alg      : IKE encryption algorithm. Default: aes256.
    - ike_dh_group     : Diffie-Hellman group for IKE. Default: 14.
    - ipsec_auth_alg   : IPSec authentication algorithm. Default: sha256.
    - ipsec_enc_alg    : IPSec encryption algorithm. Default: aes256.
    - ipsec_pfs        : IPSec PFS DH group. Default: group_14.

    ── Local side extras ──────────────────────────────────────────────────
    - additional_local_cidrs: extra local CIDRs beyond the auto-computed ones
                               (VPC subnets + PowerVS subnet).
  EOT
  type = object({
    enable        = bool
    # ── Existing gateway (reuse) ──
    existing_vpn_gateway_id    = optional(string, null)
    existing_vpn_connection_id = optional(string, null)
    # ── Peer / new gateway ──
    peer_name           = optional(string, "on-prem")
    peer_address        = optional(string, "")
    preshared_key       = optional(string, "")
    # ── Common ──
    on_premises_cidrs      = optional(list(string), [])
    additional_local_cidrs = optional(list(string), [])
    # ── Tunnel crypto (create mode) ──
    ike_version    = optional(number, 2)
    ike_auth_alg   = optional(string, "sha256")
    ike_enc_alg    = optional(string, "aes256")
    ike_dh_group   = optional(number, 14)
    ipsec_auth_alg = optional(string, "sha256")
    ipsec_enc_alg  = optional(string, "aes256")
    ipsec_pfs      = optional(string, "group_14")
  })
  default = {
    enable = false
  }
  sensitive = false

  validation {
    # In create mode (no existing gateway): peer_address and preshared_key are required
    condition = (
      var.site_to_site_vpn.enable &&
      var.site_to_site_vpn.existing_vpn_gateway_id == null
    ) ? (
      var.site_to_site_vpn.peer_address != "" &&
      var.site_to_site_vpn.preshared_key != ""
    ) : true
    error_message = "When site_to_site_vpn.enable is true and no existing gateway is provided, peer_address and preshared_key must be set."
  }
  validation {
    condition     = var.site_to_site_vpn.enable ? length(var.site_to_site_vpn.on_premises_cidrs) > 0 : true
    error_message = "When site_to_site_vpn.enable is true, on_premises_cidrs must contain at least one CIDR block."
  }
}

#####################################################
# PowerVS Workspace — Network
#####################################################

variable "powervs_network" {
  description = "Name and CIDR of the single PowerVS private subnet. Must not overlap with VPC subnets."
  type = object({
    name = string
    cidr = string
  })
  default = {
    name = "pvs-net"
    cidr = "10.51.0.0/24"
  }

  validation {
    condition     = can(regex("^([a-z]|[a-z][-_a-z0-9]*[a-z0-9])$", var.powervs_network.name))
    error_message = "powervs_network.name can only contain 'a-z', '0-9', '-', '_' and must start/end with a letter or number."
  }
}

#####################################################
# PowerVS Instance — IBM i 7.5
#####################################################

variable "ibmi_instance" {
  description = <<-EOT
    Configuration of the IBM i 7.5 Power Virtual Server instance.
    Defaults match the PoC specification:
      - proc_type  : shared (fractional core)
      - processors : 0.25  (quarter core on Power11)
      - memory     : 16 GB
      - storage_tier: tier3
      - boot_size  : 100 GB
      - sys_type   : s1022 (Power11)
      - image_id   : stock IBM i 7.5 EN image — override with your region's image ID if needed
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

  validation {
    condition     = contains(["shared", "dedicated", "capped"], var.ibmi_instance.proc_type)
    error_message = "proc_type must be one of: shared, dedicated, capped."
  }
  validation {
    condition     = contains(["tier0", "tier1", "tier3", "tier5k"], var.ibmi_instance.storage_tier)
    error_message = "storage_tier must be one of: tier0, tier1, tier3, tier5k."
  }
}

#####################################################
# Network Services VSI
#####################################################

variable "vpc_intel_image" {
  description = "Stock RHEL OS image name for the network-services VSI (SQUID proxy, NTP, DNS)."
  type        = string
  default     = "ibm-redhat-9-6-amd64-sap-applications-9"
}

variable "network_services_vsi_profile" {
  description = "Compute profile for the network-services VSI. See https://cloud.ibm.com/docs/vpc?topic=vpc-profiles"
  type        = string
  default     = "cxf-2x4"
}

variable "configure_dns_forwarder" {
  description = "Install and configure a DNS forwarder on the network-services VSI."
  type        = bool
  default     = true
}

variable "configure_ntp_forwarder" {
  description = "Install and configure an NTP forwarder on the network-services VSI."
  type        = bool
  default     = true
}

variable "dns_forwarder_config" {
  description = "Upstream DNS servers used by the forwarder."
  type = object({
    dns_servers = string
  })
  default = {
    dns_servers = "161.26.0.7; 161.26.0.8; 9.9.9.9;"
  }
}

#####################################################
# Monitoring (Lite / free tier — no new instance)
#####################################################

variable "existing_monitoring_instance_crn" {
  description = "CRN of an existing IBM Cloud Monitoring instance to connect to. Leave null to skip monitoring integration (a free Lite instance can be created manually in the IBM Cloud Console)."
  type        = string
  default     = null
}

#####################################################
# Optional — Tags
#####################################################

variable "tags" {
  description = "List of tags applied to all created resources."
  type        = list(string)
  default     = []
}

#####################################################
# Schematics (auto-populated — leave blank locally)
#####################################################

# tflint-ignore: all
variable "IC_SCHEMATICS_WORKSPACE_ID" {
  description = "Leave blank when running locally. Auto-populated by IBM Cloud Schematics."
  type        = string
  default     = ""
}
