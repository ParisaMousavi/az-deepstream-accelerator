module "rg_name" {
  source             = "github.com/ParisaMousavi/az-naming//rg?ref=2022.10.07"
  prefix             = var.prefix
  name               = var.name
  stage              = var.stage
  assembly           = null
  location_shortname = var.location_shortname
}

module "resourcegroup" {
  # https://{PAT}@dev.azure.com/{organization}/{project}/_git/{repo-name}
  source   = "github.com/ParisaMousavi/az-resourcegroup?ref=2022.10.07"
  location = var.location
  name     = module.rg_name.result
  tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}

resource "azurerm_storage_account" "this" {
  name                     = "iotpm13001"
  resource_group_name         = module.resourcegroup.name
  location                    = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "this" {
  name                  = "examplecontainer"
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}


/*
az iot hub create --resource-group IoTEdgeResources --name {hub_name} --sku F1 --partition-count 2
*/
resource "azurerm_iothub" "this" {
  name                        = "iot-pm-13001"
  resource_group_name         = module.resourcegroup.name
  location                    = var.location
  event_hub_partition_count   = 2
  event_hub_retention_in_days = 1
  sku {
    name     = "F1" # B1, B2, B3, F1, S1, S2, and S3
    capacity = "1"
  }
  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = azurerm_storage_account.this.primary_blob_connection_string
    name                       = "export"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.this.name
    encoding                   = "Avro"
    file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }  
  tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}

module "vm_name" {
  source             = "github.com/ParisaMousavi/az-naming//vm?ref=main"
  prefix             = var.prefix
  name               = var.name
  stage              = var.stage
  assembly           = "win"
  location_shortname = var.location_shortname
}

/*
  Windows 11 machine
  This is for IoT Edge device
*/
resource "azurerm_public_ip" "this_win" {
  name                = "${module.vm_name.result}-pip"
  location            = module.resourcegroup.location
  resource_group_name = module.resourcegroup.name
  allocation_method   = "Static"
  tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}

resource "azurerm_network_interface" "this_win" {
  name                = "${module.vm_name.result}-nic"
  location            = module.resourcegroup.location
  resource_group_name = module.resourcegroup.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.network.outputs.subnets["vm-linux"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this_win.id
  }
}

resource "azurerm_network_interface_security_group_association" "this_win" {
  network_interface_id      = azurerm_network_interface.this_win.id
  network_security_group_id = data.terraform_remote_state.network.outputs.nsg_id
}

resource "azurerm_windows_virtual_machine" "this_win" {
  name                = "${var.name}-win"
  location            = module.resourcegroup.location
  resource_group_name = module.resourcegroup.name
  size                = "Standard_D4s_v4" #"Standard_B2s" #"Standard_F2"
  admin_username      = "adminuser"
  admin_password      = "P@$$w0rd1234!"
  network_interface_ids = [
    azurerm_network_interface.this_win.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # az vm image list --all --publisher MicrosoftWindowsDesktop --location westeurope --offer "windows11preview-arm64"
  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-22h2-pro"
    version   = "latest"
  }

}

resource "azurerm_managed_disk" "this_win" {
  name                 = "${module.vm_name.result}-disk1"
  location             = module.resourcegroup.location
  resource_group_name  = module.resourcegroup.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 30
}

resource "azurerm_virtual_machine_data_disk_attachment" "this_win" {
  managed_disk_id    = azurerm_managed_disk.this_win.id
  virtual_machine_id = azurerm_windows_virtual_machine.this_win.id
  lun                = "10"
  caching            = "ReadWrite"
}


# Steps to simulate IoT Edge on Azure VM

# Processor compatibility
# The VM Size is important because of nested virtualization
# https://learn.microsoft.com/en-us/azure/lab-services/concept-nested-virtualization-template-vm#processor-compatibility

# Enable nested virtualization by using a script
# https://learn.microsoft.com/en-us/azure/lab-services/how-to-enable-nested-virtualization-template-vm-using-script#enable-nested-virtualization-by-using-a-script

# Install and start the IoT Edge runtime
# https://learn.microsoft.com/en-us/azure/iot-edge/quickstart?view=iotedge-1.4#install-and-start-the-iot-edge-runtime

module "acr_name" {
  source             = "github.com/ParisaMousavi/az-naming//acr?ref=2022.10.07"
  prefix             = var.prefix
  name               = var.name
  stage              = var.stage
  location_shortname = var.location_shortname
}

module "acr" {
  # https://{PAT}@dev.azure.com/{organization}/{project}/_git/{repo-name}
  source                        = "github.com/ParisaMousavi/az-acr?ref=main"
  resource_group_name           = module.resourcegroup.name
  location                      = module.resourcegroup.location
  name                          = module.acr_name.result
  sku                           = "Premium"
  admin_enabled                 = "true"
  public_network_access_enabled = true # use case: for development
  network_rule_set = {
    allow_ip_ranges  = []
    allow_subnet_ids = []
  }
  private_endpoint_config = {}
  additional_tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}
