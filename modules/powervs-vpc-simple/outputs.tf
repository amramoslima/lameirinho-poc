##################################################################
# Lameirinho — Module outputs (powervs-vpc-simple)
##################################################################

output "prefix" {
  description = "The prefix associated with all resources."
  value       = var.prefix
}

########################################################################
# VPC / Landing Zone
########################################################################

output "vpc_names" {
  description = "Names of the provisioned VPC(s)."
  value       = module.landing_zone.vpc_names
}

output "vpc_data" {
  description = "VPC data (id, subnets, security groups, etc.)."
  value       = module.landing_zone.vpc_data
}

output "vsi_names" {
  description = "Names of all VSIs provisioned in the VPC."
  value       = module.landing_zone.vsi_names
}

output "vsi_list" {
  description = "VSI list with name, id, zone, IPv4 address and VPC name."
  value       = module.landing_zone.vsi_list
}

output "resource_group_data" {
  description = "Resource groups created by the landing zone."
  value       = module.landing_zone.resource_group_data
}

output "network_services_vsi_ip" {
  description = "Private IPv4 address of the network-services VSI (Squid/DNS/NTP)."
  value       = local.network_services_vsi_ip
}

output "proxy_host_or_ip_port" {
  description = "Squid proxy endpoint reachable from PowerVS instances."
  value       = "${local.network_services_vsi_ip}:${local.network_services_config.squid.squid_port}"
}

output "dns_host_or_ip" {
  description = "DNS forwarder host IP (empty if configure_dns_forwarder = false)."
  value       = var.configure_dns_forwarder ? local.network_services_vsi_ip : ""
}

output "ntp_host_or_ip" {
  description = "NTP forwarder host IP (empty if configure_ntp_forwarder = false)."
  value       = var.configure_ntp_forwarder ? local.network_services_vsi_ip : ""
}

output "network_services_config" {
  description = "Complete network-services configuration map."
  value       = local.network_services_config
}

########################################################################
# Site-to-Site VPN
########################################################################

output "s2s_vpn_mode" {
  description = "VPN mode: 'create' (new gateway provisioned), 'reuse' (existing gateway), or 'disabled'."
  value = (
    !var.site_to_site_vpn.enable ? "disabled" :
    local.create_vpn_gw          ? "create"   : "reuse"
  )
}

output "s2s_vpn_gateway_id" {
  description = "Effective VPN Gateway ID — either the newly created one or the existing one passed in."
  value       = local.effective_vpn_gateway_id
}

output "s2s_vpn_gateway_public_ip" {
  description = "Public IP addresses of the VPN Gateway (only available in create mode; empty in reuse mode)."
  value       = local.create_vpn_gw ? [for m in ibm_is_vpn_gateway.s2s_vpn[0].members : m.public_ip_address] : []
}

output "s2s_vpn_peer_name" {
  description = "Label used for the on-premises peer gateway."
  value       = var.site_to_site_vpn.enable ? var.site_to_site_vpn.peer_name : ""
}

output "s2s_vpn_peer_address" {
  description = "Public IP of the on-premises VPN device."
  value       = var.site_to_site_vpn.enable ? var.site_to_site_vpn.peer_address : ""
}

output "s2s_vpn_on_premises_cidrs" {
  description = "On-premises CIDRs propagated to the Transit Gateway regardless of VPN mode."
  value       = var.site_to_site_vpn.enable ? var.site_to_site_vpn.on_premises_cidrs : []
}

output "s2s_vpn_local_cidrs" {
  description = "IBM Cloud-side CIDRs advertised through the VPN tunnel (auto-computed, create mode only)."
  value       = local.create_vpn_gw ? local.vpn_local_cidrs : []
}

output "s2s_vpn_connection_status" {
  description = "Status of the VPN Gateway connection. Only meaningful in create mode; empty in reuse/disabled mode."
  value       = local.create_vpn_gw ? ibm_is_vpn_gateway_connection.s2s_connection[0].status : ""
}

########################################################################
# Transit Gateway
########################################################################

output "transit_gateway_id" {
  description = "ID of the IBM Cloud Transit Gateway."
  value       = module.landing_zone.transit_gateway_data.id
}

output "transit_gateway_name" {
  description = "Name of the IBM Cloud Transit Gateway."
  value       = module.landing_zone.transit_gateway_name
}

output "transit_gateway_connections" {
  description = "List of Transit Gateway connections (VPC + PowerVS). Informational only — connection IDs are managed by the Landing Zone module."
  value       = try(module.landing_zone.transit_gateway_data.connections, null)
}

output "tgw_onprem_prefix_filters" {
  description = "TGW prefix filters (permit) created for on-premises CIDRs. Empty map if VPN is disabled."
  value = {
    for k, v in ibm_tg_connection_prefix_filter.onprem_static_route : k => {
      prefix    = v.prefix
      action    = v.action
      filter_id = v.filter_id
    }
  }
}

output "tgw_vpc_connection_id" {
  description = "Transit Gateway connection ID for the VPC (used for on-premises static routes)."
  value       = local.tgw_vpc_connection_id
}

########################################################################
# PowerVS Workspace
########################################################################

output "powervs_zone" {
  description = "Zone where the PowerVS workspace is deployed."
  value       = var.powervs_zone
}

output "powervs_resource_group_name" {
  description = "Resource group used for PowerVS resources."
  value       = var.powervs_resource_group_name
}

output "powervs_workspace_name" {
  description = "PowerVS workspace name."
  value       = module.powervs_workspace.pi_workspace_name
}

output "powervs_workspace_id" {
  description = "PowerVS workspace instance ID."
  value       = module.powervs_workspace.pi_workspace_id
}

output "powervs_workspace_guid" {
  description = "PowerVS workspace GUID."
  value       = module.powervs_workspace.pi_workspace_guid
}

output "powervs_ssh_public_key" {
  description = "SSH key imported into the PowerVS workspace."
  value       = module.powervs_workspace.pi_ssh_public_key
}

output "powervs_subnet" {
  description = "Name, ID and CIDR of the PowerVS private subnet."
  value       = module.powervs_workspace.pi_private_subnet_1
}

########################################################################
# IBM i Instance
########################################################################

output "ibmi_instance_id" {
  description = "Instance ID of the IBM i 7.5 Power Virtual Server."
  value       = ibm_pi_instance.ibmi.instance_id
}

output "ibmi_instance_name" {
  description = "Name of the IBM i 7.5 Power Virtual Server instance."
  value       = ibm_pi_instance.ibmi.pi_instance_name
}

output "ibmi_network_addresses" {
  description = "List of network interfaces and IP addresses attached to the IBM i instance."
  value       = ibm_pi_instance.ibmi.pi_network
}

output "ibmi_boot_volume_id" {
  description = "ID of the IBM i boot volume."
  value       = ibm_pi_volume.ibmi_boot.volume_id
}
