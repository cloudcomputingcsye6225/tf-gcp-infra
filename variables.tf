variable "gcp_svc_key"{
    default = "C:\\Users\\advai\\Downloads\\production-environment-415721-bd715ea2195c.json"
}

variable "gcp_project" {
    default = "production-environment-415721"
}

variable "gcp_region" {
    default = "us-west1"
}

variable "subwebapp" {
    default = "10.0.3.0/24"
}

variable "subdb" {
    default = "10.0.4.0/24"
}

variable "routemode" {
    default = "REGIONAL"
}

variable "zone" {
    default = "us-west1-a"
}

variable "dnszone" {
    default = "production"
}

variable "disk_size" {
    default = 100
}

variable "disk_type" {
    default = "pd-ssd"
}

variable "tier" {
    default = "db-f1-micro"
}

variable "cloud_function_code" {
    default = "./cloud_function_code.zip"
}

variable "connector_cidr" {
    default = "10.6.0.0/28"
}

variable "max_replicas" {
    default = 6
}

variable "min_replicas" {
    default = 3
}

variable "cpu_utilization" {
    default = 0.05
}

variable "rotation_period" {
    default = "86760s"
}

variable "key_ring_id" {
    default = "projects/production-environment-415721/locations/us-west1/keyRings/final-key-ring"
}

variable "vm_key_name" {
    default = "vmkey2"
}

variable "sql_key_name" {
    default = "sqlkey2"
}

variable "storage_key_name" {
    default = "storagekey2"
}
