terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "5.16.0"
    }
  }
}

provider "google" {
  credentials = file(var.serkey)
  project = var.projectname
  region = var.region
}


resource "google_compute_network" "new-vpc-network" {
  project                 = var.projectname
  name                    = "new-vpc-network"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "webapp" {
  name          = "webapp"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.new-vpc-network.self_link

}

resource "google_compute_subnetwork" "db" {
  name          = "db"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.new-vpc-network.self_link
}

resource "google_compute_route" "assign_route" {
  name                  = assign-route"
  network               = google_compute_network.new-vpc-network.self_link
  dest_range            = "0.0.0.0/0"
  next_hop_gateway      = "default-internet-gateway"
}