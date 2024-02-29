terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">=4.0, <5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }
  }
}

provider "google" {
  credentials = file(var.gcp_svc_key)
  project = var.gcp_project
  region = var.gcp_region
}

