resource "google_compute_network" "vpc1_network" {
  project                 = var.gcp_project
  name                    = "vpc1-network"
  auto_create_subnetworks = false
  routing_mode            = var.routemode
  delete_default_routes_on_create = true
  mtu                     = 1460
}

resource "google_compute_subnetwork" "webapp" {
  name          = "webapp"
  ip_cidr_range = var.subwebapp
  region        = var.gcp_region
  network       = google_compute_network.vpc1_network.self_link


}

resource "google_compute_subnetwork" "db" {
  name          = "db"
  ip_cidr_range = var.subdb
  region        = var.gcp_region
  network       = google_compute_network.vpc1_network.self_link
}

resource "google_compute_route" "custom_route" {
  name                  = "custom-route"
  network               = google_compute_network.vpc1_network.self_link
  dest_range            = "0.0.0.0/0"
  next_hop_gateway      = "default-internet-gateway"
}

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.vpc1_network.name

  allow {
    protocol = "tcp"
    ports    = ["8888"] // Change to the port your application listens to
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "block_ssh" {
  name    = "block-ssh"
  network = google_compute_network.vpc1_network.name

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}


resource "google_compute_instance" "google-custom-instance" {
  name         = "google-custom-instance"
  machine_type = "n1-standard-1"
  zone         = "us-central1-a" // Change to your desired zone

  boot_disk {
    initialize_params {
      image = "custom-image"
      size  = 100  # Size in GB
      type  = "pd-balanced"

       // Use the name of your custom image
    }
  }

  network_interface {
    network = google_compute_network.vpc1_network.self_link
    subnetwork = google_compute_subnetwork.webapp.self_link
    access_config {}
  }

  metadata_startup_script = "echo 'Instance created.' >> /var/log/startup_script.log" // Optional startup script
}
