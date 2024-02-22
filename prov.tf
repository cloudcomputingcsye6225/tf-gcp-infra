


terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "5.16.0"
    }
  }
}

provider "google" {
  credentials = file(var.gcp_svc_key)
  project = var.gcp_project
  region = var.gcp_region
}

