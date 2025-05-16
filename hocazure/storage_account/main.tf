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
#tạo resource để khai báo cho những resource service khác trong code
resource "azurerm_resource_group" "qthn" {
  location = "Southeast Asia"
  name     = "qthn"
}

#resource lấy grp and name of resource tạo bên trên
#storage_account chứa tất cả container, blob
resource "azurerm_storage_account" "sa-qthn" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.qthn.name
  location                 = azurerm_resource_group.qthn.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

variable "storage_account_name" {
  type        = string
  description = "Tên của storage account"
}

#create container inside storage_account
#container chứa tất cả blob
#private : chỉ có tài khoản storage mới có thể truy cập or ngưởi có quyền xác thực
#blob : tất cả mọi người đều có thể truy cập
#container: công khai- cho toàn bộ truy cập
resource "azurerm_storage_container" "data-qthn" {
  name = "container-qthn"
  storage_account_id = azurerm_storage_account.sa-qthn.id
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