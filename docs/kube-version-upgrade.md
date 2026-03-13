# Managing Kubernetes version upgrades

This document explains how to manage Kubernetes version upgrades for your IBM Cloud Kubernetes Service (IKS) cluster using this Terraform module.

## Understanding version management

By default, the module is configured to prevent Terraform from managing major Kubernetes version upgrades. This is intentional to avoid unintended version changes that could impact your workloads.

### Default behavior (recommended)

With `enable_kube_version_upgrade = false` (the default):

- Terraform will provision the cluster with the specified Kubernetes version
- IBM Cloud will automatically apply patch updates (e.g., 1.28.1 → 1.28.2)
- Terraform will ignore these patch updates (no drift)
- Major version upgrades (e.g., 1.28 → 1.29) must be done manually through the IBM Cloud console or CLI

### Advanced behavior

With `enable_kube_version_upgrade = true`:

- Terraform will manage major Kubernetes version upgrades
- You can update the `kube_version` variable to trigger an upgrade
- This gives you full control but requires careful state management

## Upgrading Kubernetes versions

### Method 1: Manual upgrade (recommended for most users)

This is the safest approach for production clusters:

1. **Plan the upgrade**:
   - Review the [Kubernetes version information](https://cloud.ibm.com/docs/containers?topic=containers-cs_versions)
   - Check for breaking changes in the target version
   - Plan a maintenance window

2. **Upgrade through IBM Cloud**:
   ```bash
   # Using IBM Cloud CLI
   ibmcloud ks cluster master update --cluster <cluster_name> --version <version>
   ```

   Or use the IBM Cloud console:
   - Navigate to your cluster
   - Click "Update version"
   - Select the target version
   - Confirm the upgrade

3. **Update your Terraform configuration**:
   After the upgrade is complete, update your `kube_version` variable to match:
   ```hcl
   kube_version = "1.29"
   ```

4. **Run Terraform**:
   ```bash
   terraform plan  # Should show no changes
   terraform apply
   ```

### Method 2: Terraform-managed upgrade (advanced users)

For advanced users who want Terraform to manage version upgrades:

#### Initial setup for existing clusters

If you have an existing cluster with `enable_kube_version_upgrade = false`, you need to migrate the Terraform state:

1. **Backup your state**:
   ```bash
   terraform state pull > backup.tfstate
   ```

2. **Enable version upgrades**:
   ```hcl
   enable_kube_version_upgrade = true
   ```

3. **Move the state**:
   ```bash
   # If using autoscaling
   terraform state mv 'module.iks_cluster.ibm_container_vpc_cluster.autoscaling_cluster[0]' \
                      'module.iks_cluster.ibm_container_vpc_cluster.autoscaling_cluster_with_upgrade[0]'

   # If not using autoscaling
   terraform state mv 'module.iks_cluster.ibm_container_vpc_cluster.iks_cluster[0]' \
                      'module.iks_cluster.ibm_container_vpc_cluster.cluster_with_upgrade[0]'
   ```

4. **Verify**:
   ```bash
   terraform plan  # Should show no changes
   ```

#### Performing the upgrade

Once `enable_kube_version_upgrade = true` is set:

1. **Update the version**:
   ```hcl
   kube_version = "1.29"  # New version
   ```

2. **Plan and apply**:
   ```bash
   terraform plan
   terraform apply
   ```

3. **Monitor the upgrade**:
   ```bash
   ibmcloud ks cluster get --cluster <cluster_name>
   ```

## Version specification

### Specifying versions

You can specify the Kubernetes version in several ways:

```hcl
# Use the current default version
kube_version = null  # or omit the variable

# Use the explicit default
kube_version = "default"

# Specify a major.minor version (recommended)
kube_version = "1.29"

# Specify a full version
kube_version = "1.29.2"
```

### Version validation

The module validates that the specified version is supported by IBM Cloud. If you specify an unsupported version, you'll see an error message listing the valid versions.

## Upgrade considerations

### Pre-upgrade checklist

Before upgrading:

- [ ] Review the [Kubernetes changelog](https://kubernetes.io/releases/) for breaking changes
- [ ] Check IBM Cloud's [version information](https://cloud.ibm.com/docs/containers?topic=containers-cs_versions) for IKS-specific changes
- [ ] Test the upgrade in a non-production environment
- [ ] Backup critical data and configurations
- [ ] Review and update deprecated API usage in your workloads
- [ ] Ensure your applications are compatible with the new version
- [ ] Plan for potential downtime during the master upgrade

### Upgrade process

The upgrade happens in stages:

1. **Master upgrade**: The Kubernetes master is upgraded first
   - Brief API server downtime (typically 5-10 minutes)
   - Workloads continue running
   - No kubectl access during upgrade

2. **Worker node upgrade**: Worker nodes are upgraded after the master
   - Can be done manually or automatically
   - Workloads are rescheduled during node updates
   - Use pod disruption budgets to control impact

### Post-upgrade tasks

After upgrading:

1. **Verify cluster health**:
   ```bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

2. **Update worker nodes**:
   ```bash
   ibmcloud ks worker update --cluster <cluster_name> --worker <worker_id>
   ```

3. **Test applications**: Verify that all workloads are functioning correctly

4. **Update add-ons**: Ensure cluster add-ons are compatible with the new version

## Example configurations

### Production cluster (manual upgrades)

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  cluster_name      = "production-cluster"
  resource_group_id = var.resource_group_id
  region            = "us-south"
  vpc_id            = var.vpc_id
  vpc_subnets       = var.vpc_subnets

  # Use default behavior - manual upgrades
  enable_kube_version_upgrade = false
  kube_version                = "1.29"

  worker_pools = [
    {
      pool_name        = "default"
      machine_type     = "bx2.4x16"
      workers_per_zone = 3
      operating_system = "REDHAT_8_64"
      subnet_prefix    = "default"
    }
  ]
}
```

### Development cluster (Terraform-managed upgrades)

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  cluster_name      = "dev-cluster"
  resource_group_id = var.resource_group_id
  region            = "us-south"
  vpc_id            = var.vpc_id
  vpc_subnets       = var.vpc_subnets

  # Enable Terraform-managed upgrades for dev
  enable_kube_version_upgrade = true
  kube_version                = "1.29"

  worker_pools = [
    {
      pool_name        = "default"
      machine_type     = "bx2.4x16"
      workers_per_zone = 2
      operating_system = "REDHAT_8_64"
      subnet_prefix    = "default"
    }
  ]
}
```

## Troubleshooting

### Upgrade fails with version incompatibility

**Problem**: The upgrade fails because the target version is not compatible.

**Solution**:
- Check that you're upgrading to a supported version
- Ensure you're not skipping major versions (e.g., 1.27 → 1.29)
- Upgrade incrementally if needed (1.27 → 1.28 → 1.29)

### Terraform shows drift after manual upgrade

**Problem**: After manually upgrading through IBM Cloud, Terraform shows changes.

**Solution**:
- Update your `kube_version` variable to match the current cluster version
- Run `terraform apply` to sync the state

### State migration fails

**Problem**: The state move command fails during migration to upgrade-enabled mode.

**Solution**:
- Verify you're using the correct resource path
- Check if you're using autoscaling (`ignore_worker_pool_size_changes = true`)
- Ensure you have a state backup before attempting migration

## Best practices

1. **Test upgrades**: Always test version upgrades in non-production environments first
2. **Use manual upgrades for production**: The default behavior (manual upgrades) is safer for production
3. **Stay current**: Keep your clusters within 2-3 minor versions of the latest release
4. **Plan maintenance windows**: Schedule upgrades during low-traffic periods
5. **Monitor after upgrades**: Watch cluster and application metrics after upgrading
6. **Document your process**: Keep a runbook for your upgrade procedures
7. **Use pod disruption budgets**: Protect critical workloads during node updates

## Additional resources

- [IBM Cloud Kubernetes Service version information](https://cloud.ibm.com/docs/containers?topic=containers-cs_versions)
- [Kubernetes version skew policy](https://kubernetes.io/releases/version-skew-policy/)
- [Updating clusters, worker nodes, and cluster components](https://cloud.ibm.com/docs/containers?topic=containers-update)
