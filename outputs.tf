##################################################################
# Lameirinho — Solution outputs
##################################################################

output "prefix"                         { value = module.lameirinho.prefix }

########################################################################
# VPC / Landing Zone
########################################################################
output "vpc_names"                      { value = module.lameirinho.vpc_names }
output "vpc_data"                       { value = module.lameirinho.vpc_data }
output "vsi_names"                      { value = module.lameirinho.vsi_names }
output "vsi_list"                       { value = module.lameirinho.vsi_list }
output "resource_group_data"            { value = module.lameirinho.resource_group_data }
output "network_services_vsi_ip"        { value = module.lameirinho.network_services_vsi_ip }
output "proxy_host_or_ip_port"          { value = module.lameirinho.proxy_host_or_ip_port }
output "dns_host_or_ip"                 { value = module.lameirinho.dns_host_or_ip }
output "ntp_host_or_ip"                 { value = module.lameirinho.ntp_host_or_ip }
output "network_services_config"        { value = module.lameirinho.network_services_config }

########################################################################
# Site-to-Site VPN
########################################################################
output "s2s_vpn_mode"                   { value = module.lameirinho.s2s_vpn_mode }
output "s2s_vpn_gateway_id"             { value = module.lameirinho.s2s_vpn_gateway_id }
output "s2s_vpn_gateway_public_ip"      { value = module.lameirinho.s2s_vpn_gateway_public_ip
                                          description = "IBM Cloud VPN Gateway public IPs — configure these on the on-premises firewall/router." }
output "s2s_vpn_peer_name"              { value = module.lameirinho.s2s_vpn_peer_name }
output "s2s_vpn_peer_address"           { value = module.lameirinho.s2s_vpn_peer_address }
output "s2s_vpn_on_premises_cidrs"      { value = module.lameirinho.s2s_vpn_on_premises_cidrs }
output "s2s_vpn_local_cidrs"            { value = module.lameirinho.s2s_vpn_local_cidrs }
output "s2s_vpn_connection_status"      { value = module.lameirinho.s2s_vpn_connection_status }

########################################################################
# Transit Gateway
########################################################################
output "transit_gateway_id"             { value = module.lameirinho.transit_gateway_id }
output "transit_gateway_name"           { value = module.lameirinho.transit_gateway_name }
output "transit_gateway_connections"    { value = module.lameirinho.transit_gateway_connections }
output "tgw_onprem_prefix_filters"      { value = module.lameirinho.tgw_onprem_prefix_filters }
output "tgw_vpc_connection_id"          { value = module.lameirinho.tgw_vpc_connection_id }

########################################################################
# PowerVS Workspace
########################################################################
output "powervs_zone"                   { value = module.lameirinho.powervs_zone }
output "powervs_resource_group_name"    { value = module.lameirinho.powervs_resource_group_name }
output "powervs_workspace_name"         { value = module.lameirinho.powervs_workspace_name }
output "powervs_workspace_id"           { value = module.lameirinho.powervs_workspace_id }
output "powervs_workspace_guid"         { value = module.lameirinho.powervs_workspace_guid }
output "powervs_ssh_public_key"         { value = module.lameirinho.powervs_ssh_public_key }
output "powervs_subnet"                 { value = module.lameirinho.powervs_subnet }

########################################################################
# IBM i Instance
########################################################################
output "ibmi_instance_id"               { value = module.lameirinho.ibmi_instance_id }
output "ibmi_instance_name"             { value = module.lameirinho.ibmi_instance_name }
output "ibmi_network_addresses"         { value = module.lameirinho.ibmi_network_addresses }
output "ibmi_boot_volume_id"            { value = module.lameirinho.ibmi_boot_volume_id }

########################################################################
# Schematics
########################################################################
output "schematics_workspace_id"        { value = var.IC_SCHEMATICS_WORKSPACE_ID }
