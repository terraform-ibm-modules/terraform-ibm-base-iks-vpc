locals {
  # ibm_container_vpc_cluster automatically names default pool "default" (See https://github.com/IBM-Cloud/terraform-provider-ibm/issues/2849)
  default_pool = element([for pool in var.worker_pools : pool if pool.pool_name == "default"], 0)

  default_kube_version = data.ibm_container_cluster_versions.cluster_versions.default_kube_version
  kube_version         = var.kube_version == null || var.kube_version == "default" ? local.default_kube_version : var.kube_version
  valid_versions_list  = data.ibm_container_cluster_versions.cluster_versions.valid_kube_versions
  valid_kube_versions  = [for version in local.valid_versions_list : regex("^([0-9]+\\.[0-9]+)", version)[0]]

  delete_timeout = "2h"
  create_timeout = "3h"
  update_timeout = "3h"

  # tflint-ignore: terraform_unused_declarations
  cluster_with_upgrade_id = var.ignore_worker_pool_size_changes ? try(ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade[0].id, null) : try(ibm_container_vpc_cluster.cluster_with_upgrade[0].id, null)
  # tflint-ignore: terraform_unused_declarations
  cluster_without_upgrade_id = var.ignore_worker_pool_size_changes ? try(ibm_container_vpc_cluster.autoscaling_cluster[0].id, null) : try(ibm_container_vpc_cluster.iks_cluster[0].id, null)

  cluster_id = var.enable_kube_version_upgrade ? local.cluster_with_upgrade_id : local.cluster_without_upgrade_id

  # tflint-ignore: terraform_unused_declarations
  cluster_with_upgrade_crn = var.ignore_worker_pool_size_changes ? try(ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade[0].crn, null) : try(ibm_container_vpc_cluster.cluster_with_upgrade[0].crn, null)
  # tflint-ignore: terraform_unused_declarations
  cluster_without_upgrade_crn = var.ignore_worker_pool_size_changes ? try(ibm_container_vpc_cluster.autoscaling_cluster[0].crn, null) : try(ibm_container_vpc_cluster.iks_cluster[0].crn, null)

  cluster_crn = var.enable_kube_version_upgrade ? local.cluster_with_upgrade_crn : local.cluster_without_upgrade_crn

  # security group attached to worker pool
  # the terraform provider / iks api take a security group id hardcoded to "cluster", so this pseudo-value is injected into the array based on attach_default_cluster_security_group

  # attach_ibm_managed_security_group is true and custom_security_group_ids is not set => default behavior, so set to null
  # attach_ibm_managed_security_group is true and custom_security_group_ids is set => add "cluster" to the list of custom security group ids

  # attach_ibm_managed_security_group is false and custom_security_group_ids is not set => default behavior, so set to null
  # attach_ibm_managed_security_group is false and custom_security_group_ids is set => only use the custom security group ids
  cluster_security_groups = var.attach_ibm_managed_security_group == true ? (var.custom_security_group_ids == null ? null : concat(["cluster"], var.custom_security_group_ids)) : (var.custom_security_group_ids == null ? null : var.custom_security_group_ids)

  binaries_path = "/tmp"
}

# Lookup the current default kube version
data "ibm_container_cluster_versions" "cluster_versions" {}

resource "terraform_data" "install_required_binaries" {
  count = var.install_required_binaries && (var.verify_worker_network_readiness || lookup(var.addons, "cluster-autoscaler", null) != null) ? 1 : 0
  triggers_replace = {
    verify_worker_network_readiness = var.verify_worker_network_readiness
    cluster_autoscaler              = lookup(var.addons, "cluster-autoscaler", null) != null
  }
  provisioner "local-exec" {
    # Using the script from the kube-audit module to avoid code duplication.
    command     = "${path.module}/scripts/install-binaries.sh ${local.binaries_path}"
    interpreter = ["/bin/bash", "-c"]
  }
}

# ****************************************************************
#                     CREATE A IKS CLUSTER
# ****************************************************************

resource "ibm_container_vpc_cluster" "iks_cluster" {
  count                               = var.enable_kube_version_upgrade ? 0 : (var.ignore_worker_pool_size_changes ? 0 : 1)
  name                                = var.cluster_name
  vpc_id                              = var.vpc_id
  resource_group_id                   = var.resource_group_id
  tags                                = var.tags
  kube_version                        = local.kube_version
  flavor                              = local.default_pool.machine_type
  worker_count                        = local.default_pool.workers_per_zone
  wait_till                           = var.cluster_ready_when
  pod_subnet                          = var.pod_subnet_cidr
  service_subnet                      = var.service_subnet_cidr
  operating_system                    = local.default_pool.operating_system
  security_groups                     = local.cluster_security_groups
  force_delete_storage                = var.force_delete_storage
  disable_outbound_traffic_protection = var.disable_outbound_traffic_protection

  lifecycle {
    ignore_changes = [kube_version]
  }

  # default workers are mapped to the subnets that are "private"
  dynamic "zones" {
    for_each = local.default_pool.subnet_prefix != null ? var.vpc_subnets[local.default_pool.subnet_prefix] : local.default_pool.vpc_subnets
    content {
      subnet_id = zones.value.id
      name      = zones.value.zone
    }
  }

  # Apply taints to the default worker pools i.e private
  dynamic "taints" {
    for_each = var.worker_pools_taints == null ? [] : concat(var.worker_pools_taints["all"], var.worker_pools_taints["default"])
    content {
      effect = taints.value.effect
      key    = taints.value.key
      value  = taints.value.value
    }
  }

  dynamic "kms_config" {
    for_each = var.kms_config != null ? [1] : []
    content {
      crk_id           = var.kms_config.crk_id
      instance_id      = var.kms_config.instance_id
      private_endpoint = var.kms_config.private_endpoint
      account_id       = var.kms_config.account_id
      wait_for_apply   = var.kms_config.wait_for_apply
    }
  }

  timeouts {
    # Extend create, update and delete timeout to static values.
    create = local.create_timeout
    update = local.update_timeout
    delete = local.delete_timeout
  }

}

# copy of the cluster resource above which allows major kubernetes version upgrade
resource "ibm_container_vpc_cluster" "cluster_with_upgrade" {
  count                               = var.enable_kube_version_upgrade ? (var.ignore_worker_pool_size_changes ? 0 : 1) : 0
  name                                = var.cluster_name
  vpc_id                              = var.vpc_id
  resource_group_id                   = var.resource_group_id
  tags                                = var.tags
  kube_version                        = local.kube_version
  flavor                              = local.default_pool.machine_type
  worker_count                        = local.default_pool.workers_per_zone
  wait_till                           = var.cluster_ready_when
  pod_subnet                          = var.pod_subnet_cidr
  service_subnet                      = var.service_subnet_cidr
  operating_system                    = local.default_pool.operating_system
  security_groups                     = local.cluster_security_groups
  force_delete_storage                = var.force_delete_storage
  disable_outbound_traffic_protection = var.disable_outbound_traffic_protection

  # This resource intentionally omits ignore_changes for kube_version to allow major version upgrades

  # default workers are mapped to the subnets that are "private"
  dynamic "zones" {
    for_each = local.default_pool.subnet_prefix != null ? var.vpc_subnets[local.default_pool.subnet_prefix] : local.default_pool.vpc_subnets
    content {
      subnet_id = zones.value.id
      name      = zones.value.zone
    }
  }

  # Apply taints to the default worker pools i.e private
  dynamic "taints" {
    for_each = var.worker_pools_taints == null ? [] : concat(var.worker_pools_taints["all"], var.worker_pools_taints["default"])
    content {
      effect = taints.value.effect
      key    = taints.value.key
      value  = taints.value.value
    }
  }

  dynamic "kms_config" {
    for_each = var.kms_config != null ? [1] : []
    content {
      crk_id           = var.kms_config.crk_id
      instance_id      = var.kms_config.instance_id
      private_endpoint = var.kms_config.private_endpoint
      account_id       = var.kms_config.account_id
      wait_for_apply   = var.kms_config.wait_for_apply
    }
  }

  timeouts {
    # Extend create, update and delete timeout to static values.
    create = local.create_timeout
    update = local.update_timeout
    delete = local.delete_timeout
  }
}


# copy of the cluster resource above which ignores changes to the worker pool for use in autoscaling scenarios
resource "ibm_container_vpc_cluster" "autoscaling_cluster" {
  count                               = var.enable_kube_version_upgrade ? 0 : (var.ignore_worker_pool_size_changes ? 1 : 0)
  name                                = var.cluster_name
  vpc_id                              = var.vpc_id
  resource_group_id                   = var.resource_group_id
  tags                                = var.tags
  kube_version                        = local.kube_version
  flavor                              = local.default_pool.machine_type
  worker_count                        = local.default_pool.workers_per_zone
  wait_till                           = var.cluster_ready_when
  pod_subnet                          = var.pod_subnet_cidr
  service_subnet                      = var.service_subnet_cidr
  operating_system                    = local.default_pool.operating_system
  security_groups                     = local.cluster_security_groups
  force_delete_storage                = var.force_delete_storage
  disable_outbound_traffic_protection = var.disable_outbound_traffic_protection

  lifecycle {
    ignore_changes = [kube_version, worker_count]
  }

  # default workers are mapped to the subnets that are "private"
  dynamic "zones" {
    for_each = local.default_pool.subnet_prefix != null ? var.vpc_subnets[local.default_pool.subnet_prefix] : local.default_pool.vpc_subnets
    content {
      subnet_id = zones.value.id
      name      = zones.value.zone
    }
  }

  # Apply taints to the default worker pools i.e private
  dynamic "taints" {
    for_each = var.worker_pools_taints == null ? [] : concat(var.worker_pools_taints["all"], var.worker_pools_taints["default"])
    content {
      effect = taints.value.effect
      key    = taints.value.key
      value  = taints.value.value
    }
  }

  dynamic "kms_config" {
    for_each = var.kms_config != null ? [1] : []
    content {
      crk_id           = var.kms_config.crk_id
      instance_id      = var.kms_config.instance_id
      private_endpoint = var.kms_config.private_endpoint
      account_id       = var.kms_config.account_id
      wait_for_apply   = var.kms_config.wait_for_apply
    }
  }

  timeouts {
    # Extend create, update and delete timeout to static values.
    create = local.create_timeout
    update = local.update_timeout
    delete = local.delete_timeout
  }

}

# copy of the cluster resource above which allows major kubernetes version upgrade
resource "ibm_container_vpc_cluster" "autoscaling_cluster_with_upgrade" {
  count                               = var.enable_kube_version_upgrade ? (var.ignore_worker_pool_size_changes ? 1 : 0) : 0
  name                                = var.cluster_name
  vpc_id                              = var.vpc_id
  resource_group_id                   = var.resource_group_id
  tags                                = var.tags
  kube_version                        = local.kube_version
  flavor                              = local.default_pool.machine_type
  worker_count                        = local.default_pool.workers_per_zone
  wait_till                           = var.cluster_ready_when
  pod_subnet                          = var.pod_subnet_cidr
  service_subnet                      = var.service_subnet_cidr
  operating_system                    = local.default_pool.operating_system
  security_groups                     = local.cluster_security_groups
  force_delete_storage                = var.force_delete_storage
  disable_outbound_traffic_protection = var.disable_outbound_traffic_protection

  lifecycle {
    ignore_changes = [worker_count]
  }

  # default workers are mapped to the subnets that are "private"
  dynamic "zones" {
    for_each = local.default_pool.subnet_prefix != null ? var.vpc_subnets[local.default_pool.subnet_prefix] : local.default_pool.vpc_subnets
    content {
      subnet_id = zones.value.id
      name      = zones.value.zone
    }
  }

  # Apply taints to the default worker pools i.e private
  dynamic "taints" {
    for_each = var.worker_pools_taints == null ? [] : concat(var.worker_pools_taints["all"], var.worker_pools_taints["default"])
    content {
      effect = taints.value.effect
      key    = taints.value.key
      value  = taints.value.value
    }
  }

  dynamic "kms_config" {
    for_each = var.kms_config != null ? [1] : []
    content {
      crk_id           = var.kms_config.crk_id
      instance_id      = var.kms_config.instance_id
      private_endpoint = var.kms_config.private_endpoint
      account_id       = var.kms_config.account_id
      wait_for_apply   = var.kms_config.wait_for_apply
    }
  }

  timeouts {
    # Extend create, update and delete timeout to static values.
    create = local.create_timeout
    update = local.update_timeout
    delete = local.delete_timeout
  }
}

##############################################################################
# Cluster Access Tag
##############################################################################


resource "ibm_resource_tag" "cluster_access_tag" {
  count       = length(var.access_tags) == 0 ? 0 : 1
  resource_id = local.cluster_crn
  tags        = var.access_tags
  tag_type    = "access"
}


##############################################################################
# Access cluster to kick off RBAC synchronisation
##############################################################################

data "ibm_container_cluster_config" "cluster_config" {
  count             = (var.verify_worker_network_readiness || lookup(var.addons, "cluster-autoscaler", null) != null) ? 1 : 0
  cluster_name_id   = local.cluster_id
  config_dir        = "${path.module}/kubeconfig"
  admin             = true
  resource_group_id = var.resource_group_id
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
}

module "worker_pools" {
  source                                = "./modules/worker-pool"
  vpc_id                                = var.vpc_id
  resource_group_id                     = var.resource_group_id
  cluster_id                            = local.cluster_id
  vpc_subnets                           = var.vpc_subnets
  worker_pools                          = var.worker_pools
  ignore_worker_pool_size_changes       = var.ignore_worker_pool_size_changes
  allow_default_worker_pool_replacement = var.allow_default_worker_pool_replacement
  worker_pools_taints                   = var.worker_pools_taints
}


##############################################################################
# Confirm network healthy by ensuring master can communicate with all workers.
#
# Please note:
# The network health check is applicable only if the cluster is accessible.
#
# To do this, we run a script to execute "kubectl logs" against each calico
# daemonset pod (as there will be one pod per node) and ensure it passes.
#
# Why?
# There can be a delay in getting the routes set up for the VPN that lets
# the master connect across accounts down to the workers, and that VPN
# connection is what is used by "kubectl logs".
#
# Why is there a delay?
# The network microservice has to trigger on new workers being created and
# push down an updated vpn config, and then the vpn server and client need
# to pick up this updated config. Depending on how busy the network
# microservice is handling requests, there might be a delay.

##############################################################################

resource "terraform_data" "confirm_network_healthy" {

  count = var.verify_worker_network_readiness ? 1 : 0

  # Worker pool creation can start before the 'ibm_container_vpc_cluster' completes since there is no explicit
  # depends_on in 'ibm_container_vpc_worker_pool', just an implicit depends_on on the cluster ID. Cluster ID can exist before
  # 'ibm_container_vpc_cluster' completes, so hence need to add explicit depends on against 'ibm_container_vpc_cluster' here.
  depends_on = [
    terraform_data.install_required_binaries,
    ibm_container_vpc_cluster.iks_cluster,
    ibm_container_vpc_cluster.cluster_with_upgrade,
    ibm_container_vpc_cluster.autoscaling_cluster,
    ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade,
    module.worker_pools
  ]

  provisioner "local-exec" {
    command     = "${path.module}/scripts/confirm_network_healthy.sh"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = data.ibm_container_cluster_config.cluster_config[0].config_file_path
    }
  }
}

##############################################################################
# Addons
##############################################################################

locals {
  addons = { for addon_name, addon_version in(var.addons != null ? var.addons : {}) : addon_name => addon_version if addon_version != null }
}

resource "ibm_container_addons" "addons" {
  count = length(local.addons) > 0 ? 1 : 0
  depends_on = [
    ibm_container_vpc_cluster.iks_cluster,
    ibm_container_vpc_cluster.cluster_with_upgrade,
    ibm_container_vpc_cluster.autoscaling_cluster,
    ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade,
    module.worker_pools,
    terraform_data.confirm_network_healthy
  ]

  cluster           = local.cluster_id
  resource_group_id = var.resource_group_id

  # setting to false means we do not want Terraform to manage addons that are managed elsewhere
  manage_all_addons = var.manage_all_addons

  dynamic "addons" {
    for_each = local.addons
    content {
      name            = addons.key
      version         = lookup(addons.value, "version", null)
      parameters_json = lookup(addons.value, "parameters_json", null)
    }
  }

  timeouts {
    create = "1h"
  }
}

locals {
  worker_pool_config = [
    for worker in var.worker_pools :
    {
      name    = worker.pool_name
      minSize = worker.minSize
      maxSize = worker.maxSize
      enabled = worker.enableAutoscaling
    } if worker.enableAutoscaling != null && worker.minSize != null && worker.maxSize != null
  ]

}

resource "terraform_data" "config_map_status" {
  count      = lookup(var.addons, "cluster-autoscaler", null) != null ? 1 : 0
  depends_on = [terraform_data.install_required_binaries, ibm_container_addons.addons]

  provisioner "local-exec" {
    command     = "${path.module}/scripts/get_config_map_status.sh"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = data.ibm_container_cluster_config.cluster_config[0].config_file_path
    }
  }
}

resource "kubernetes_config_map_v1_data" "set_autoscaling" {
  count      = lookup(var.addons, "cluster-autoscaler", null) != null ? 1 : 0
  depends_on = [terraform_data.config_map_status]

  metadata {
    name      = "iks-ca-configmap"
    namespace = "kube-system"
  }

  data = {
    "workerPoolsConfig.json" = jsonencode(local.worker_pool_config)
  }

  force = true
}

##############################################################################
# Attach additional security groups to the load balancers managed by this
# cluster. Note that the module attaches security group to existing loadbalancer
# only. Re-run the module to attach security groups to new load balancers created
# after the initial run of this module. The module detects new load balancers.
##############################################################################

data "ibm_is_lbs" "all_lbs" {
  depends_on = [
    ibm_container_vpc_cluster.iks_cluster,
    ibm_container_vpc_cluster.cluster_with_upgrade,
    ibm_container_vpc_cluster.autoscaling_cluster,
    ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade,
    module.worker_pools,
    terraform_data.confirm_network_healthy
  ]

  count = length(var.additional_lb_security_group_ids) > 0 ? 1 : 0
}

locals {
  lbs_associated_with_cluster = length(var.additional_lb_security_group_ids) > 0 ? [for lb in data.ibm_is_lbs.all_lbs[0].load_balancers : lb.id if strcontains(lb.name, local.cluster_id)] : []
}

module "attach_sg_to_lb" {
  count                          = length(var.additional_lb_security_group_ids)
  source                         = "terraform-ibm-modules/security-group/ibm"
  version                        = "2.8.0"
  existing_security_group_id     = var.additional_lb_security_group_ids[count.index]
  use_existing_security_group_id = true
  target_ids                     = [for index in range(var.number_of_lbs) : local.lbs_associated_with_cluster[index]] # number_of_lbs is necessary to give a static number of elements to tf to accomplish the apply when the cluster does not initially exists
}

##############################################################################
# Attach additional security groups to the load balancers managed by this
# cluster. Note that the module attaches security group to existing loadbalancer
# only. Re-run the module to attach security groups to new load balancers created
# after the initial run of this module. The module detects new load balancers.
##############################################################################

locals {
  vpes_to_attach_to_sg = {
    "master" : "iks-${local.cluster_id}",
    "api" : "iks-api-${var.vpc_id}",
    "registry" : "iks-registry-${var.vpc_id}"
  }
}

data "ibm_is_virtual_endpoint_gateway" "master_vpe" {
  count = length(var.additional_vpe_security_group_ids["master"])
  depends_on = [ibm_container_vpc_cluster.iks_cluster,
    ibm_container_vpc_cluster.cluster_with_upgrade,
    ibm_container_vpc_cluster.autoscaling_cluster,
    ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade,
    module.worker_pools,
    terraform_data.confirm_network_healthy
  ]
  name = local.vpes_to_attach_to_sg["master"]
}

data "ibm_is_virtual_endpoint_gateway" "api_vpe" {
  count = length(var.additional_vpe_security_group_ids["api"])
  depends_on = [
    ibm_container_vpc_cluster.iks_cluster,
    ibm_container_vpc_cluster.cluster_with_upgrade,
    ibm_container_vpc_cluster.autoscaling_cluster,
    ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade,
    module.worker_pools,
    terraform_data.confirm_network_healthy
  ]
  name = local.vpes_to_attach_to_sg["api"]
}

data "ibm_is_virtual_endpoint_gateway" "registry_vpe" {
  count = length(var.additional_vpe_security_group_ids["registry"])
  depends_on = [
    ibm_container_vpc_cluster.iks_cluster,
    ibm_container_vpc_cluster.cluster_with_upgrade,
    ibm_container_vpc_cluster.autoscaling_cluster,
    ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade,
    module.worker_pools,
    terraform_data.confirm_network_healthy
  ]
  name = local.vpes_to_attach_to_sg["registry"]
}

locals {
  # loading cluster master, cluster API and registry VPE IDs to attach related SGs
  master_vpe_id   = length(var.additional_vpe_security_group_ids["master"]) > 0 ? data.ibm_is_virtual_endpoint_gateway.master_vpe[0].id : null
  api_vpe_id      = length(var.additional_vpe_security_group_ids["api"]) > 0 ? data.ibm_is_virtual_endpoint_gateway.api_vpe[0].id : null
  registry_vpe_id = length(var.additional_vpe_security_group_ids["registry"]) > 0 ? data.ibm_is_virtual_endpoint_gateway.registry_vpe[0].id : null
}

module "attach_sg_to_master_vpe" {
  count                          = length(var.additional_vpe_security_group_ids["master"])
  source                         = "terraform-ibm-modules/security-group/ibm"
  version                        = "2.8.0"
  existing_security_group_id     = var.additional_vpe_security_group_ids["master"][count.index]
  use_existing_security_group_id = true
  target_ids                     = [local.master_vpe_id]
}

module "attach_sg_to_api_vpe" {
  count                          = length(var.additional_vpe_security_group_ids["api"])
  source                         = "terraform-ibm-modules/security-group/ibm"
  version                        = "2.8.0"
  existing_security_group_id     = var.additional_vpe_security_group_ids["api"][count.index]
  use_existing_security_group_id = true
  target_ids                     = [local.api_vpe_id]
}

module "attach_sg_to_registry_vpe" {
  count                          = length(var.additional_vpe_security_group_ids["registry"])
  source                         = "terraform-ibm-modules/security-group/ibm"
  version                        = "2.8.0"
  existing_security_group_id     = var.additional_vpe_security_group_ids["registry"][count.index]
  use_existing_security_group_id = true
  target_ids                     = [local.registry_vpe_id]
}


##############################################################################
# Context Based Restrictions
##############################################################################
locals {
  default_operations = [{
    api_types = [
      {
        "api_type_id" : "crn:v1:bluemix:public:context-based-restrictions::::api-type:"
      }
    ]
  }]
}
module "cbr_rule" {
  count            = length(var.cbr_rules) > 0 ? length(var.cbr_rules) : 0
  source           = "terraform-ibm-modules/cbr/ibm//modules/cbr-rule-module"
  version          = "1.33.7"
  rule_description = var.cbr_rules[count.index].description
  enforcement_mode = var.cbr_rules[count.index].enforcement_mode
  rule_contexts    = var.cbr_rules[count.index].rule_contexts
  resources = [{
    attributes = [
      {
        name     = "accountId"
        value    = var.cbr_rules[count.index].account_id
        operator = "stringEquals"
      },
      {
        name     = "serviceInstance"
        value    = local.cluster_id
        operator = "stringEquals"
      },
      {
        name     = "serviceName"
        value    = "containers-kubernetes"
        operator = "stringEquals"
      }
    ],
  }]
  operations = var.cbr_rules[count.index].operations == null ? local.default_operations : var.cbr_rules[count.index].operations
}


##############################################################
# Ingress Secrets Manager Integration
##############################################################

module "existing_secrets_manager_instance_parser" {
  count   = var.enable_secrets_manager_integration ? 1 : 0
  source  = "terraform-ibm-modules/common-utilities/ibm//modules/crn-parser"
  version = "1.2.0"
  crn     = var.existing_secrets_manager_instance_crn
}

resource "ibm_iam_authorization_policy" "secrets_manager_iam_auth_policy" {
  count = var.enable_secrets_manager_integration && !var.skip_secrets_manager_iam_auth_policy ? 1 : 0
  depends_on = [
    ibm_container_vpc_cluster.iks_cluster,
    ibm_container_vpc_cluster.cluster_with_upgrade,
    ibm_container_vpc_cluster.autoscaling_cluster,
    ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade,
    module.worker_pools
  ]
  source_service_name         = "containers-kubernetes"
  source_resource_instance_id = local.cluster_id
  target_service_name         = "secrets-manager"
  target_resource_instance_id = module.existing_secrets_manager_instance_parser[0].service_instance
  roles                       = ["Manager"]
}

resource "time_sleep" "wait_for_auth_policy" {
  count           = var.enable_secrets_manager_integration ? 1 : 0
  depends_on      = [ibm_iam_authorization_policy.secrets_manager_iam_auth_policy]
  create_duration = "30s"
}


resource "ibm_container_ingress_instance" "instance" {
  count           = var.enable_secrets_manager_integration ? 1 : 0
  depends_on      = [time_sleep.wait_for_auth_policy]
  cluster         = var.cluster_name
  instance_crn    = var.existing_secrets_manager_instance_crn
  is_default      = true
  secret_group_id = var.secrets_manager_secret_group_id
}
