data "azurerm_resource_group" "credifyai" {
  name = "credifyai-resources"
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_private_key" {
  filename        = "/Users/admin/Downloads/ssh-key.pem"
  content         = tls_private_key.ssh_key.private_key_pem
  file_permission = "0600"
}

resource "azurerm_virtual_network" "vault" {
  name                = "${var.prefix}-vault-network"
  address_space       = ["10.1.0.0/16"]
  location            = data.azurerm_resource_group.credifyai.location
  resource_group_name = data.azurerm_resource_group.credifyai.name
}

resource "azurerm_subnet" "vault" {
  name                 = "${var.prefix}-vault-subnet"
  resource_group_name  = data.azurerm_resource_group.credifyai.name
  virtual_network_name = azurerm_virtual_network.vault.name
  address_prefixes     = ["10.1.0.0/24"]
}

resource "azurerm_network_security_group" "vault" {
  name                = "${var.prefix}-vault-sg"
  location            = data.azurerm_resource_group.credifyai.location
  resource_group_name = data.azurerm_resource_group.credifyai.name

  security_rule {
    name                       = "AllowVault"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8200"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "vault" {
  name                = "${var.prefix}-vault-nic"
  location            = data.azurerm_resource_group.credifyai.location
  resource_group_name = data.azurerm_resource_group.credifyai.name

  ip_configuration {
    name                          = "vm"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vault.id
    public_ip_address_id          = data.azurerm_public_ip.vault.id
  }
}

resource "azurerm_managed_disk" "vault_disk" {
  name                   = "${var.prefix}-vault-disk"
  location               = data.azurerm_resource_group.credifyai.location
  resource_group_name    = data.azurerm_resource_group.credifyai.name
  storage_account_type   = "Standard_LRS"
  create_option          = "Empty"
  disk_size_gb           = 20
  disk_encryption_set_id = azurerm_disk_encryption_set.vault.id
}

resource "azurerm_linux_virtual_machine" "vault" {
  name                  = "${var.prefix}-vault-vm"
  resource_group_name   = data.azurerm_resource_group.credifyai.name
  location              = data.azurerm_resource_group.credifyai.location
  network_interface_ids = [azurerm_network_interface.vault.id]
  size                  = "Standard_DS1_v2"
  admin_username        = var.admin_username
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  os_disk {
    caching                = "ReadWrite"
    storage_account_type   = "Standard_LRS"
    disk_encryption_set_id = azurerm_disk_encryption_set.vault.id
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  custom_data = filebase64("${path.module}/cloud-init.sh")

  tags = {
    service = "vault"
  }
}


resource "azurerm_network_interface_security_group_association" "vault" {
  network_interface_id      = azurerm_network_interface.vault.id
  network_security_group_id = azurerm_network_security_group.vault.id
}


data "azurerm_public_ip" "vault" {
  name                = "${var.prefix}-vault-ip"
  resource_group_name = data.azurerm_resource_group.credifyai.name
}
