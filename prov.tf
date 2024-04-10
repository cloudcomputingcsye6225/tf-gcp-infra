terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">=4.0, <5.0"
    }
    google-beta = {
    source = "hashicorp/google-beta"
    version = ">=5.0, <6.0"
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

