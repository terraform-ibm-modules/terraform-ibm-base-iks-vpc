##############################################################################
# base-iks-vpc-module
# Deploy IKS cluster in IBM Cloud on VPC Gen 2
##############################################################################

# Segregate pools, as we need default pool for cluster creation
locals {
  # ibm_container_vpc_cluster automatically names default pool "default" (See https://github.com/IBM-Cloud/terraform-provider-ibm/issues/2849)
  default_pool = element([for pool in var.worker_pools : pool if pool.pool_name == "default"], 0)

  default_kube_version = data.ibm_container_cluster_versions.cluster_versions.default_kube_version
  kube_version         = var.kube_version == null || var.kube_version == "default" ? local.default_kube_version : var.kube_version
  valid_versions_list  = data.ibm_container_cluster_versions.cluster_versions.valid_kube_versions
  valid_kube_versions  = [for version in local.valid_versions_list : regex("^([0-9]+\\.[0-9]+)", version)[0]]

  binaries_path = "/tmp"
}

# Lookup the current default kube version
data "ibm_container_cluster_versions" "cluster_versions" {}

# Check whether access tags are valid and exist in the account
data "ibm_iam_access_tag" "access_tags" {
  for_each = length(var.access_tags) != 0 ? toset(var.access_tags) : [] # Force dependency on data source validation to ensure access_tags exist and are valid before use.
  name     = each.value
}

module "cluster" {
  source = (
    "git::https://github.com/terraform-ibm-modules/terraform-ibm-base-cluster-vpc.git?ref=base-module"
  )

  cluster_type      = "kubernetes"
  cluster_name      = var.cluster_name
  resource_group_id = var.resource_group_id
  region            = var.region
  vpc_id            = var.vpc_id
  vpc_subnets       = var.vpc_subnets
  worker_pools      = var.worker_pools

  # Renamed from kube_version.
  cluster_version = var.kube_version

  # Renamed from enable_kube_version_upgrade.
  enable_cluster_version_upgrade = var.enable_kube_version_upgrade

  # Renamed from resource_tags.
  tags = var.resource_tags

  allow_default_worker_pool_replacement = (
    var.allow_default_worker_pool_replacement
  )
  ignore_worker_pool_size_changes = var.ignore_worker_pool_size_changes
  worker_pools_taints             = var.worker_pools_taints

  attach_ibm_managed_security_group = (
    var.attach_ibm_managed_security_group
  )
  custom_security_group_ids         = var.custom_security_group_ids
  additional_lb_security_group_ids  = var.additional_lb_security_group_ids
  number_of_lbs                     = var.number_of_lbs
  additional_vpe_security_group_ids = var.additional_vpe_security_group_ids

  cluster_ready_when      = var.cluster_ready_when
  disable_public_endpoint = var.disable_public_endpoint
  disable_outbound_traffic_protection = (
    var.disable_outbound_traffic_protection
  )
  force_delete_storage = var.force_delete_storage
  pod_subnet_cidr      = var.pod_subnet_cidr
  service_subnet_cidr  = var.service_subnet_cidr
  kms_config           = var.kms_config

  access_tags                  = var.access_tags
  cluster_config_endpoint_type = var.cluster_config_endpoint_type

  verify_worker_network_readiness = (
    var.verify_worker_network_readiness
  )
  install_required_binaries = var.install_required_binaries

  addons            = var.addons
  manage_all_addons = var.manage_all_addons

  cbr_rules = var.cbr_rules

  enable_secrets_manager_integration = (
    var.enable_secrets_manager_integration
  )
  existing_secrets_manager_instance_crn = (
    var.existing_secrets_manager_instance_crn
  )
  secrets_manager_secret_group_id = (
    var.secrets_manager_secret_group_id
  )
  skip_secrets_manager_iam_auth_policy = (
    var.skip_secrets_manager_iam_auth_policy
  )
}

##############################################################################
# State Migration - moved blocks
##############################################################################

moved {
  from = terraform_data.install_required_binaries[0]
  to   = module.cluster.terraform_data.install_required_binaries[0]
}

moved {
  from = ibm_container_vpc_cluster.iks_cluster[0]
  to   = module.cluster.ibm_container_vpc_cluster.cluster[0]
}

moved {
  from = ibm_container_vpc_cluster.cluster_with_upgrade[0]
  to   = module.cluster.ibm_container_vpc_cluster.cluster_with_upgrade[0]
}

moved {
  from = ibm_container_vpc_cluster.autoscaling_cluster[0]
  to   = module.cluster.ibm_container_vpc_cluster.autoscaling_cluster[0]
}

moved {
  from = ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade[0]
  to   = module.cluster.ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade[0]
}

moved {
  from = ibm_resource_tag.cluster_access_tag[0]
  to   = module.cluster.ibm_resource_tag.cluster_access_tag[0]
}

moved {
  from = data.ibm_container_cluster_config.cluster_config[0]
  to   = module.cluster.data.ibm_container_cluster_config.cluster_config[0]
}

moved {
  from = module.worker_pools
  to   = module.cluster.module.worker_pools
}

moved {
  from = terraform_data.confirm_network_healthy[0]
  to   = module.cluster.terraform_data.confirm_network_healthy[0]
}

moved {
  from = ibm_container_addons.addons[0]
  to   = module.cluster.ibm_container_addons.addons[0]
}

moved {
  from = terraform_data.config_map_status[0]
  to   = module.cluster.terraform_data.config_map_status[0]
}

moved {
  from = kubernetes_config_map_v1_data.set_autoscaling[0]
  to   = module.cluster.kubernetes_config_map_v1_data.set_autoscaling[0]
}

moved {
  from = data.ibm_is_lbs.all_lbs[0]
  to   = module.cluster.data.ibm_is_lbs.all_lbs[0]
}

moved {
  from = module.attach_sg_to_lb[0]
  to   = module.cluster.module.attach_sg_to_lb[0]
}

moved {
  from = data.ibm_is_virtual_endpoint_gateway.master_vpe[0]
  to   = module.cluster.data.ibm_is_virtual_endpoint_gateway.master_vpe[0]
}

moved {
  from = data.ibm_is_virtual_endpoint_gateway.api_vpe[0]
  to   = module.cluster.data.ibm_is_virtual_endpoint_gateway.api_vpe[0]
}

moved {
  from = data.ibm_is_virtual_endpoint_gateway.registry_vpe[0]
  to   = module.cluster.data.ibm_is_virtual_endpoint_gateway.registry_vpe[0]
}

moved {
  from = module.attach_sg_to_master_vpe[0]
  to   = module.cluster.module.attach_sg_to_master_vpe[0]
}

moved {
  from = module.attach_sg_to_api_vpe[0]
  to   = module.cluster.module.attach_sg_to_api_vpe[0]
}

moved {
  from = module.attach_sg_to_registry_vpe[0]
  to   = module.cluster.module.attach_sg_to_registry_vpe[0]
}

moved {
  from = module.cbr_rule[0]
  to   = module.cluster.module.cbr_rule[0]
}

moved {
  from = module.existing_secrets_manager_instance_parser[0]
  to   = module.cluster.module.existing_secrets_manager_instance_parser[0]
}

moved {
  from = ibm_iam_authorization_policy.secrets_manager_iam_auth_policy[0]
  to   = module.cluster.ibm_iam_authorization_policy.secrets_manager_iam_auth_policy[0]
}

moved {
  from = time_sleep.wait_for_auth_policy[0]
  to   = module.cluster.time_sleep.wait_for_auth_policy[0]
}

moved {
  from = ibm_container_ingress_instance.instance[0]
  to   = module.cluster.ibm_container_ingress_instance.instance[0]
}
