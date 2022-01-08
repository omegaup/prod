locals {
  locations = [
    "westus2",
  ]
}

resource "azurerm_resource_group" "runner" {
  name     = "omegaup-runner"
  location = "westus2"
}

resource "azurerm_user_assigned_identity" "runner" {
  name                = "omegaup-runner"
  resource_group_name = azurerm_resource_group.runner.name
  location            = "eastus"
}

resource "azurerm_resource_group" "runner_vmss" {
  count = length(local.locations)

  name     = "omegaup-runner-${local.locations[count.index]}"
  location = local.locations[count.index]
}

resource "azurerm_virtual_network" "runner_vmss" {
  count = length(local.locations)

  name                = "omegaup-runner-${local.locations[count.index]}-vnet"
  resource_group_name = azurerm_resource_group.runner_vmss[count.index].name
  location            = azurerm_resource_group.runner_vmss[count.index].location
  address_space       = ["172.16.0.0/16"]
}

resource "azurerm_subnet" "runner_vmss_default" {
  count = length(local.locations)

  name                 = "default"
  resource_group_name  = azurerm_resource_group.runner_vmss[count.index].name
  virtual_network_name = azurerm_virtual_network.runner_vmss[count.index].name
  address_prefixes     = ["172.16.0.0/16"]
}

resource "azurerm_network_security_group" "runner_vmss" {
  count = length(local.locations)

  name                = "omegaup-runner-${local.locations[count.index]}-nsg"
  resource_group_name = azurerm_resource_group.runner_vmss[count.index].name
  location            = azurerm_resource_group.runner_vmss[count.index].location

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

resource "azurerm_user_assigned_identity" "runner_vmss" {
  count = length(local.locations)

  name                = "omegaup-runner-${local.locations[count.index]}"
  resource_group_name = azurerm_resource_group.runner.name
  location            = azurerm_resource_group.runner.location
}

resource "azurerm_key_vault" "runner" {
  name = "omegaup-runner-vault"

  resource_group_name             = azurerm_resource_group.runner.name
  location                        = azurerm_resource_group.runner.location
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  enabled_for_template_deployment = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    certificate_permissions = [
      "Get",
      "List",
      "Delete",
      "Create",
      "Import",
      "Update",
      "ManageContacts",
      "GetIssuers",
      "ListIssuers",
      "SetIssuers",
      "DeleteIssuers",
      "ManageIssuers",
      "Recover",
    ]
    key_permissions = [
      "Get",
      "Create",
      "Delete",
      "List",
      "Update",
      "Import",
      "Backup",
      "Restore",
      "Recover",
    ]
    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Backup",
      "Restore",
      "Recover",
    ]
    storage_permissions = [
      "Get",
      "List",
      "Delete",
      "Set",
      "Update",
      "RegenerateKey",
      "SetSAS",
      "ListSAS",
      "GetSAS",
      "DeleteSAS",
    ]
  }
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.runner_vmss[0].principal_id

    certificate_permissions = [
      "Get",
    ]
    key_permissions = [
      "Get",
    ]
    secret_permissions = [
      "Get",
    ]
  }
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.runner.principal_id

    certificate_permissions = [
      "Get",
    ]
    key_permissions = [
      "Get",
    ]
    secret_permissions = [
      "Get",
    ]
  }
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.runner_image_builder.principal_id

    certificate_permissions = []
    key_permissions         = []
    secret_permissions = [
      "Get",
    ]
  }
}

resource "azurerm_linux_virtual_machine_scale_set" "runner_vmss" {
  count = length(local.locations)

  name                        = "omegaup-runner-${local.locations[count.index]}-vmss"
  resource_group_name         = azurerm_resource_group.runner_vmss[count.index].name
  location                    = azurerm_resource_group.runner_vmss[count.index].location
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
    grace_period = "PT15M"
  }

  boot_diagnostics {
  }

  custom_data = filebase64("${path.module}/files/cloud-init.yml")

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
  extension {
    auto_upgrade_minor_version = true
    automatic_upgrade_enabled  = false
    name                       = "KVVMExtensionForLinux"
    provision_after_extensions = []
    publisher                  = "Microsoft.Azure.KeyVault"
    settings = jsonencode(
      {
        secretsManagementSettings = {
          certificateStoreLocation = "/var/lib/waagent/Microsoft.Azure.KeyVault"
          certificateStoreName     = ""
          observedCertificates = [
            "${azurerm_key_vault.runner.vault_uri}secrets/omegaup-runner",
          ]
          pollingIntervalInS = "7200"
          requireInitialSync = true
        }
      }
    )
    type                 = "KeyVaultForLinux"
    type_handler_version = "2.0"
  }

  identity {
    identity_ids = [
      azurerm_user_assigned_identity.runner.id,
    ]
    type = "UserAssigned"
  }

  network_interface {
    dns_servers               = []
    name                      = "omegaup-runner-${local.locations[count.index]}-nic"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.runner_vmss[0].id

    ip_configuration {
      name      = "omegaup-runner-${local.locations[count.index]}-ipconfig"
      primary   = true
      subnet_id = azurerm_subnet.runner_vmss_default[count.index].id

      public_ip_address {
        name                    = "omegaup-runner-${local.locations[count.index]}-ipconfig-public"
        domain_name_label       = "omegaup-runner"
        idle_timeout_in_minutes = 30
      }
    }
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

  source_image_id = azurerm_shared_image_version.runner.id

  lifecycle {
    ignore_changes = [
      instances,
    ]
  }
}

resource "azurerm_resource_group" "grader" {
  name     = "omegaup-grader"
  location = "eastus"
}

resource "azurerm_application_insights" "grader" {
  name                = "omegaup-grader"
  resource_group_name = azurerm_resource_group.grader.name
  location            = "westus2"
  application_type    = "web"
  sampling_percentage = 0
}

resource "azurerm_monitor_autoscale_setting" "runner_vmss" {
  count = length(local.locations)

  name                = "omegaup-runner-${local.locations[count.index]}-autoscale"
  resource_group_name = azurerm_resource_group.runner_vmss[count.index].name
  location            = azurerm_resource_group.runner_vmss[count.index].location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.runner_vmss[count.index].id

  profile {
    name = "Default"

    capacity {
      default = 4
      minimum = 2
      maximum = 8
    }

    rule {
      metric_trigger {
        divide_by_instance_count = true
        metric_name              = "performanceCounters/requestsInQueue"
        metric_namespace         = "microsoft.insights/components"
        metric_resource_id       = azurerm_application_insights.grader.id
        statistic                = "Max"
        operator                 = "GreaterThan"
        threshold                = 5
        time_aggregation         = "Maximum"
        time_window              = "PT1M"
        time_grain               = "PT1M"
      }

      scale_action {
        cooldown  = "PT5M"
        type      = "ChangeCount"
        value     = 3
        direction = "Increase"
      }
    }
    rule {
      metric_trigger {
        divide_by_instance_count = true
        metric_name              = "performanceCounters/requestsInQueue"
        metric_namespace         = "microsoft.insights/components"
        metric_resource_id       = azurerm_application_insights.grader.id
        statistic                = "Max"
        operator                 = "LessThan"
        threshold                = 1
        time_aggregation         = "Maximum"
        time_window              = "PT5M"
        time_grain               = "PT1M"
      }

      scale_action {
        cooldown  = "PT5M"
        type      = "ChangeCount"
        value     = "1"
        direction = "Decrease"
      }
    }
  }
}
