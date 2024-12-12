variable "location" {
  description = "The region where the Azure resources will be created"
  type        = string
  default     = "japaneast"
  validation {
    condition     = contains(["japaneast", "japanwest"], var.location)
    error_message = "The location must be either 'japaneast' or 'japanwest'."
  }
}

variable "resource_group_name" {
  description = "value of the resource group name"
  type        = string
}

variable "base_name" {
  description = "The base name for the resources"
  type        = string
  default     = "test"
}

variable "vnet_cidr" {
  description = "The CIDR block for the virtual network"
  type        = string
  default     = "10.100.0.0/24"
}

variable "vm_size" {
  description = "The size of the virtual machine"
  type        = string
  default     = "Standard_B2s"
  validation {
    condition     = contains(["Standard_B1s", "Standard_B2s", "Standard_B2ms"], var.vm_size)
    error_message = "The vm_size must be either 'Standard_B1s', 'Standard_B2s', or 'Standard_B2ms'."
  }
}

variable "vm_username" {
  description = "The username for the virtual machine"
  type        = string
}

variable "vm_password" {
  description = "The password for the virtual machine"
  type        = string
}

variable "vm_public_key" {
  description = "The public key for the virtual machine"
  type        = string
}

variable "mysql_admin_username" {
  description = "The username for the MySQL server"
  type        = string
  default     = "dbadmin"
}

variable "mysql_admin_password" {
  description = "The password for the MySQL server"
  type        = string
}

variable "mysql_sku_name" {
  description = "The SKU name for the MySQL server"
  type        = string
  default     = "B_Standard_B1ms"
  validation {
    condition     = contains(["B_Standard_B1ms", "B_Standard_B2ms", "B_Standard_B2s"], var.mysql_sku_name)
    error_message = "The mysql_sku_name must be either 'B_Standard_B1ms', 'B_Standard_B2ms', or 'B_Standard_B2s'."
  }
}

variable "mysql_database_size" {
  description = "The size of the MySQL database"
  type        = number
  default     = 20
}

variable "mysql_database_version" {
  description = "The version of the MySQL database"
  type        = string
  default     = "5.7"
  validation {
    condition     = contains(["5.7", "8.0.21"], var.mysql_database_version)
    error_message = "The mysql_database_version must be either '5.7' or '8.0.21'."
  }
}

locals {
  tags = {
    environment = "dev"
    project     = "test"
  }
  vnet_name  = "vnet-${var.base_name}"
  vm_name    = "vm01"
  subnet_vms = "snet-vms"
  subnet_db  = "snet-db"
  mysql_name = "mysql-${var.base_name}${random_id.random_number.dec}"
}

resource "random_id" "random_number" {
  byte_length = 3
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(local.tags, { "name" = var.resource_group_name })
}

resource "azurerm_virtual_network" "main" {
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.main.location
  name                = local.vnet_name
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(local.tags, { "name" = local.vnet_name })
}

resource "azurerm_subnet" "vms" {
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 0)]
  name                 = local.subnet_vms
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
}

resource "azurerm_subnet" "db" {
  address_prefixes = [cidrsubnet(var.vnet_cidr, 4, 1)]
  name             = local.subnet_db
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
}

resource "azurerm_network_security_group" "vm" {
  location            = azurerm_resource_group.main.location
  name                = "nsg-${local.vm_name}"
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(local.tags, { "name" = "nsg-${local.vm_name}" })
}

resource "azurerm_network_security_rule" "vm_ssh" {
  resource_group_name         = azurerm_resource_group.main.name
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "22"
  direction                   = "Inbound"
  name                        = "AllowSshInbound"
  network_security_group_name = azurerm_network_security_group.vm.name
  priority                    = 100
  protocol                    = "Tcp"
  source_address_prefix       = "*"
  source_port_range           = "*"
}

resource "azurerm_network_security_rule" "vm_http" {
  resource_group_name         = azurerm_resource_group.main.name
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "80"
  direction                   = "Inbound"
  name                        = "AllowHttpInbound"
  network_security_group_name = azurerm_network_security_group.vm.name
  priority                    = 110
  protocol                    = "Tcp"
  source_address_prefix       = "*"
  source_port_range           = "*"
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_public_ip" "main" {
  location            = azurerm_resource_group.main.location
  name                = "ip-${local.vm_name}"
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  allocation_method   = "Static"

  tags = merge(local.tags, { "name" = "ip-${local.vm_name}" })
}

resource "azurerm_network_interface" "main" {
  location            = azurerm_resource_group.main.location
  name                = "nic-${local.vm_name}"
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipcfg-${local.vm_name}"
    subnet_id                     = azurerm_subnet.vms.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }

  tags = merge(local.tags, { "name" = "nic-${local.vm_name}" })
}

resource "azurerm_virtual_machine" "main" {
  location            = azurerm_resource_group.main.location
  name                = local.vm_name
  resource_group_name = azurerm_resource_group.main.name
  vm_size             = var.vm_size
  zones               = ["1"]
  storage_image_reference {
    offer     = "0001-com-ubuntu-server-jammy"
    publisher = "Canonical"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  storage_os_disk {
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "StandardSSD_LRS"
    name              = "osdisk-${local.vm_name}"
    disk_size_gb      = 30
  }

  os_profile {
    computer_name  = local.vm_name
    admin_username = var.vm_username
    custom_data    = filebase64("${path.module}/cloud-init.yaml")
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.vm_username}/.ssh/authorized_keys"
      key_data = var.vm_public_key
    }
  }

  network_interface_ids = [
    azurerm_network_interface.main.id
  ]

  tags = merge(local.tags, { "name" = local.vm_name })
}

resource "azurerm_mysql_flexible_server" "main" {
  location               = azurerm_resource_group.main.location
  name                   = local.mysql_name
  resource_group_name    = azurerm_resource_group.main.name
  sku_name               = var.mysql_sku_name
  administrator_login    = var.mysql_admin_username
  administrator_password = var.mysql_admin_password
  version                = "8.0.21"
  zone                   = "1"
  storage {
    auto_grow_enabled = true
    size_gb           = var.mysql_database_size
  }
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  delegated_subnet_id          = azurerm_subnet.db.id
  private_dns_zone_id          = azurerm_private_dns_zone.main.id

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.main
  ]

  tags = merge(local.tags, { "name" = "mysql-${local.vm_name}" })
}

resource "azurerm_mysql_flexible_server_configuration" "secure_settings" {
  name                = "require_secure_transport"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "OFF"
}

resource "azurerm_private_dns_zone" "main" {
  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(local.tags, { "name" = "privatelink.mysql.database.azure.com" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  name                  = "vnet-link-${local.vnet_name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = azurerm_virtual_network.main.id
}
