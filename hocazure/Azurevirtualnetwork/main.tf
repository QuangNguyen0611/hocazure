terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.27.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.2"
    }
  }
}


provider "azurerm" {
  # Configuration options
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

}

resource "azurerm_resource_group" "qthn" {
  location = "Southeast Asia"
  name     = "qthn"
}

resource "tls_private_key" "linux_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "linuxkey" {
  filename = "linuxkey.pem"
  content  = tls_private_key.linux_key.private_key_pem
}

data "azurerm_client_config" "current" {}


resource "azurerm_virtual_network" "qthn-network" {
  name                = "qthn-network"
  location            = azurerm_resource_group.qthn.location
  resource_group_name = azurerm_resource_group.qthn.name
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "subnetA" {
  name                 = "subnetA"
  resource_group_name  = azurerm_resource_group.qthn.name
  virtual_network_name = azurerm_virtual_network.qthn-network.name
  address_prefixes     = ["10.10.10.0/24"]
  depends_on = [
    azurerm_virtual_network.qthn-network
  ]
}
resource "azurerm_network_interface" "qthn_interface" {
  name                = "qthn-nic"
  location            = azurerm_resource_group.qthn.location
  resource_group_name = azurerm_resource_group.qthn.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnetA.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.qthn_public_ip.id
  }
  depends_on = [
    azurerm_virtual_network.qthn-network,
    azurerm_public_ip.qthn_public_ip,
    azurerm_subnet.subnetA
  ]
}

resource "azurerm_windows_virtual_machine" "qthn-machine" {
  name                = "qthn-machine"
  resource_group_name = azurerm_resource_group.qthn.name
  location            = azurerm_resource_group.qthn.location
  availability_set_id = azurerm_availability_set.qthn_set.id
  size                = "Standard_F2"
  admin_username      = var.admin_username
  #azurerm_key_vault_secret.vmpassword.value là cách Terraform truy cập giá trị của một bí mật (secret) được lưu trong Azure Key Vault.
  #Đây là một cách bảo mật hơn để quản lý thông tin nhạy cảm như mật khẩu, vì:
  #Không cần lưu mật khẩu trong mã nguồn.
  #Có thể kiểm soát truy cập thông qua Azure RBAC hoặc chính sách Key Vault.
  admin_password = azurerm_key_vault_secret.vmpassword.value
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
    azurerm_network_interface.qthn_interface,
    azurerm_availability_set.qthn_set,
    azurerm_key_vault_secret.vmpassword
  ]
}

resource "azurerm_public_ip" "qthn_public_ip" {
  name                = "qthn_public_ip"
  resource_group_name = azurerm_resource_group.qthn.name
  location            = azurerm_resource_group.qthn.location
  allocation_method   = "Static"
}

resource "azurerm_managed_disk" "qthn_disk" {
  name                 = "qthn_disk"
  location             = azurerm_resource_group.qthn.location
  resource_group_name  = azurerm_resource_group.qthn.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 16
}

resource "azurerm_virtual_machine_data_disk_attachment" "disk_attach" {
  managed_disk_id    = azurerm_managed_disk.qthn_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.qthn-machine.id
  lun                = "10"
  caching            = "ReadWrite"
  depends_on = [
    azurerm_windows_virtual_machine.qthn-machine
  ]
}

resource "azurerm_availability_set" "qthn_set" {
  name                        = "qthn_set"
  location                    = azurerm_resource_group.qthn.location
  resource_group_name         = azurerm_resource_group.qthn.name
  platform_fault_domain_count = 2
}

resource "azurerm_storage_account" "sa-qthn" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.qthn.name
  location                 = azurerm_resource_group.qthn.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

#create container inside storage_account
#container chứa tất cả blob
#private : chỉ có tài khoản storage mới có thể truy cập or ngưởi có quyền xác thực
#blob : tất cả mọi người đều có thể truy cập
#container: công khai- cho toàn bộ truy cập
resource "azurerm_storage_container" "data-qthn" {
  name                  = "container-qthn"
  storage_account_id    = azurerm_storage_account.sa-qthn.id
  container_access_type = "blob"
  depends_on = [
    azurerm_storage_account.sa-qthn
  ]
}

#create storage_blob chứa dữ liệu từ container
#Block blobs: lưu trữ dữ liệu dạng text và dữ liệu nhị phân.
#Append blobs: lý tưởng cho việc ghi dữ liệu từ máy ảo
#Page blobs: lưu trữ các tệp truy cập ngẫu nhiên có kích thước lên đến 8 TB
resource "azurerm_storage_blob" "blob-qthn" {
  name                   = "thisisanexample.txt"
  storage_account_name   = var.storage_account_name
  storage_container_name = azurerm_storage_container.data-qthn.name
  type                   = "Block"
  source                 = "thisisanexample.txt"
  depends_on = [
    azurerm_storage_container.data-qthn
  ]
}

resource "azurerm_storage_blob" "IIS_config" {
  name                   = "IIS_config.ps1"
  storage_account_name   = azurerm_storage_account.sa-qthn.name
  storage_container_name = azurerm_storage_container.data-qthn.name
  type                   = "Block"
  source                 = "IIS_config.ps1"
  depends_on             = [azurerm_storage_container.data-qthn]
}

resource "azurerm_virtual_machine_extension" "vm_extension" {
  name                 = "qthn-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.qthn-machine.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    fileUris = [
      "https://${azurerm_storage_account.sa-qthn.name}.blob.core.windows.net/container-qthn/IIS_config.ps1"
    ]
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -File IIS_config.ps1"
  })

  depends_on = [
    azurerm_storage_blob.IIS_config
  ]
}

resource "azurerm_network_security_group" "qthn-security-group" {
  name                = "qthn-security-group"
  location            = azurerm_resource_group.qthn.location
  resource_group_name = azurerm_resource_group.qthn.name

  security_rule {
    name                       = "allow_http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow_rdp"
    direction                  = "Inbound"
    priority                   = 101
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
#Khi bạn tạo một Network Security Group (NSG), nó chỉ là một tập hợp các rule. Để các rule này có hiệu lực, bạn phải gắn NSG vào một đối tượng mạng, cụ thể là:
#1.Subnet
#2.Network Interface (NIC)
#Nếu bạn không gắn NSG vào đâu cả, thì các rule trong đó không có tác dụng.
#Kích hoạt NSG cho subnet.
#Áp dụng các rule bảo mật (như mở cổng 80 cho HTTP) cho toàn bộ subnet.
#Đảm bảo an toàn mạng cho các tài nguyên trong subnet đó.
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  network_security_group_id = azurerm_network_security_group.qthn-security-group.id
  subnet_id                 = azurerm_subnet.subnetA.id
}

resource "azurerm_key_vault" "qthn-vault" {
  name                        = var.keyvault
  location                    = azurerm_resource_group.qthn.location
  resource_group_name         = azurerm_resource_group.qthn.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
  depends_on = [
    azurerm_resource_group.qthn
  ]
}

resource "azurerm_key_vault_secret" "vmpassword" {
  key_vault_id = azurerm_key_vault.qthn-vault.id
  name         = "vmpassword"
  value        = "Passwd@1990"
}


resource "azurerm_linux_virtual_machine" "qthn-linux" {
  name                = "linux-machine"
  resource_group_name = azurerm_resource_group.qthn.name
  location            = azurerm_resource_group.qthn.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  #admin_password                  = var.admin_password
  #disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.qthn_interface.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.linux_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  depends_on = [
    azurerm_network_interface.qthn_interface,
    tls_private_key.linux_key
  ]
}
