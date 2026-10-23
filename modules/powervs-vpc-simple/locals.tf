##################################################################
# Lameirinho — Module locals
##################################################################

locals {
  #----------------------------------------------------------------
  # Zone → IBM Cloud region maps
  #----------------------------------------------------------------
  ibm_powervs_zone_cloud_region_map = {
    "syd04"    = "au-syd"
    "syd05"    = "au-syd"
    "sao01"    = "br-sao"
    "sao04"    = "br-sao"
    "sao05"    = "br-sao"
    "tor01"    = "ca-tor"
    "mon01"    = "ca-tor"
    "eu-de-1"  = "eu-de"
    "eu-de-2"  = "eu-de"
    "mad02"    = "eu-es"
    "mad04"    = "eu-es"
    "lon04"    = "eu-gb"
    "lon06"    = "eu-gb"
    "osa21"    = "jp-osa"
    "tok04"    = "jp-tok"
    "us-south" = "us-south"
    "dal10"    = "us-south"
    "dal12"    = "us-south"
    "dal14"    = "us-south"
    "us-east"  = "us-east"
    "wdc06"    = "us-east"
    "wdc07"    = "us-east"
    "che02"    = "in-che"
    "che03"    = "in-che"
    "in-mum-1" = "in-mum"
    "in-mum-2" = "in-mum"
  }

  ibm_powervs_availability_zone_map = {
    "syd04"    = "zone-2"
    "syd05"    = "zone-3"
    "sao01"    = "zone-1"
    "sao04"    = "zone-2"
    "sao05"    = "zone-3"
    "tor01"    = "zone-1"
    "mon01"    = "zone-1"
    "eu-de-1"  = "zone-2"
    "eu-de-2"  = "zone-3"
    "mad02"    = "zone-1"
    "mad04"    = "zone-2"
    "lon04"    = "zone-1"
    "lon06"    = "zone-3"
    "osa21"    = "zone-1"
    "tok04"    = "zone-2"
    "us-south" = "zone-3"
    "dal10"    = "zone-1"
    "dal12"    = "zone-2"
    "dal14"    = "zone-3"
    "us-east"  = "zone-1"
    "wdc06"    = "zone-2"
    "wdc07"    = "zone-3"
    "che02"    = "zone-2"
    "che03"    = "zone-3"
    "in-mum-1" = "zone-2"
    "in-mum-2" = "zone-1"
  }

  availability_zone        = lookup(local.ibm_powervs_availability_zone_map, var.powervs_zone, null)
  availability_zone_number = substr(local.availability_zone, -1, 1)
  vpc_zone                 = "${lookup(local.ibm_powervs_zone_cloud_region_map, var.powervs_zone, null)}-${local.availability_zone_number}"

  #----------------------------------------------------------------
  # Resource group helpers
  #----------------------------------------------------------------
  second_rg_name = "slz-edge-rg"
  tgw_rg_name    = "slz-service-rg"

  #----------------------------------------------------------------
  # Normalise external_access_ip (add /32 if no prefix supplied)
  #----------------------------------------------------------------
  external_access_ip = var.external_access_ip != null && var.external_access_ip != "" ? (
    length(regexall("/", var.external_access_ip)) > 0 ? var.external_access_ip : "${var.external_access_ip}/32"
  ) : ""

  #----------------------------------------------------------------
  # cloud-init user_data — write SSH public key and enable root login
  #----------------------------------------------------------------
  generated_user_data = <<-EOT
#cloud-config
# vim: syntax=yaml
write_files:
- content: |
    ${var.ssh_public_key}
  path: /root/.ssh/authorized_keys
  permissions: '0600'
  owner: root:root
runcmd:
- sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
- systemctl restart sshd
EOT

  #----------------------------------------------------------------
  # Build the SLZ override JSON from the simplified preset
  #----------------------------------------------------------------
  override_json_string = templatefile("${path.module}/presets/slz-preset.json.tftpl",
    {
      external_access_ip           = local.external_access_ip
      rhel_image                   = var.vpc_intel_image
      network_services_vsi_profile = var.network_services_vsi_profile
      user_data                    = replace(local.generated_user_data, "\n", "\\n")
      transit_gateway_global       = var.transit_gateway_global
      second_rg_name               = local.second_rg_name
      tgw_rg_name                  = local.tgw_rg_name
      availability_zone            = local.availability_zone
      vpc_subnet_cidrs             = var.vpc_subnet_cidrs
      powervs_net_cidr             = var.powervs_network.cidr
    }
  )

  #----------------------------------------------------------------
  # Lookup helpers for VSI IPs (used by Ansible)
  #----------------------------------------------------------------
  key_vsi_list_exists         = contains(keys(module.landing_zone), "vsi_list") ? true : false
  network_services_vsi_exists = local.key_vsi_list_exists ? length([for n in module.landing_zone.vsi_names : n if can(regex("${var.prefix}-network-services", n))]) > 0 : false
  network_services_vsi_ip     = local.network_services_vsi_exists ? [for v in module.landing_zone.vsi_list : v.ipv4_address if can(regex("${var.prefix}-network-services", v.name))][0] : ""

  # No bastion/jump-box in this architecture — Ansible reaches the
  # network-services VSI directly via the site-to-site VPN tunnel
  # or via a temporary Floating IP (if external_access_ip is set).
  access_host_or_ip = local.network_services_vsi_ip

  #----------------------------------------------------------------
  # Primary subnet ID (used by VPN gateway)
  #----------------------------------------------------------------
  primary_subnet_id = [for s in module.landing_zone.subnet_data : s.id if s.name == "${var.prefix}-pvs-vpc-primary-${local.availability_zone}"][0]

  #----------------------------------------------------------------
  # VPN mode flags
  # create_vpn_gw = true  → new gateway/policies/connection are provisioned
  # create_vpn_gw = false → existing gateway is reused (or VPN is disabled)
  #----------------------------------------------------------------
  create_vpn_gw = var.site_to_site_vpn.enable && var.site_to_site_vpn.existing_vpn_gateway_id == null

  # Resolve the effective VPN gateway ID for outputs regardless of mode
  effective_vpn_gateway_id = (
    var.site_to_site_vpn.enable
    ? (
      local.create_vpn_gw
      ? try(ibm_is_vpn_gateway.s2s_vpn[0].id, "")
      : var.site_to_site_vpn.existing_vpn_gateway_id
    )
    : ""
  )

  #----------------------------------------------------------------
  # VPN local CIDRs — auto-computed: all VPC subnets + PowerVS subnet
  # + any caller-supplied additional_local_cidrs
  #----------------------------------------------------------------
  vpc_all_cidrs = compact([
    var.vpc_subnet_cidrs.primary,
    var.vpc_subnet_cidrs.optional1,
    var.vpc_subnet_cidrs.optional2,
  ])

  vpn_local_cidrs = concat(
    local.vpc_all_cidrs,
    [var.powervs_network.cidr],
    var.site_to_site_vpn.additional_local_cidrs
  )

  #----------------------------------------------------------------
  # Transit Gateway — static routes for on-premises CIDRs
  #
  # For each on-premises CIDR we need:
  #   - A VPC address prefix (so the TGW learns the CIDR from the VPC)
  #   - A TGW static route pointing to the VPC connection
  #
  # We build a map keyed by a safe slug of the CIDR (e.g. "10-192-0-0-16")
  # for use in for_each.
  #----------------------------------------------------------------
  onprem_cidr_map = var.site_to_site_vpn.enable ? {
    for cidr in var.site_to_site_vpn.on_premises_cidrs :
    replace(replace(cidr, ".", "-"), "/", "-") => cidr
  } : {}

  #----------------------------------------------------------------
  # Transit Gateway VPC connection ID
  # Looked up via data source after the TGW is created by SLZ.
  # We pick the connection whose network_type == "vpc".
  #----------------------------------------------------------------
  tgw_vpc_connection_id = try(
    [for c in data.ibm_tg_connections.tgw_connections.connections :
      c.id if c.network_type == "vpc"
    ][0],
    null
  )
}
