resource "azurerm_resource_group" "runner_beta" {
  count    = var.runner_beta ? 1 : 0
  name     = "omegaup-runner-beta"
  location = "westus2"
}

resource "azurerm_user_assigned_identity" "runner_beta" {
  count = var.runner_beta ? 1 : 0

  name                = "omegaup-runner-beta"
  resource_group_name = azurerm_resource_group.runner_beta[count.index].name
  location            = "eastus"
}

resource "azurerm_resource_group" "runner_beta_vmss" {
  count = var.runner_beta ? length(local.locations) : 0

  name     = "omegaup-runner-beta-${local.locations[count.index]}"
  location = local.locations[count.index]
}

resource "azurerm_virtual_network" "runner_beta_vmss" {
  count = var.runner_beta ? length(local.locations) : 0

  name                = "omegaup-runner-beta-${local.locations[count.index]}-vnet"
  resource_group_name = azurerm_resource_group.runner_beta_vmss[count.index].name
  location            = azurerm_resource_group.runner_beta_vmss[count.index].location
  address_space       = ["172.16.0.0/16"]
}

resource "azurerm_subnet" "runner_beta_vmss_default" {
  count = var.runner_beta ? length(local.locations) : 0

  name                 = "default"
  resource_group_name  = azurerm_resource_group.runner_beta_vmss[count.index].name
  virtual_network_name = azurerm_virtual_network.runner_beta_vmss[count.index].name
  address_prefixes     = ["172.16.0.0/16"]
}

resource "azurerm_network_security_group" "runner_beta_vmss" {
  count = var.runner_beta ? length(local.locations) : 0

  name                = "omegaup-runner-beta-${local.locations[count.index]}-nsg"
  resource_group_name = azurerm_resource_group.runner_beta_vmss[count.index].name
  location            = azurerm_resource_group.runner_beta_vmss[count.index].location

  security_rule {
    name                       = "SSH"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "TCP"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "prometheus-metrics"
    priority                   = 310
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "TCP"
    source_port_range          = "*"
    destination_port_range     = "6060"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_user_assigned_identity" "runner_beta_vmss" {
  count = var.runner_beta ? length(local.locations) : 0

  name                = "omegaup-runner-beta-${local.locations[count.index]}"
  resource_group_name = azurerm_resource_group.runner_beta[count.index].name
  location            = azurerm_resource_group.runner_beta[count.index].location
}

resource "azurerm_linux_virtual_machine_scale_set" "runner_beta_vmss" {
  count = var.runner_beta ? length(local.locations) : 0

  name                        = "omegaup-runner-beta-${local.locations[count.index]}-vmss"
  resource_group_name         = azurerm_resource_group.runner_beta_vmss[count.index].name
  location                    = azurerm_resource_group.runner_beta_vmss[count.index].location
  sku                         = "Standard_A1_v2"
  priority                    = "Spot"
  scale_in_policy             = "OldestVM"
  eviction_policy             = "Delete"
  admin_username              = "lhchavez"
  instances                   = 2
  single_placement_group      = false
  platform_fault_domain_count = 1
  upgrade_mode                = "Rolling"
  zones                       = ["1", "2", "3"]

  admin_ssh_key {
    username   = "lhchavez"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCnjhoOKyTPYdNViybSdZUobS5WsOuhZnGO3QWQqI8K5+op8gEzBJaV1XfwVMewbBFv1t8NNANBlqbkjAGwrbLVixz156fcnTpVKaXPF7L31UTSv3x3/7gjRkAnNAexVNQOR5uLzEqaC1WLzTZf1iN4VMLskmuEE1PYAR7JBoE7jwKc5w67Iu0aELhiZ2nGSXkNU9fuSA3O/EFRQMtUVY8KvRuCN5iSTuHhL3vm4TE39ZYfSCsPok0PAbnR0eIFObQYkp/EaJZitqALmxr9gFsK5AxlfbbGiOXlUP1et4tA1/6ep3CPCnUy6TNCwKuOdC8kMzHg9tYIl0qtpgibuLU3 lhchavez@lhc-desktop"
  }

  automatic_instance_repair {
    enabled      = true
    grace_period = "PT30M"
  }

  boot_diagnostics {
  }

  custom_data = filebase64("${path.module}/files/beta.cloud-init.yml")

  extension {
    auto_upgrade_minor_version = false
    automatic_upgrade_enabled  = false
    name                       = "HealthExtension"
    provision_after_extensions = []
    publisher                  = "Microsoft.ManagedServices"
    settings = jsonencode(
      {
        port        = 6060
        protocol    = "http"
        requestPath = "/metrics"
      }
    )
    type                 = "ApplicationHealthLinux"
    type_handler_version = "1.0"
  }

  identity {
    identity_ids = [
      azurerm_user_assigned_identity.runner_beta[count.index].id,
    ]
    type = "UserAssigned"
  }

  network_interface {
    dns_servers               = []
    name                      = "omegaup-runner-beta-${local.locations[count.index]}-nic"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.runner_beta_vmss[0].id

    ip_configuration {
      name      = "omegaup-runner-beta-${local.locations[count.index]}-ipconfig"
      primary   = true
      subnet_id = azurerm_subnet.runner_beta_vmss_default[count.index].id

      public_ip_address {
        name                    = "omegaup-runner-beta-${local.locations[count.index]}-ipconfig-public"
        domain_name_label       = "omegaup-runner-beta"
        idle_timeout_in_minutes = 30
      }
    }
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = 30
  }

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 20
    pause_time_between_batches              = "PT2S"
  }

  lifecycle {
    ignore_changes = [
      instances,
    ]
  }
}
resource "azurerm_monitor_autoscale_setting" "runner_beta_vmss" {
  count = var.runner_beta ? length(local.locations) : 0

  name                = "omegaup-runner-beta-${local.locations[count.index]}-autoscale"
  resource_group_name = azurerm_resource_group.runner_beta_vmss[count.index].name
  location            = azurerm_resource_group.runner_beta_vmss[count.index].location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.runner_beta_vmss[count.index].id

  profile {
    name = "Default"

    capacity {
      default = 4
      minimum = 4
      maximum = 4
    }
  }
}
