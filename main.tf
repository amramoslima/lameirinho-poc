##################################################################
# Lameirinho — Solution entry point
# Calls the powervs-vpc-simple module with all required inputs
##################################################################

module "lameirinho" {
  source = "./modules/powervs-vpc-simple"

  providers = { ibm.ibm-is = ibm.ibm-is, ibm.ibm-pi = ibm.ibm-pi }

  # Identity
  prefix                      = var.prefix
  powervs_zone                = var.powervs_zone
  powervs_resource_group_name = var.powervs_resource_group_name

  # SSH
  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  # External management access (set to your public IP, or null when using VPN only)
  external_access_ip = var.external_access_ip

  # VPC — single VPC, 1 mandatory + up to 2 optional subnets
  vpc_subnet_cidrs       = var.vpc_subnet_cidrs
  transit_gateway_global = var.transit_gateway_global

  # Site-to-Site VPN (replaces Client-to-Site)
  site_to_site_vpn = var.site_to_site_vpn

  # Network services VSI (Squid proxy, DNS forwarder, NTP forwarder)
  vpc_intel_image              = var.vpc_intel_image
  network_services_vsi_profile = var.network_services_vsi_profile
  configure_dns_forwarder      = var.configure_dns_forwarder
  configure_ntp_forwarder      = var.configure_ntp_forwarder
  dns_forwarder_config         = var.dns_forwarder_config

  # PowerVS — single subnet
  powervs_network = var.powervs_network

  # IBM i 7.5 instance
  ibmi_instance = var.ibmi_instance

  # Monitoring (no new instance — pass existing CRN or leave null)
  existing_monitoring_instance_crn = var.existing_monitoring_instance_crn

  tags = var.tags
}
