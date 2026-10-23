##################################################################
# Lameirinho — Module: powervs-vpc-simple
# Orchestrates:
#   1. IBM Cloud VPC Landing Zone (single VPC, 1-3 subnets)
#   2. Site-to-Site VPN Gateway (policy-based) — peer gateway input
#   3. Transit Gateway connections: VPC ↔ PowerVS + static on-prem routes
#   4. PowerVS Workspace (single subnet)
#   5. IBM i 7.5 Power Virtual Server instance
#   6. Network services configuration via Ansible (Squid, DNS, NTP)
##################################################################

##################################################################
# 1. VPC Landing Zone (SLZ)
##################################################################

module "landing_zone" {
  source    = "terraform-ibm-modules/landing-zone/ibm//patterns//vsi//module"
  version   = "8.23.5"
  providers = { ibm = ibm.ibm-is }

  ssh_public_key       = var.ssh_public_key
  region               = lookup(local.ibm_powervs_zone_cloud_region_map, var.powervs_zone, null)
  prefix               = var.prefix
  override_json_string = local.override_json_string
  kms_endpoint_type    = "public"
}

##################################################################
# 2. Site-to-Site VPN Gateway (policy-based)
#
# Two modes controlled by site_to_site_vpn.existing_vpn_gateway_id:
#
# CREATE mode (existing_vpn_gateway_id = null)
#   → IKE policy, IPSec policy, VPN Gateway and connection are created.
#
# REUSE mode (existing_vpn_gateway_id = "<id>")
#   → No gateway or connection resources are created/modified.
#     on_premises_cidrs are still applied to the TGW (block 3).
#
# local.create_vpn_gw = true only in CREATE mode.
##################################################################

resource "ibm_is_ike_policy" "s2s_ike" {
  provider = ibm.ibm-is
  count    = local.create_vpn_gw ? 1 : 0

  name                     = "${var.prefix}-${var.site_to_site_vpn.peer_name}-ike-policy"
  authentication_algorithm = var.site_to_site_vpn.ike_auth_alg
  encryption_algorithm     = var.site_to_site_vpn.ike_enc_alg
  dh_group                 = var.site_to_site_vpn.ike_dh_group
  ike_version              = var.site_to_site_vpn.ike_version
  resource_group           = module.landing_zone.resource_group_data["${var.prefix}-${local.second_rg_name}"]
}

resource "ibm_is_ipsec_policy" "s2s_ipsec" {
  provider = ibm.ibm-is
  count    = local.create_vpn_gw ? 1 : 0

  name                     = "${var.prefix}-${var.site_to_site_vpn.peer_name}-ipsec-policy"
  authentication_algorithm = var.site_to_site_vpn.ipsec_auth_alg
  encryption_algorithm     = var.site_to_site_vpn.ipsec_enc_alg
  pfs                      = var.site_to_site_vpn.ipsec_pfs
  resource_group           = module.landing_zone.resource_group_data["${var.prefix}-${local.second_rg_name}"]
}

resource "ibm_is_vpn_gateway" "s2s_vpn" {
  provider = ibm.ibm-is
  count    = local.create_vpn_gw ? 1 : 0

  name           = "${var.prefix}-${var.site_to_site_vpn.peer_name}-vpn-gw"
  subnet         = local.primary_subnet_id
  resource_group = module.landing_zone.resource_group_data["${var.prefix}-${local.second_rg_name}"]
  mode           = "policy"
  tags           = var.tags
}

resource "ibm_is_vpn_gateway_connection" "s2s_connection" {
  provider = ibm.ibm-is
  count    = local.create_vpn_gw ? 1 : 0

  name          = "${var.prefix}-${var.site_to_site_vpn.peer_name}-vpn-conn"
  vpn_gateway   = ibm_is_vpn_gateway.s2s_vpn[0].id
  peer_address  = var.site_to_site_vpn.peer_address
  preshared_key = var.site_to_site_vpn.preshared_key

  # local_cidrs: auto-computed (VPC subnets + PowerVS subnet + extras)
  local_cidrs = local.vpn_local_cidrs
  # peer_cidrs: on-premises networks declared by the operator
  peer_cidrs  = var.site_to_site_vpn.on_premises_cidrs

  ike_policy   = ibm_is_ike_policy.s2s_ike[0].id
  ipsec_policy = ibm_is_ipsec_policy.s2s_ipsec[0].id
}

# Data source: look up TGW connections after landing_zone creates them
data "ibm_tg_connections" "tgw_connections" {
  provider   = ibm.ibm-is
  gateway_id = module.landing_zone.transit_gateway_data.id
  depends_on = [module.landing_zone]
}

##################################################################
# 3. Transit Gateway — VPC address prefixes + static routes
#
# Context
# -------
# The SLZ module (landing_zone) already:
#   • Creates the Transit Gateway
#   • Attaches the VPC ("pvs-vpc") as a connection
#   • Attaches the PowerVS workspace as a connection (via pi_transit_gateway_connection)
#
# What we add here
# ----------------
# When a site-to-site VPN is enabled, the PowerVS instances need to
# reach on-premises hosts through the path:
#
#   PowerVS → Transit Gateway → VPC (via TGW connection) → VPN Gateway → on-premises
#
# For this to work we need:
#   a) VPC address prefixes for each on-premises CIDR
#      → makes the TGW aware that those CIDRs are reachable via the VPC connection
#   b) TGW static routes for each on-premises CIDR pointing to the VPC connection
#      → overrides any possible conflicting routes and guarantees forwarding
##################################################################

# (a) VPC address prefix per on-premises CIDR
#     Advertises each on-prem CIDR into the TGW route table via the VPC connection
resource "ibm_is_vpc_address_prefix" "onprem_prefix" {
  provider = ibm.ibm-is

  for_each = local.onprem_cidr_map

  name = "${var.prefix}-onprem-${each.key}"
  zone = local.vpc_zone
  vpc  = [for vpc in module.landing_zone.vpc_data : vpc.vpc_id if vpc.vpc_name == "${var.prefix}-pvs-vpc"][0]
  cidr = each.value
}

# (b) TGW static route per on-premises CIDR → VPC connection
#     Ensures the TGW always forwards on-prem traffic toward the VPC
resource "ibm_tg_route_report" "tgw_route_report" {
  provider = ibm.ibm-is
  count    = var.site_to_site_vpn.enable ? 1 : 0

  gateway = module.landing_zone.transit_gateway_data.id
}

resource "ibm_tg_connection_prefix_filter" "onprem_static_route" {
  provider = ibm.ibm-is

  # One prefix filter per on-premises CIDR.
  # Works in both CREATE and REUSE mode — the on_premises_cidrs drive this,
  # not whether the gateway was created by this module.
  for_each   = local.onprem_cidr_map
  depends_on = [ibm_is_vpc_address_prefix.onprem_prefix, ibm_is_vpn_gateway_connection.s2s_connection]

  gateway       = module.landing_zone.transit_gateway_data.id
  connection_id = local.tgw_vpc_connection_id
  action        = "permit"
  prefix        = each.value
  le            = tonumber(split("/", each.value)[1])
  ge            = tonumber(split("/", each.value)[1])
}

##################################################################
# 4. PowerVS Workspace (single subnet)
##################################################################

module "powervs_workspace" {
  source  = "terraform-ibm-modules/powervs-workspace/ibm"
  version = "5.1.0"

  providers = { ibm = ibm.ibm-pi }

  pi_zone                       = var.powervs_zone
  pi_resource_group_name        = var.powervs_resource_group_name
  pi_workspace_name             = "${var.prefix}-${var.powervs_zone}-power-workspace"
  pi_ssh_public_key             = { "name" = "${var.prefix}-${var.powervs_zone}-pvs-ssh-key", value = var.ssh_public_key }
  pi_private_subnet_1           = var.powervs_network
  pi_private_subnet_2           = null
  pi_transit_gateway_connection = {
    "enable"             = true
    "transit_gateway_id" = module.landing_zone.transit_gateway_data.id
  }
  pi_tags                       = var.tags
}

##################################################################
# 5. IBM i 7.5 Power Virtual Server instance
#
# Stock image name pattern: IBMi-7.5-*-EN (English, Power11 S1022)
# The image must be available in the target zone; if var.ibmi_instance.image_id
# is empty we perform a data lookup by OS type.
##################################################################

data "ibm_pi_catalog_images" "ibmi_catalog" {
  provider             = ibm.ibm-pi
  pi_cloud_instance_id = module.powervs_workspace.pi_workspace_guid
  sap                  = false
}

locals {
  # Resolve the IBM i 7.5 EN image: prefer explicit override, otherwise
  # pick the first catalog image whose name contains "IBMi-7.5" and "EN".
  ibmi_image_id = var.ibmi_instance.image_id != "" ? var.ibmi_instance.image_id : (
    length([
      for img in data.ibm_pi_catalog_images.ibmi_catalog.images :
      img.image_id if(
        can(regex("IBMi-7.5", img.name)) &&
        can(regex("-EN", img.name))
      )
    ]) > 0
    ? [
      for img in data.ibm_pi_catalog_images.ibmi_catalog.images :
      img.image_id if(
        can(regex("IBMi-7.5", img.name)) &&
        can(regex("-EN", img.name))
      )
    ][0]
    : ""
  )
}

resource "ibm_pi_image" "ibmi_image" {
  provider             = ibm.ibm-pi
  pi_cloud_instance_id = module.powervs_workspace.pi_workspace_guid
  pi_image_id          = local.ibmi_image_id
}

resource "ibm_pi_instance" "ibmi" {
  provider             = ibm.ibm-pi
  pi_cloud_instance_id = module.powervs_workspace.pi_workspace_guid

  pi_instance_name     = "${var.prefix}-${var.ibmi_instance.name}"
  pi_image_id          = ibm_pi_image.ibmi_image.image_id
  pi_key_pair_name     = module.powervs_workspace.pi_ssh_public_key.name
  pi_sys_type          = var.ibmi_instance.sys_type
  pi_proc_type         = var.ibmi_instance.proc_type
  pi_processors        = var.ibmi_instance.processors
  pi_memory            = var.ibmi_instance.memory

  # Primary PowerVS network
  pi_network {
    network_id = module.powervs_workspace.pi_private_subnet_1.id
  }

  # Boot volume (Tier 3, 100 GB)
  pi_storage_pool_affinity = false
  pi_storage_type          = var.ibmi_instance.storage_tier

  pi_volume_ids = [ibm_pi_volume.ibmi_boot.volume_id]

  depends_on = [ibm_pi_image.ibmi_image]
}

resource "ibm_pi_volume" "ibmi_boot" {
  provider             = ibm.ibm-pi
  pi_cloud_instance_id = module.powervs_workspace.pi_workspace_guid

  pi_volume_name       = "${var.prefix}-ibmi-boot"
  pi_volume_type       = var.ibmi_instance.storage_tier
  pi_volume_size       = var.ibmi_instance.boot_size
  pi_volume_shareable  = false
}

##################################################################
# 6. Network services — Ansible (Squid + DNS + NTP)
##################################################################

locals {
  network_services_config = {
    squid = {
      enable     = true
      squid_port = "3128"
    }
    dns = merge(var.dns_forwarder_config, {
      enable = var.configure_dns_forwarder
    })
    ntp = {
      enable = var.configure_ntp_forwarder
    }
    nfs = {
      enable          = false
      nfs_server_path = ""
      nfs_client_path = ""
      opts            = "sec=sys,nfsvers=4.1,nofail"
      fstype          = "nfs4"
    }
  }
}

module "configure_network_services" {
  source = "./submodules/ansible"

  bastion_host_ip        = local.access_host_or_ip
  ansible_host_or_ip     = local.network_services_vsi_ip
  ssh_private_key        = var.ssh_private_key
  configure_ansible_host = true

  src_script_template_name = "configure-network-services/ansible_exec.sh.tftpl"
  dst_script_file_name     = "network-services-instance.sh"

  src_playbook_template_name = "configure-network-services/playbook-configure-network-services.yml.tftpl"
  dst_playbook_file_name     = "network-services-instance-playbook.yml"
  playbook_template_vars = {
    "server_config" : jsonencode(
      {
        "squid" : local.network_services_config.squid,
        "dns" : local.network_services_config.dns,
        "ntp" : local.network_services_config.ntp
      }
    ),
    "client_config" : jsonencode({ "nfs" : local.network_services_config.nfs })
  }

  src_inventory_template_name = "inventory.tftpl"
  dst_inventory_file_name     = "network-services-instance-inventory"
  inventory_template_vars     = { "host_or_ip" : local.network_services_vsi_ip }
}
