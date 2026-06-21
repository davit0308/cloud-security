# =============================================================================
# AEGIS PORTAL – AUTOMATED IAC GENERATION (OPENSTACK PRIVATE CLOUD DIRECT)
# =============================================================================

provider "openstack" {
  auth_url = "http://openstack-control-plane:5000/v3"
  region   = "RegionOne"
}

# ── NEUTRON NETWORK ───────────────────────────────────────────────────────────
resource "openstack_networking_network_v2" "tenant_net" {
  name           = "os-internal-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "tenant_subnet" {
  name       = "aegis-subnet"
  network_id = openstack_networking_network_v2.tenant_net.id
  cidr       = "192.168.10.0/24"
  ip_version = 4
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}

# ── SECURITY GROUP DATABASE ───────────────────────────────────────────────────
resource "openstack_networking_secgroup_v2" "db_secgroup" {
  name        = "aegis-db-secgroup"
  description = "Security Group cho Database Node – Project aegis"
}

resource "openstack_networking_secgroup_rule_v2" "db_ingress_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3306
  port_range_max    = 3306
  remote_ip_prefix  = "10.10.0.0/16"
  security_group_id = openstack_networking_secgroup_v2.db_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "db_egress_rule" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.db_secgroup.id
}

# ── COMPUTE INSTANCE ──────────────────────────────────────────────────────────
resource "openstack_compute_instance_v2" "app_node" {
  name            = "aegis-vm"
  image_name      = "Ubuntu-24.04-LTS"
  flavor_name     = "m1.medium"
  key_pair        = "deployer-key"
  security_groups = [openstack_networking_secgroup_v2.db_secgroup.name]

  network {
    name = "os-internal-network"
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.ubuntu.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = 20
    boot_index            = 0
    delete_on_termination = true
  }

  metadata = {
    Environment = "staging"
    Project     = "aegis"
    ManagedBy   = "Aegis-Portal"
  }
}

data "openstack_images_image_v2" "ubuntu" {
  name        = "Ubuntu-24.04-LTS"
  most_recent = true
}

# ── OUTPUTS ───────────────────────────────────────────────────────────────────
output "instance_id" { value = openstack_compute_instance_v2.app_node.id }
output "instance_ip" { value = openstack_compute_instance_v2.app_node.access_ip_v4 }
output "secgroup_id" { value = openstack_networking_secgroup_v2.db_secgroup.id }
