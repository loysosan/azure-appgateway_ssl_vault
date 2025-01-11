resource "azurerm_resource_group" "main" {
  name     = var.ag_vault_resource_group_name_rg
  location = var.location
}

resource "azurerm_dns_zone" "main" {
  name                = "azure.kurkumas.site"
  resource_group_name = azurerm_resource_group.main.name
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "example-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "example-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Public IP for VM
resource "azurerm_public_ip" "vm" {
  name                = "vm-public-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Basic"
}

# Network Interface with Public IP for VM
resource "azurerm_network_interface" "nic" {
  name                = "example-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "example-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "appgw-public-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Subnet for Application Gateway
resource "azurerm_subnet" "appgw_subnet" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"] # Отдельный адресный диапазон
}

resource "azurerm_user_assigned_identity" "platform_app_gateway_identity" {
  name                = "platform-app-gateway-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
}

# Application Gateway
resource "azurerm_application_gateway" "appgw" {
  name                = "example-appgw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw_subnet.id # Используем новую подсеть
  }

  frontend_port {
    name = "frontendPort"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "public-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = "vm-backend-pool"
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 20
  }

  ssl_certificate {
    name               = "PlatformLestEncrypt"
    key_vault_secret_id = "https://${var.key_vault_name}.vault.azure.net/secrets/TestLetsEncrypt"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.platform_app_gateway_identity.id]
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "public-ip"
    frontend_port_name             = "frontendPort"
    protocol                       = "Https"
    ssl_certificate_name           = "PlatformLestEncrypt"
  }

  request_routing_rule {
    name                       = "http-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "vm-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100 # Указываем приоритет
  }
}

data "azurerm_key_vault" "existing" {
  name                = "platform-vault-ssl"
  resource_group_name = "platform-ssl-certs"
}

resource "azurerm_key_vault_access_policy" "example" {
  key_vault_id = data.azurerm_key_vault.existing.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.platform_app_gateway_identity.principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# DNS A Record for Application Gateway
resource "azurerm_dns_a_record" "appgw" {
  name                = "appgw"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_public_ip.appgw.ip_address]
}

# DNS A Record for VM
resource "azurerm_dns_a_record" "vm" {
  name                = "vm"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_public_ip.vm.ip_address]
}

data "azurerm_client_config" "current" {}