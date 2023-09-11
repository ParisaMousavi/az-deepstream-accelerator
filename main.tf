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
  resource_group_name      = module.resourcegroup.name
  location                 = var.location
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
  tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}

resource "null_resource" "register_iot_device" {
  depends_on = [
    azurerm_iothub.this
  ]
  triggers = { always_run = timestamp() }
  provisioner "local-exec" {
    command     = "chmod +x ${path.module}/1-iot-device-identity/script.sh ;${path.module}/1-iot-device-identity/script.sh"
    interpreter = ["bash", "-c"]
    environment = {
      iothub_name        = "iot-pm-13001"
      iothub_device_name = "myEdgeDevice"
    }
  }
}



/*
 configure file upload for IoT Hub
 video: https://www.youtube.com/watch?v=RI-tQnLsPJ0&list=PL1ljc761XCiYVaDEfS4X-f493capyL-cL&index=1
 step: https://github.com/microsoft/AzureDeepStreamAccelerator/blob/main/documentation/quickstart-readme.md
 concept: https://learn.microsoft.com/en-us/azure/iot-hub/iot-hub-devguide-file-upload
 how-to: https://learn.microsoft.com/en-us/azure/iot-hub/iot-hub-configure-file-upload-cli

*/


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
    subnet_id                     = data.terraform_remote_state.network.outputs.subnets["vm-win"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this_win.id
  }
}

resource "azurerm_network_interface_security_group_association" "this_win" {
  network_interface_id      = azurerm_network_interface.this_win.id
  network_security_group_id = data.terraform_remote_state.network.outputs.nsg_id
}

locals {
  admin_password = "P@$$w0rd1234!"
  admin_username = "adminuser"
}
resource "azurerm_windows_virtual_machine" "this_win" {
  name                = "${var.name}-win"
  location            = module.resourcegroup.location
  resource_group_name = module.resourcegroup.name
  size                = "Standard_D4s_v4" #"Standard_B2s" #"Standard_F2"
  admin_username      = local.admin_username
  admin_password      = local.admin_password
  provision_vm_agent  = true
  timezone            = "Romance Standard Time"
  custom_data         = base64encode(file("${path.module}/0-files/winrm.ps1"))
  network_interface_ids = [
    azurerm_network_interface.this_win.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # winrm_listener {
  #   protocol = "http"
  # }

  # # Auto-Login's required to configure WinRM
  # additional_unattend_content {
  #   setting = "AutoLogon"
  #   content = "<AutoLogon><Password><Value>${local.admin_password}</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>${local.admin_username}</Username></AutoLogon>"
  # }

  # additional_unattend_content {
  #   setting = "FirstLogonCommands"
  #   content = file("${path.module}/0-files/FirstLogonCommands.xml")
  # }

  # az vm image list --all --publisher MicrosoftWindowsDesktop --location westeurope --offer "windows11preview-arm64"
  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-22h2-pro"
    version   = "latest"
  }

  # provisioner "remote-exec" {
  #   connection {
  #     host     = azurerm_public_ip.this_win.ip_address
  #     type     = "winrm"
  #     user     = local.admin_username
  #     password = local.admin_password
  #     port     = 5985
  #     https    = true
  #     timeout  = "5m"
  #   }
  #   inline = [
  #     "write-Host 'Enable nested virtualization by using a script' -NoNewline",
  #   ]
  # }

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
# Nvidia link: https://docs.nvidia.com/cuda/eflow-users-guide/index.html

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
