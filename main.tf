resource "google_project_service" "private_services_access" {
  project = var.gcp_project
  service = "servicenetworking.googleapis.com"
  depends_on = [ google_compute_network.vpc1_network ]
}

resource "google_project_service_identity" "cloudsql_sa" {
  provider = google-beta

  project = var.gcp_project
  service = "sqladmin.googleapis.com"
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
    protocol = "all"
  }
  priority = 999

  source_ranges= [google_compute_global_forwarding_rule.web_forwarding_rule.ip_address, "35.191.0.0/16", "130.211.0.0/22"]
  depends_on    = [google_compute_network.vpc1_network]
}

resource "google_compute_firewall" "block_ssh" {
  project = var.gcp_project
  name    = "block-ssh"
  network = google_compute_network.vpc1_network.name

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  depends_on    = [google_compute_network.vpc1_network]
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
  encryption_key_name = google_kms_crypto_key.sql_crypto_key.id
  database_version = "MYSQL_8_0"
  depends_on = [google_project_service.private_services_access, 
                google_compute_network.vpc1_network,
                google_service_networking_connection.private_vpc_connection,
                google_compute_global_address.private_service_address, google_kms_crypto_key_iam_binding.sql_key_crypto_key ]
  
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

resource "google_compute_region_instance_template" "web_instance_template" {
  name        = "web-instance-template"
  project     = var.gcp_project
  region      = var.gcp_region
  
  depends_on = [ google_kms_crypto_key_iam_binding.vm_key_crypto_key ]

  machine_type = "n1-standard-1"

  disk {
    source_image = "custom-image"
    auto_delete  = true
    type  = "pd-balanced"
    disk_size_gb = 100
    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.vm_crypto_key.id
    }
  }  

  network_interface {
    network = google_compute_network.vpc1_network.self_link
    subnetwork = google_compute_subnetwork.webapp.self_link
    access_config {}
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
  rrdatas = [google_compute_global_forwarding_rule.web_forwarding_rule.ip_address]
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

  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_crypto_key.id
  }
  
  versioning {
    enabled = true
  }
  depends_on = [ google_kms_crypto_key_iam_binding.storage_key_crypto_key ]
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

resource "google_compute_managed_ssl_certificate" "default" {
  name        = "managed-ssl-certificate"
  project     = var.gcp_project
  managed {
    domains = ["generalming.me.", "www.generalming.me."]
  }
}

resource "google_compute_backend_service" "web_backend_service" {
  name                    = "web-backend-service"
  project                 = var.gcp_project
  health_checks           = [google_compute_http_health_check.https_health_check.self_link]

  backend {
    group = google_compute_region_instance_group_manager.web_instance_group_manager.instance_group
  }

  timeout_sec = 60
}

resource "google_compute_url_map" "web_url_map" {
  name            = "web-url-map"
  project         = var.gcp_project
  default_service = google_compute_backend_service.web_backend_service.self_link
}

resource "google_compute_target_https_proxy" "web_https_proxy" {
  name      = "web-https-proxy"
  project   = var.gcp_project
  url_map   = google_compute_url_map.web_url_map.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.default.self_link]
}

resource "google_compute_global_forwarding_rule" "web_forwarding_rule" {
  name       = "web-forwarding-rule"
  project    = var.gcp_project
  target     = google_compute_target_https_proxy.web_https_proxy.self_link
  port_range = "443"
}

resource "google_compute_http_health_check" "https_health_check" {
  name               = "https-health-check"
  project            = var.gcp_project
  request_path       = "/healthz"
  port               = 8888
  check_interval_sec = 5
  timeout_sec        = 5
}

resource "google_compute_region_instance_group_manager" "web_instance_group_manager" {
  name               = "web-instance-group-manager"
  version {
    instance_template  = google_compute_region_instance_template.web_instance_template.self_link
  }
  project            = var.gcp_project
  base_instance_name = "web-instance"
  named_port {
    name = "http"
    port = 8888
  }
  auto_healing_policies {
    health_check = google_compute_http_health_check.https_health_check.self_link
    initial_delay_sec = 60
  }
}

resource "google_compute_firewall" "allow_lb_access" {
  name    = "allow-lb-access"
  project = var.gcp_project
  network = google_compute_network.vpc1_network.name

  allow {
    protocol = "tcp"
    ports    = ["8888", "22"]
  }

  source_ranges = [google_compute_global_forwarding_rule.web_forwarding_rule.ip_address]
  depends_on    = [google_compute_network.vpc1_network]
}

resource "google_compute_region_autoscaler" "web_autoscaler" {
  name               = "web-autoscaler"
  project            = var.gcp_project
  target             = google_compute_region_instance_group_manager.web_instance_group_manager.self_link
  autoscaling_policy {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas 
    cpu_utilization {
      target = var.cpu_utilization
    }
  }
}
/*
resource "google_kms_key_ring" "final_key_ring" {
  name     = "final-key-ring"
  location = var.gcp_region
}*/

resource "google_kms_crypto_key" "vm_crypto_key" {
  name       = var.vm_key_name
  key_ring = var.key_ring_id
  rotation_period = var.rotation_period
  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key" "sql_crypto_key" {
  name       = var.sql_key_name
  key_ring = var.key_ring_id
  rotation_period = var.rotation_period
  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key" "storage_crypto_key" {
  name       = var.storage_key_name
  key_ring   = var.key_ring_id
  rotation_period = var.rotation_period
  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key_iam_binding" "vm_key_crypto_key" {
  crypto_key_id = google_kms_crypto_key.vm_crypto_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.my_service_account.email}",
    "serviceAccount:service-661981349246@compute-system.iam.gserviceaccount.com"
  ]
}

resource "google_kms_crypto_key_iam_binding" "sql_key_crypto_key" {
  crypto_key_id = google_kms_crypto_key.sql_crypto_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_project_service_identity.cloudsql_sa.email}"
  ]
}

resource "google_kms_crypto_key_iam_binding" "storage_key_crypto_key" {
  crypto_key_id = google_kms_crypto_key.storage_crypto_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
  ]
}

data "google_storage_project_service_account" "gcs_account" {
}
