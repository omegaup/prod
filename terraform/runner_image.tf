resource "azurerm_resource_group" "runner_image_builder" {
  name     = "omegaup-runner-image-builder"
  location = "westus2"
}

resource "azurerm_shared_image_gallery" "runner" {
  name                = "omegaup_runner"
  resource_group_name = azurerm_resource_group.runner_image_builder.name
  location            = azurerm_resource_group.runner_image_builder.location
  description         = "omegaUp runner image gallery"
}

resource "azurerm_shared_image" "runner" {
  name                = "omegaup-runner-image-20211231"
  gallery_name        = azurerm_shared_image_gallery.runner.name
  resource_group_name = azurerm_resource_group.runner_image_builder.name
  location            = azurerm_resource_group.runner_image_builder.location
  os_type             = "Linux"

  identifier {
    publisher = "omegaUp"
    offer     = "runner"
    sku       = "20211231"
  }
}

data "azurerm_image" "runner" {
  name                = "omegaup-runner-image-20220212"
  resource_group_name = azurerm_resource_group.runner_image_builder.name
}

resource "azurerm_shared_image_version" "runner" {
  name                = "1.0.3"
  gallery_name        = azurerm_shared_image_gallery.runner.name
  image_name          = azurerm_shared_image.runner.name
  resource_group_name = azurerm_resource_group.runner_image_builder.name
  location            = azurerm_resource_group.runner_image_builder.location
  managed_image_id    = data.azurerm_image.runner.id

  target_region {
    name                   = azurerm_shared_image.runner.location
    regional_replica_count = 1
    storage_account_type   = "Standard_ZRS"
  }
}

resource "azurerm_user_assigned_identity" "runner_image_builder" {
  name                = "omegaup-runner-image-builder"
  resource_group_name = azurerm_resource_group.runner_image_builder.name
  location            = azurerm_resource_group.runner_image_builder.location
}

resource "azurerm_role_definition" "runner_image_builder" {
  name  = "omegaup-runner-image-builder-role"
  scope = azurerm_resource_group.runner_image_builder.id

  permissions {
    actions = [
      "Microsoft.Compute/galleries/read",
      "Microsoft.Compute/galleries/images/read",
      "Microsoft.Compute/galleries/images/versions/read",
      "Microsoft.Compute/galleries/images/versions/write",
      "Microsoft.Compute/images/write",
      "Microsoft.Compute/images/read",
      "Microsoft.Compute/images/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [
    azurerm_resource_group.runner_image_builder.id,
  ]
}

resource "azurerm_role_assignment" "runner_image_builder" {
  scope              = azurerm_resource_group.runner_image_builder.id
  role_definition_id = azurerm_role_definition.runner_image_builder.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.runner_image_builder.principal_id
}

resource "azurerm_public_ip" "runner_image_builder" {
  count = var.az_runner_image ? 1 : 0

  name                = "omegaup-runner-image-builder-ip"
  resource_group_name = azurerm_resource_group.runner_image_builder.name
  location            = azurerm_resource_group.runner_image_builder.location
  allocation_method   = "Dynamic"
  domain_name_label   = "omegaup-runner-image-builder"
}

resource "azurerm_network_interface" "runner_image_builder" {
  count = var.az_runner_image ? 1 : 0

  name                = "omegaup-runner-image-builder-nic"
  resource_group_name = azurerm_resource_group.runner_image_builder.name
  location            = azurerm_resource_group.runner_image_builder.location

  ip_configuration {
    name                          = "omegaup-runner-image-builder-ipconfig"
    subnet_id                     = azurerm_subnet.runner_vmss_default[count.index].id
    private_ip_address_allocation = "Dynamic"

    public_ip_address_id = azurerm_public_ip.runner_image_builder[count.index].id
  }
}

resource "azurerm_linux_virtual_machine" "runner_image_builder" {
  count = var.az_runner_image ? 1 : 0

  name                  = "omegaup-runner-image-builder"
  resource_group_name   = azurerm_resource_group.runner_image_builder.name
  location              = azurerm_resource_group.runner_image_builder.location
  size                  = "Standard_A1_v2"
  admin_username        = "lhchavez"
  network_interface_ids = [azurerm_network_interface.runner_image_builder[count.index].id]
  custom_data           = filebase64("${path.module}/files/image-builder.cloud-init.yml")

  admin_ssh_key {
    username   = "lhchavez"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCnjhoOKyTPYdNViybSdZUobS5WsOuhZnGO3QWQqI8K5+op8gEzBJaV1XfwVMewbBFv1t8NNANBlqbkjAGwrbLVixz156fcnTpVKaXPF7L31UTSv3x3/7gjRkAnNAexVNQOR5uLzEqaC1WLzTZf1iN4VMLskmuEE1PYAR7JBoE7jwKc5w67Iu0aELhiZ2nGSXkNU9fuSA3O/EFRQMtUVY8KvRuCN5iSTuHhL3vm4TE39ZYfSCsPok0PAbnR0eIFObQYkp/EaJZitqALmxr9gFsK5AxlfbbGiOXlUP1et4tA1/6ep3CPCnUy6TNCwKuOdC8kMzHg9tYIl0qtpgibuLU3 lhchavez@lhc-desktop"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runner_image_builder.id]
  }

  tags = {
    "imagebuilderTemplate" = "AzureImageBuilderSIG",
    "userIdentity"         = "enabled"
  }
}
