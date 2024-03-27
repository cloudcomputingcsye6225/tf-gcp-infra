resource "google_project_service" "private_services_access" {
  project = var.gcp_project
  service = "servicenetworking.googleapis.com"
  depends_on = [ google_compute_network.vpc1_network ]
}

resource "google_compute_network" "vpc1_network" {
  project                 = var.gcp_project
  name                    = "vpc1-network"
  auto_create_subnetworks = false
  routing_mode            = var.routemode
  delete_default_routes_on_create = true
  mtu                     = 1460
}

resource "google_compute_subnetwork" "webapp" {
  project = var.gcp_project
  name          = "webapp"
  ip_cidr_range = var.subwebapp
  region        = var.gcp_region
  network       = google_compute_network.vpc1_network.self_link
  private_ip_google_access = true
  depends_on    = [google_compute_network.vpc1_network]
}

resource "google_compute_subnetwork" "db" {
  project = var.gcp_project
  name          = "db"
  ip_cidr_range = var.subdb
  region        = var.gcp_region
  network       = google_compute_network.vpc1_network.self_link
  depends_on    = [google_compute_network.vpc1_network]
}

resource "google_compute_route" "custom_route" {
  project = var.gcp_project
  name                  = "custom-route"
  network               = google_compute_network.vpc1_network.self_link
  dest_range            = "0.0.0.0/0"
  next_hop_gateway      = "default-internet-gateway"
  depends_on            = [google_compute_network.vpc1_network]
}

resource "google_compute_firewall" "allow_http" {
  project = var.gcp_project
  name    = "allow-http"
  network = google_compute_network.vpc1_network.name

  allow {
    protocol = "tcp"
    ports    = ["8888"]
  }

  source_ranges = ["0.0.0.0/0"]
  depends_on    = [google_compute_network.vpc1_network]
}

resource "google_compute_firewall" "block_ssh" {
  project = var.gcp_project
  name    = "block-ssh"
  network = google_compute_network.vpc1_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  depends_on    = [google_compute_network.vpc1_network]
}

resource "google_compute_firewall" "cloudsql_access" {
  project = var.gcp_project
  name    = "allow-cloudsql-access"
  network = google_compute_network.vpc1_network.name

  allow {
    protocol = "tcp"
    ports    = ["8888","3306"]
  }

  source_tags = [google_compute_instance.google_custom_instance.name]
  target_tags = [google_sql_database_instance.cloudsql_instance.name]
  depends_on    = [google_compute_network.vpc1_network, google_compute_instance.google_custom_instance, google_sql_database_instance.cloudsql_instance]
}

resource "google_compute_global_address" "private_service_address" {
  project               = var.gcp_project
  name                  = "private-service-address"
  purpose               = "VPC_PEERING"
  address_type          = "INTERNAL"
  network               = google_compute_network.vpc1_network.id
  prefix_length         = 24
  depends_on = [google_compute_network.vpc1_network]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc1_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_address.name]
  depends_on              = [google_project_service.private_services_access, 
                            google_compute_global_address.private_service_address, 
                            google_compute_network.vpc1_network]
}

resource "google_sql_database" "cloudsql_database" {
  project = var.gcp_project
  name     = "webapp"
  instance = google_sql_database_instance.cloudsql_instance.name
  depends_on = [ google_sql_database_instance.cloudsql_instance ]
}

resource "google_sql_database_instance" "cloudsql_instance" {
  name             = "cloudsql-instance"
  project          = var.gcp_project
  region           = var.gcp_region
  deletion_protection = false
  database_version = "MYSQL_8_0"
  depends_on = [google_project_service.private_services_access, 
                google_compute_network.vpc1_network,
                google_service_networking_connection.private_vpc_connection,
                google_compute_global_address.private_service_address]
  
  settings {
    tier = var.tier
    availability_type = var.routemode
    disk_type = var.disk_type
    disk_size = var.disk_size
    ip_configuration {
      ipv4_enabled = false
      private_network = google_compute_network.vpc1_network.self_link
    }
    backup_configuration {
      binary_log_enabled = true
      enabled = true
    }
  }
}

resource "random_password" "cloudsql_password" {
  length  = 16
  upper   = true
  lower   = true
  number  = true
  override_special = "!&#"
  depends_on = [ google_sql_database_instance.cloudsql_instance ]
}

resource "google_sql_user" "cloudsql_user" {
  project = var.gcp_project
  name     = "webapp"
  instance = google_sql_database_instance.cloudsql_instance.name
  password = random_password.cloudsql_password.result
  depends_on = [ google_sql_database_instance.cloudsql_instance ]
}

resource "google_compute_instance" "google_custom_instance" {
  project = var.gcp_project
  name         = "google-custom-instance"
  machine_type = "n1-standard-1"
  zone         = var.zone
  depends_on = [google_sql_database_instance.cloudsql_instance , 
                google_compute_network.vpc1_network, 
                google_compute_subnetwork.webapp, 
                google_compute_subnetwork.db, 
                google_sql_database_instance.cloudsql_instance,
                google_sql_database.cloudsql_database,
                google_sql_user.cloudsql_user,
                google_service_account.my_service_account,
                google_project_iam_binding.my_service_account_metric_writer,
                google_project_iam_binding.my_service_account_roles,
                google_project_iam_binding.service_account_token_creator_binding,
                google_project_iam_binding.pubsub_publisher_binding,
                google_project_iam_binding.pubsub_subscriber_binding,
                google_pubsub_topic.verify_email_topic]

  boot_disk {
    initialize_params {
      image = "custom-image"
      size  = 100
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = google_compute_network.vpc1_network.self_link
    subnetwork = google_compute_subnetwork.webapp.self_link
    access_config {
      
    }
  }

  service_account {
    email  = google_service_account.my_service_account.email
    scopes = ["userinfo-email", 
              "compute-ro", 
              "storage-ro", 
              "https://www.googleapis.com/auth/monitoring.write", 
              "https://www.googleapis.com/auth/logging.write",
              "https://www.googleapis.com/auth/pubsub"]
  }

  metadata = {
    MYSQL_HOST = google_sql_database_instance.cloudsql_instance.ip_address[0]["ip_address"]
    MYSQL_USER = google_sql_user.cloudsql_user.name
    MYSQL_PASSWORD = google_sql_user.cloudsql_user.password
    MYSQL_DATABASE = google_sql_database.cloudsql_database.name
    MYSQL_ROOT_PASSWORD = "root"
    MYSQL_PORT = "3306"
    GCP_PROJECT_ID = var.gcp_project
    GCP_TOPIC = google_pubsub_topic.verify_email_topic.name
  }
  metadata_startup_script = "/home/csye6225/reload_service.sh && touch /home/csye6225/reload_flag"
}

resource "google_dns_record_set" "www" {
  name    = "generalming.me."
  type    = "A"
  ttl     = 60
  managed_zone = var.dnszone

  rrdatas = [google_compute_instance.google_custom_instance.network_interface.0.access_config.0.nat_ip]
}

resource "google_dns_record_set" "generalmingme" {
  name    = "www.generalming.me."
  type    = "CNAME"
  ttl     = 60
  managed_zone = var.dnszone

  rrdatas = ["generalming.me."]
}

resource "google_service_account" "my_service_account" {
  account_id   = "iam-service-account"
  display_name = "iam binding roles"
}

resource "google_project_iam_binding" "my_service_account_roles" {
  project = var.gcp_project
  role    = "roles/logging.admin"
  depends_on = [ google_service_account.my_service_account ]
  members = [
    "serviceAccount:${google_service_account.my_service_account.email}"
  ]
}

resource "google_project_iam_binding" "my_service_account_metric_writer" {
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"
  depends_on = [ google_service_account.my_service_account ]
  members = [
    "serviceAccount:${google_service_account.my_service_account.email}"
  ]
}

resource "google_project_iam_binding" "service_account_token_creator_binding" {
  project = var.gcp_project
  role    = "roles/iam.serviceAccountTokenCreator"
  depends_on = [ google_service_account.my_service_account ]
  members = [
    "serviceAccount:${google_service_account.my_service_account.email}"
  ]
}

resource "google_project_iam_binding" "pubsub_publisher_binding" {
  project = var.gcp_project
  role    = "roles/pubsub.publisher"
  depends_on = [ google_service_account.my_service_account ]
  members = [
    "serviceAccount:${google_service_account.my_service_account.email}"
  ]
}

resource "google_project_iam_binding" "pubsub_subscriber_binding" {
  project = var.gcp_project
  role    = "roles/pubsub.subscriber"
  depends_on = [ google_service_account.my_service_account ]
  members = [
    "serviceAccount:${google_service_account.my_service_account.email}"
  ]
}

resource "google_project_iam_binding" "cloudsql_client" {
  project = var.gcp_project
  role    = "roles/cloudsql.client"
  members = ["serviceAccount:${google_service_account.my_service_account.email}"]
  depends_on = [google_service_account.my_service_account]
}

resource "google_vpc_access_connector" "vpc_connector_cloudsql" {
  name         = "vpc-connector-cloudsql"
  network      = google_compute_network.vpc1_network.self_link
  region       = var.gcp_region
  ip_cidr_range = var.connector_cidr
}

resource "google_pubsub_topic" "verify_email_topic" {
  name = "verify_email"
  message_storage_policy {
    allowed_persistence_regions = ["us-west1"]
  }
  message_retention_duration = "604800s"
}

resource "google_storage_bucket" "cloud_function_bucket" {
  name          = "cloud-function-source-bucket-2024-03-26"
  location      = "us-west1"
  force_destroy = true
  
  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_object" "cloud_function_object" {
  name   = "cloud_function_code.zip"
  bucket = google_storage_bucket.cloud_function_bucket.name
  source = var.cloud_function_code
  depends_on = [google_storage_bucket.cloud_function_bucket]
}

resource "google_cloudfunctions_function" "verify_email_function" {
  name        = "verify_email"
  runtime     = "python39" 
  source_archive_bucket = google_storage_bucket.cloud_function_bucket.name
  source_archive_object = google_storage_bucket_object.cloud_function_object.name
  ingress_settings = "ALLOW_ALL"
  vpc_connector = google_vpc_access_connector.vpc_connector_cloudsql.id
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource = google_pubsub_topic.verify_email_topic.name
  }
  environment_variables = {
    DATABASE_NAME = google_sql_database.cloudsql_database.name
    DATABASE_USER = google_sql_user.cloudsql_user.name
    DATABASE_PASSWORD = random_password.cloudsql_password.result
    DATABASE_HOST = google_sql_database_instance.cloudsql_instance.ip_address[0]["ip_address"]
  }
  depends_on = [
    google_pubsub_topic.verify_email_topic,
    random_password.cloudsql_password,
    google_sql_database_instance.cloudsql_instance,
    google_sql_database.cloudsql_database,
    google_sql_user.cloudsql_user,
    google_vpc_access_connector.vpc_connector_cloudsql
  ]
}
