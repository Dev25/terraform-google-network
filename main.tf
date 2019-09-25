/**
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/******************************************
	VPC configuration
 *****************************************/
resource "google_compute_network" "network" {
  name                    = var.network_name
  auto_create_subnetworks = var.auto_create_subnetworks
  routing_mode            = var.routing_mode
  project                 = var.project_id
  description             = var.description
}

/******************************************
	Shared VPC
 *****************************************/
resource "google_compute_shared_vpc_host_project" "shared_vpc_host" {
  count      = var.shared_vpc_host == "true" ? 1 : 0
  project    = var.project_id
  depends_on = [google_compute_network.network]
}

/******************************************
	Subnet configuration
 *****************************************/
resource "google_compute_subnetwork" "subnetwork" {
  for_each = var.subnets

  name                     = each.value["subnet_name"]
  ip_cidr_range            = each.value["subnet_ip"]
  region                   = each.value["subnet_region"]
  private_ip_google_access = lookup(each.value, "subnet_private_access", "false")
  enable_flow_logs         = lookup(each.value, "subnet_flow_logs", "false")
  network                  = google_compute_network.network.name
  project                  = var.project_id
  description              = lookup(each.value, "description", null)

  secondary_ip_range = [
    for range_name, ip_cidr_range in lookup(each.value, "secondary_ranges", {}) : {
      range_name    = range_name
      ip_cidr_range = ip_cidr_range
    }
  ]
}


/******************************************
	Routes
 *****************************************/
resource "google_compute_route" "route" {
  for_each = var.routes

  project                = var.project_id
  network                = var.network_name
  name                   = lookup(each.value, "name", format("%s-%s-%d", lower(var.network_name), "route", each.key))
  description            = lookup(each.value, "description", "")
  tags                   = compact(split(",", lookup(each.value, "tags", "")))
  dest_range             = lookup(each.value, "destination_range", "")
  next_hop_gateway       = lookup(each.value, "next_hop_internet", "") == "true" ? "default-internet-gateway" : ""
  next_hop_ip            = lookup(each.value, "next_hop_ip", "")
  next_hop_instance      = lookup(each.value, "next_hop_instance", "")
  next_hop_instance_zone = lookup(each.value, "next_hop_instance_zone", "")
  next_hop_vpn_tunnel    = lookup(each.value, "next_hop_vpn_tunnel", "")
  priority               = lookup(each.value, "priority", "1000")

  depends_on = [
    google_compute_network.network,
    google_compute_subnetwork.subnetwork,
  ]
}

resource "null_resource" "delete_default_internet_gateway_routes" {
  count = var.delete_default_internet_gateway_routes ? 1 : 0

  provisioner "local-exec" {
    command = "${path.module}/scripts/delete-default-gateway-routes.sh ${var.project_id} ${var.network_name}"
  }

  triggers = {
    number_of_routes = length(var.routes)
  }

  depends_on = [
    google_compute_network.network,
    google_compute_subnetwork.subnetwork,
    google_compute_route.route,
  ]
}
