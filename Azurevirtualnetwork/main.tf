terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.27.0"
    }
  }
}


provider "azurerm" {
  # Configuration options
  features {}
  subscription_id = "1aa30304-f3cf-446b-848a-f0c77bf1d964"
}

resource "azurerm_resource_group" "qthn" {
  location = "Southeast Asia"
  name     = "qthn"
}

data "azurerm_subnet" "subnetA" {
  name                 = "backend"
  virtual_network_name = "production"
  resource_group_name  = "networking"
}

output "subnet_id" {
  value = data.azurerm_subnet.subnetA.id
}

resource "azurerm_virtual_network" "qthn-network" {
  name                = "qthn-network"
  location            = azurerm_resource_group.qthn.location
  resource_group_name = azurerm_resource_group.qthn.name
  address_space = ["10.10.10.0/16"]

  subnet {
    name = "subnetA"
    address_prefixes = ["10.10.10.0/24"]
  }
}

resource "azurerm_network_interface" "qthn_interface" {
  name                = "qthn-nic"
  location            = azurerm_resource_group.qthn.location
  resource_group_name = azurerm_resource_group.qthn.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.subnetA.id
    private_ip_address_allocation = "Dynamic"
  }
  depends_on = [
    azurerm_virtual_network.qthn-network
  ]
}

resource "azurerm_windows_virtual_machine" "qthn-machine" {
  name                = "qthn-machine"
  resource_group_name = azurerm_resource_group.qthn.name
  location            = azurerm_resource_group.qthn.location
  size                = "Standard_F2"
  admin_username      = "quangd"
  admin_password      = "Passwd@1991"
  network_interface_ids = [
    azurerm_network_interface.qthn_interface.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
  azurerm_network_interface.qthn_interface
  ]
}