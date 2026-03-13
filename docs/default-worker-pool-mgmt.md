# Managing the default worker pool

When you create an IBM Cloud Kubernetes Service (IKS) cluster, a default worker pool is automatically created. This default pool is special because:

1. It cannot be deleted
2. It must always have at least one worker node
3. Certain modifications require special handling

## Understanding the default worker pool

The default worker pool is identified by the name `"default"` in your worker pools configuration. This pool is created during the initial cluster provisioning and serves as the foundation for your cluster.

## Making changes to the default worker pool

### Changes that don't require recreation

The following changes can be made without recreating the default worker pool:

- Scaling the number of workers (`workers_per_zone`)
- Adding or modifying labels
- Adding or modifying taints
- Changing security groups

### Changes that require recreation

The following changes require the default worker pool to be recreated:

- Changing the machine type (`machine_type`)
- Changing the operating system (`operating_system`)
- Changing the subnets or zones
- Changing boot volume encryption settings

## How to recreate the default worker pool

When you need to make changes that require recreation, follow these steps:

### Step 1: Enable recreation in your configuration

Set the `allow_default_worker_pool_replacement` variable to `true`:

```hcl
module "iks_cluster" {
  source = "terraform-ibm-modules/base-iks-vpc/ibm"
  # ... other configuration ...

  allow_default_worker_pool_replacement = true

  worker_pools = [
    {
      pool_name        = "default"
      machine_type     = "bx2.8x32"  # New machine type
      workers_per_zone = 2
      operating_system = "REDHAT_8_64"
      subnet_prefix    = "default"
    }
  ]
}
```

### Step 2: Apply the configuration

Run `terraform apply`. The module will:

1. Create a new worker pool with a temporary name
2. Wait for the new pool to be ready
3. Remove the old default pool
4. Rename the new pool to "default"

### Step 3: Reset the flag (optional)

After the recreation is complete, you can set `allow_default_worker_pool_replacement` back to `false` to prevent accidental changes:

```hcl
allow_default_worker_pool_replacement = false
```

## Important considerations

### Workload migration

When recreating the default worker pool:

1. **Plan for downtime**: Workloads running on the default pool will be rescheduled
2. **Use multiple worker pools**: For production workloads, use additional worker pools to ensure availability
3. **Check pod disruption budgets**: Ensure your PDBs allow for node draining

### State management

The recreation process involves Terraform state manipulation. Always:

1. **Backup your state**: Before making changes, backup your Terraform state
2. **Use version control**: Keep your Terraform configurations in version control
3. **Test in non-production**: Test the recreation process in a non-production environment first

## Example: Complete worker pool configuration

Here's a complete example showing both default and additional worker pools:

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  cluster_name                          = "my-iks-cluster"
  resource_group_id                     = var.resource_group_id
  region                                = "us-south"
  vpc_id                                = var.vpc_id
  vpc_subnets                           = var.vpc_subnets
  allow_default_worker_pool_replacement = false

  worker_pools = [
    {
      pool_name        = "default"
      machine_type     = "bx2.4x16"
      workers_per_zone = 2
      operating_system = "REDHAT_8_64"
      subnet_prefix    = "default"
      labels = {
        "pool" = "default"
      }
    },
    {
      pool_name        = "compute"
      machine_type     = "bx2.8x32"
      workers_per_zone = 3
      operating_system = "REDHAT_8_64"
      subnet_prefix    = "default"
      labels = {
        "pool"     = "compute"
        "workload" = "general"
      }
    }
  ]
}
```

## Troubleshooting

### Error: Cannot delete default worker pool

If you see this error, it means you're trying to remove the default pool. The default pool must always exist. Instead, you need to recreate it with the desired configuration.

### Error: Worker pool replacement not allowed

This error occurs when `allow_default_worker_pool_replacement` is `false` but you're trying to make changes that require recreation. Set the flag to `true` to proceed.

### Workers not draining properly

If workers are not draining properly during recreation:

1. Check that your workloads have proper pod disruption budgets
2. Ensure workloads can be scheduled on other nodes
3. Verify that there are no local storage dependencies

## Best practices

1. **Use multiple worker pools**: Don't rely solely on the default pool for production workloads
2. **Plan changes carefully**: Default pool recreation affects cluster availability
3. **Test thoroughly**: Always test changes in non-production environments first
4. **Monitor during changes**: Watch cluster and workload health during the recreation process
5. **Document your configuration**: Keep clear documentation of your worker pool requirements
