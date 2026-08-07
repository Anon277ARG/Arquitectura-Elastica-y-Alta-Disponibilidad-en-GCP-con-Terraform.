provider "google" {#<-- Provider configuration for Google Cloud
  project = "cloud-lab-493"
  region  = "southamerica-west1"
}

variable "region" {#<-- Variable for region configuration
    type = string
    default = "southamerica-west1"
}    

resource "google_compute_network" "itaca_network" {#<-- Network configuration
    name = "itaca-network"
    routing_mode = "GLOBAL"
    auto_create_subnetworks = false
}
# Create a subnetwork for the instances to ensure they are in a private IP range ---------------------------------------------
resource "google_compute_subnetwork" "itaca_subnet" {
    name = "itaca-subnetwork"
    region = var.region
    ip_cidr_range = "10.0.0.0/24"
    network = google_compute_network.itaca_network.id
    private_ip_google_access = true
}
# Create a subnetwork specifically for the proxy to ensure it is in a different IP range than the instances --------------------------------
resource "google_compute_subnetwork" "itaca_proxy" {
    name = "itaca-subnetwork-proxy"
    region = var.region
    ip_cidr_range = "10.129.0.0/23"
    network = google_compute_network.itaca_network.id
    purpose = "REGIONAL_MANAGED_PROXY"
    role = "ACTIVE"
}
# Create a Cloud Router to manage the NAT configuration for the private subnet ------------------------------------------------
resource "google_compute_router" "itaca_router" {
    name = "itaca-router"
    region = var.region
    network = google_compute_network.itaca_network.id

}
# Create a Cloud NAT configuration for the router to allow instances in the private subnet to access the internet ----------------
resource "google_compute_router_nat" "itaca_nat" {
name = "intaca-mig-updatenat"
router = google_compute_router.itaca_router.name
region = var.region
nat_ip_allocate_option = "AUTO_ONLY"
source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

    log_config {
    enable = true
    filter = "ALL"
    }
}
# Firewall rule to allow health check traffic from Google's health check IP ranges ------------------------------------------------
resource "google_compute_firewall" "itaca_health_check" {
  name    = "itaca-health-check"
  network = google_compute_network.itaca_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  target_tags = ["itaca-firewalls"]
}
# Firewall rule to allow traffic to the instances from the proxy subnet ------------------------------------------------------
resource "google_compute_firewall" "itaca_firewall" {
  name    = "itaca-firewall"
  network = google_compute_network.itaca_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["10.129.0.0/23"]

  target_tags = ["itaca-firewalls"]
}
# Firewall rule to allow SSH access from the specified IP range ---------------------------------------------------------------
resource "google_compute_firewall" "allow_ssh_itaca" {
  name        = "allow-ssh-itaca"
  network     = google_compute_network.itaca_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]

  target_tags = ["itaca-firewalls"]
}
# Create a regional health check for the managed instance group ---------------------------------------------------------------
resource "google_compute_region_health_check" "itaca_check" {
  name        = "health-check-itaca"
  description = "Health check via https"
  region = var.region

  timeout_sec         = 5
  check_interval_sec  = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port = "8080"
    request_path = "/health" # La ruta del FastAPI
  }
}
# Create an instance template for the managed instance group ---------------------------------------------------------------
resource "google_compute_instance_template" "mig_template" {
  name        = "virtual-machine-template"
  description = "tose are thet templates used by the manage instance group."

  tags = ["itaca-firewalls"]

  labels = {
    environment = "virtual_machine"
  }

  instance_description = "description assigned to instances"
  machine_type         = "e2-micro"
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
  disk {
    source_image      = "debian-cloud/debian-11"
    auto_delete       = true
    boot              = true
  }
  network_interface {
    network = google_compute_network.itaca_network.id
    subnetwork = google_compute_subnetwork.itaca_subnet.id
  }

  metadata = {
    "serial-port-enable" = "true"
    "startup-script"     = <<-EOF
      #!/bin/bash
      apt-get update -y
      apt-get install -y python3 python3-pip stress
      pip3 install fastapi uvicorn

      cat > /home/main.py << 'PYEOF'
from fastapi import FastAPI
import socket

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/")
def home():
    return {
        "mensaje": "Instancia activa recibiendo trafico",
        "maquina": socket.gethostname()
    }
PYEOF
      cat > /home/estresar.sh << 'BASH_EOF'
#!/bin/bash
sleep 300
stress --cpu $(nproc) --timeout 960
BASH_EOF
      chmod +x /home/estresar.sh
      python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --app-dir /home &
      nohup /home/estresar.sh > /home/estresar.log 2>&1 &
    EOF
  }
}
# Create a managed instance group with the instance template ---------------------------------------------------------------
resource "google_compute_region_instance_group_manager" "mig" { 
 name = "itaca-mig"
 base_instance_name = "itaca-vm-"
 region = var.region
 version {
   instance_template = google_compute_instance_template.mig_template.id
 }
 named_port {
    name = "http"
    port = 8080
  }
 distribution_policy_zones = [
   "${var.region}-a",
   "${var.region}-b",
 ]
 auto_healing_policies {
   health_check = google_compute_region_health_check.itaca_check.id
   initial_delay_sec = 300
 }
}
# Create an autoscaler for the managed instance group ---------------------------------------------------------------------
resource "google_compute_region_autoscaler" "itaca_autoscaler" { #<---autoscaler
 name = "autoscaler-itaca"
 region = var.region
 target = google_compute_region_instance_group_manager.mig.id
 autoscaling_policy {
   min_replicas = 1
   max_replicas = 6
   cooldown_period = 180
   cpu_utilization {
     target = 0.8
   }
 }
}
# Create a backend service and associate it with the managed instance group ------------------------------------------------
resource "google_compute_region_backend_service" "itaca_backend" { #<--- backend service
  name = "itaca-backend-service"
  region = var.region
  protocol = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks = [google_compute_region_health_check.itaca_check.id]
  backend {
    group = google_compute_region_instance_group_manager.mig.instance_group
    balancing_mode = "UTILIZATION"
    capacity_scaler = 1.0
  }
}
# Create a URL map, target HTTP proxy, and forwarding rule to route traffic to the backend service -------------------------
resource "google_compute_region_url_map" "itaca_url_map" { #<--- url map
  name = "itaca-url-map"
  region = var.region
  default_service = google_compute_region_backend_service.itaca_backend.id
} 
# Create a target HTTP proxy and forwarding rule to route traffic to the backend service -----------------------------------
resource "google_compute_region_target_http_proxy" "itaca_target_proxy" { #<--- target http proxy
  name = "itaca-target-proxy"
  region = var.region
  url_map = google_compute_region_url_map.itaca_url_map.id
}
# Create a forwarding rule to route traffic to the target HTTP proxy ------------------------------------------------------
resource "google_compute_forwarding_rule" "itaca-forwarding-rule" { 
  name = "itaca-forwarding-rule"
  region = var.region 
  target = google_compute_region_target_http_proxy.itaca_target_proxy.id
  port_range = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  network = google_compute_network.itaca_network.id

}
# Output the IP address of the load balancer to access the application ------------------------------------------------------
output "ip_publica_balanceador" {
  value = google_compute_forwarding_rule.itaca-forwarding-rule.ip_address
}
