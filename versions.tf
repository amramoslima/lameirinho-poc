##################################################################
# Lameirinho — PowerVS with single-VPC Landing Zone (simplified)
##################################################################

terraform {
  required_version = ">= 1.9"
  required_providers {
    ibm = {
      source  = "ibm-cloud/ibm"
      version = "2.8.0"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "2.0.1"
    }
  }
}
