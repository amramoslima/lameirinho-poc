##################################################################
# Lameirinho — Provider configuration
# PowerVS uses a different region alias from VPC (ibm-is)
##################################################################

locals {
  # PowerVS zone → short region (used by ibm-pi provider)
  ibm_powervs_zone_region_map = {
    "syd04"    = "syd"
    "syd05"    = "syd"
    "sao01"    = "sao"
    "sao04"    = "sao"
    "sao05"    = "sao"
    "tor01"    = "tor"
    "mon01"    = "mon"
    "eu-de-1"  = "eu-de"
    "eu-de-2"  = "eu-de"
    "mad02"    = "mad"
    "mad04"    = "mad"
    "lon04"    = "lon"
    "lon06"    = "lon"
    "osa21"    = "osa"
    "tok04"    = "tok"
    "us-south" = "us-south"
    "dal10"    = "us-south"
    "dal12"    = "us-south"
    "dal14"    = "us-south"
    "us-east"  = "us-east"
    "wdc06"    = "us-east"
    "wdc07"    = "us-east"
    "che02"    = "che"
    "che03"    = "che"
    "in-mum-1" = "in-mum"
    "in-mum-2" = "in-mum"
  }

  # PowerVS zone → IBM Cloud region (used by ibm-is provider)
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
}

# VPC / IBM Cloud resources
provider "ibm" {
  alias            = "ibm-is"
  region           = lookup(local.ibm_powervs_zone_cloud_region_map, var.powervs_zone, null)
  zone             = var.powervs_zone
  ibmcloud_api_key = var.ibmcloud_api_key
}

# Power Virtual Server resources
provider "ibm" {
  alias            = "ibm-pi"
  region           = lookup(local.ibm_powervs_zone_region_map, var.powervs_zone, null)
  zone             = var.powervs_zone
  ibmcloud_api_key = var.ibmcloud_api_key
}

data "ibm_iam_auth_token" "auth_token" {
  provider = ibm.ibm-is
}

provider "restapi" {
  uri = "https://resource-controller.cloud.ibm.com"
  headers = {
    Authorization = data.ibm_iam_auth_token.auth_token.iam_access_token
  }
  write_returns_object = true
}
