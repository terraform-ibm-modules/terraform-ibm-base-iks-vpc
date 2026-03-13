# Security group management

This document explains how to manage security groups for your IBM Cloud Kubernetes Service (IKS) cluster using this Terraform module.

## Overview

The module provides comprehensive security group management for:

- **Worker nodes**: Control network access to and from cluster worker nodes
- **Load balancers**: Manage security for cluster load balancers
- **Virtual Private Endpoints (VPEs)**: Secure VPE connections for master, API, and registry

## Worker node security groups

### Default behavior

By default, IBM Cloud automatically creates and manages a security group for your cluster worker nodes. This security group is named `kube-<cluster-id>` and contains rules necessary for cluster operation.

### Custom security groups

You can add custom security groups to worker nodes in addition to or instead of the IBM-managed security group.

#### Adding custom security groups alongside IBM-managed group

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  # ... other configuration ...

  # Attach both IBM-managed and custom security groups
  attach_ibm_managed_security_group = true
  custom_security_group_ids = [
    "r006-xxxx-xxxx-xxxx-xxxx",  # Your custom security group
    "r006-yyyy-yyyy-yyyy-yyyy"   # Another custom security group
  ]
}
```

#### Using only custom security groups

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  # ... other configuration ...

  # Use only custom security groups (not recommended for most cases)
  attach_ibm_managed_security_group = false
  custom_security_group_ids = [
    "r006-xxxx-xxxx-xxxx-xxxx",
    "r006-yyyy-yyyy-yyyy-yyyy"
  ]
}
```

**Important**: When `attach_ibm_managed_security_group = false`, you are responsible for ensuring your custom security groups allow all necessary cluster traffic. This is an advanced configuration.

### Per-worker-pool security groups

You can also specify security groups for individual worker pools:

```hcl
worker_pools = [
  {
    pool_name                     = "default"
    machine_type                  = "bx2.4x16"
    workers_per_zone              = 2
    operating_system              = "REDHAT_8_64"
    subnet_prefix                 = "default"
    additional_security_group_ids = [
      "r006-aaaa-aaaa-aaaa-aaaa"  # Additional SG for this pool only
    ]
  },
  {
    pool_name                     = "compute"
    machine_type                  = "bx2.8x32"
    workers_per_zone              = 3
    operating_system              = "REDHAT_8_64"
    subnet_prefix                 = "default"
    additional_security_group_ids = [
      "r006-bbbb-bbbb-bbbb-bbbb"  # Different SG for this pool
    ]
  }
]
```

### Security group limits

- Maximum of 5 security groups per worker node (including IBM-managed)
- When using `custom_security_group_ids`, you can specify up to 4 custom groups
- Per-worker-pool security groups count toward this limit

## Load balancer security groups

IKS automatically creates load balancers for services of type `LoadBalancer`. You can attach additional security groups to these load balancers.

### Basic configuration

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  # ... other configuration ...

  # Attach security groups to load balancers
  additional_lb_security_group_ids = [
    "r006-xxxx-xxxx-xxxx-xxxx",
    "r006-yyyy-yyyy-yyyy-yyyy"
  ]

  # Specify the number of load balancers
  number_of_lbs = 1  # Adjust based on your services
}
```

### Important considerations

1. **Number of load balancers**: Set `number_of_lbs` to match the number of LoadBalancer services you plan to create
2. **Timing**: Security groups are attached to existing load balancers only
3. **Re-run required**: If you create new load balancers after initial deployment, re-run Terraform to attach security groups
4. **Maximum**: Up to 4 additional security groups per load balancer

### Example with multiple load balancers

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  # ... other configuration ...

  additional_lb_security_group_ids = [
    "r006-xxxx-xxxx-xxxx-xxxx"  # Allow HTTPS from specific CIDR
  ]

  number_of_lbs = 3  # Expecting 3 LoadBalancer services
}
```

## Virtual Private Endpoint (VPE) security groups

IKS creates VPEs for secure communication with the cluster master, API server, and container registry. You can attach additional security groups to these VPEs.

### VPE types

- **Master VPE**: Default VPE for cluster master communication (`iks-<cluster-id>`)
- **API VPE**: VPE for Kubernetes API server (`iks-api-<vpc-id>`)
- **Registry VPE**: VPE for container registry access (`iks-registry-<vpc-id>`)

### Configuration

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  # ... other configuration ...

  additional_vpe_security_group_ids = {
    master = [
      "r006-master-sg-1",
      "r006-master-sg-2"
    ]
    api = [
      "r006-api-sg-1"
    ]
    registry = [
      "r006-registry-sg-1"
    ]
  }
}
```

### Selective VPE security groups

You can configure security groups for specific VPEs only:

```hcl
# Only attach security groups to master VPE
additional_vpe_security_group_ids = {
  master = ["r006-master-sg-1"]
}

# Or only to API and registry VPEs
additional_vpe_security_group_ids = {
  api      = ["r006-api-sg-1"]
  registry = ["r006-registry-sg-1"]
}
```

## Complete example

Here's a comprehensive example showing all security group configurations:

```hcl
module "iks_cluster" {
  source  = "terraform-ibm-modules/base-iks-vpc/ibm"
  version = "X.Y.Z"

  cluster_name      = "secure-cluster"
  resource_group_id = var.resource_group_id
  region            = "us-south"
  vpc_id            = var.vpc_id
  vpc_subnets       = var.vpc_subnets

  # Worker node security groups
  attach_ibm_managed_security_group = true
  custom_security_group_ids = [
    var.worker_sg_id  # Custom rules for worker nodes
  ]

  # Load balancer security groups
  additional_lb_security_group_ids = [
    var.lb_sg_id  # Allow specific traffic to load balancers
  ]
  number_of_lbs = 2

  # VPE security groups
  additional_vpe_security_group_ids = {
    master = [
      var.master_vpe_sg_id  # Restrict master access
    ]
    api = [
      var.api_vpe_sg_id  # Control API server access
    ]
    registry = [
      var.registry_vpe_sg_id  # Manage registry access
    ]
  }

  worker_pools = [
    {
      pool_name        = "default"
      machine_type     = "bx2.4x16"
      workers_per_zone = 2
      operating_system = "REDHAT_8_64"
      subnet_prefix    = "default"
      # Pool-specific security group
      additional_security_group_ids = [
        var.default_pool_sg_id
      ]
    },
    {
      pool_name        = "compute"
      machine_type     = "bx2.8x32"
      workers_per_zone = 3
      operating_system = "REDHAT_8_64"
      subnet_prefix    = "default"
      # Different security group for compute pool
      additional_security_group_ids = [
        var.compute_pool_sg_id
      ]
    }
  ]
}
```

## Security group rules

### Required rules for worker nodes

If using custom security groups without the IBM-managed group, ensure your security groups allow:

**Inbound rules**:
- Cluster master to worker nodes (various ports for kubelet, etc.)
- Worker-to-worker communication (all ports)
- VPC DNS (port 53)
- Load balancer health checks

**Outbound rules**:
- Worker to cluster master
- Worker to IBM Cloud services
- Container registry access
- Internet access (if needed for pulling images)

### Example security group rules

```hcl
resource "ibm_is_security_group_rule" "worker_inbound_kubelet" {
  group     = ibm_is_security_group.worker_sg.id
  direction = "inbound"
  remote    = "10.0.0.0/8"  # Your VPC CIDR
  tcp {
    port_min = 10250
    port_max = 10250
  }
}

resource "ibm_is_security_group_rule" "worker_outbound_all" {
  group     = ibm_is_security_group.worker_sg.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}
```

## Best practices

1. **Use IBM-managed security group**: Keep `attach_ibm_managed_security_group = true` unless you have specific requirements
2. **Principle of least privilege**: Only allow necessary traffic in custom security groups
3. **Document rules**: Clearly document the purpose of each security group and rule
4. **Test thoroughly**: Test security group changes in non-production environments first
5. **Monitor connectivity**: Watch for connectivity issues after security group changes
6. **Use descriptive names**: Name security groups clearly to indicate their purpose
7. **Separate concerns**: Use different security groups for different types of traffic
8. **Plan for scale**: Consider future load balancers when setting `number_of_lbs`

## Troubleshooting

### Worker nodes can't communicate with master

**Problem**: Worker nodes show as "Not Ready" or can't connect to the master.

**Solution**:
- Verify security groups allow traffic from worker nodes to master VPE
- Check that the IBM-managed security group is attached (if using default configuration)
- Ensure VPC routing is correct

### Load balancer not accessible

**Problem**: Services of type LoadBalancer are not accessible.

**Solution**:
- Verify `number_of_lbs` is set correctly
- Check that security groups allow inbound traffic on service ports
- Re-run Terraform if load balancers were created after initial deployment
- Verify load balancer security group rules

### VPE connectivity issues

**Problem**: Cannot access cluster API or registry through VPE.

**Solution**:
- Check VPE security group rules allow necessary traffic
- Verify VPE is in the correct subnets
- Ensure DNS resolution is working for VPE endpoints

### Security group limit exceeded

**Problem**: Error about too many security groups.

**Solution**:
- Maximum 5 security groups per worker node
- Reduce the number of custom security groups
- Consolidate rules into fewer security groups

## Additional resources

- [IBM Cloud VPC security groups](https://cloud.ibm.com/docs/vpc?topic=vpc-using-security-groups)
- [IKS security best practices](https://cloud.ibm.com/docs/containers?topic=containers-security)
- [VPC network security](https://cloud.ibm.com/docs/vpc?topic=vpc-security-in-your-vpc)
