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
    name                       = "AllowHTTP"
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
}

resource "azurerm_network_interface" "vault" {
  count               = 3
  name                = "${var.prefix}-vault-nic-${count.index}"
  location            = data.azurerm_resource_group.credifyai.location
  resource_group_name = data.azurerm_resource_group.credifyai.name

  ip_configuration {
    name                          = "vm"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vault.id
    public_ip_address_id          = azurerm_public_ip.vault[count.index].id
  }
}

resource "azurerm_managed_disk" "vault_disk" {
  count                  = 3
  name                   = "${var.prefix}-vault-disk-${count.index}"
  location               = data.azurerm_resource_group.credifyai.location
  resource_group_name    = data.azurerm_resource_group.credifyai.name
  storage_account_type   = "Standard_LRS"
  create_option          = "Empty"
  disk_size_gb           = 20
  disk_encryption_set_id = azurerm_disk_encryption_set.vault.id
}

resource "azurerm_virtual_machine" "vault" {
  count                 = 3
  name                  = "${var.prefix}-vault-vm-${count.index}"
  resource_group_name   = data.azurerm_resource_group.credifyai.name
  location              = data.azurerm_resource_group.credifyai.location
  network_interface_ids = [azurerm_network_interface.vault[count.index].id]
  vm_size               = "Standard_DS1_v2"
  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  storage_os_disk {
    name              = "vm-${count.index}-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "vault-${count.index}"
    admin_username = var.admin_username
    custom_data    = filebase64("${path.module}/cloud-init.sh")
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = tls_private_key.ssh_key.public_key_openssh
    }
  }

  tags = {
    service = "vault"
  }
}

resource "azurerm_network_interface_security_group_association" "vault" {
  count                     = 3
  network_interface_id      = azurerm_network_interface.vault[count.index].id
  network_security_group_id = azurerm_network_security_group.vault.id
}

resource "azurerm_virtual_machine_data_disk_attachment" "vault" {
  count              = 3
  managed_disk_id    = azurerm_managed_disk.vault_disk[count.index].id
  virtual_machine_id = azurerm_virtual_machine.vault[count.index].id
  lun                = "10"
  caching            = "ReadWrite"
}

resource "azurerm_public_ip" "vaultlb" {
  name                = "PublicIPForLB"
  location            = data.azurerm_resource_group.credifyai.location
  resource_group_name = data.azurerm_resource_group.credifyai.name
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "vault" {
  count               = 3
  name                = "${var.prefix}-vault-public-ip-${count.index}"
  location            = data.azurerm_resource_group.credifyai.location
  resource_group_name = data.azurerm_resource_group.credifyai.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "vault" {
  name                = "${var.prefix}-vault-lb"
  location            = data.azurerm_resource_group.credifyai.location
  resource_group_name = data.azurerm_resource_group.credifyai.name

  frontend_ip_configuration {
    name                 = "vaultFrontend"
    public_ip_address_id = azurerm_public_ip.vaultlb.id
  }
}

resource "azurerm_lb_backend_address_pool" "vault" {
  loadbalancer_id = azurerm_lb.vault.id
  name            = "BackEndAddressPool"
}

resource "azurerm_network_interface_backend_address_pool_association" "vault" {
  count                   = 3
  network_interface_id    = azurerm_network_interface.vault[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.vault.id
}

resource "azurerm_lb_probe" "vault_probe" {
  loadbalancer_id     = azurerm_lb.vault.id
  name                = "vaultProbe"
  protocol            = "Http"
  port                = 8200
  request_path        = "/v1/sys/health"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "vault_rule" {
  loadbalancer_id                = azurerm_lb.vault.id
  name                           = "vaultRule"
  protocol                       = "Tcp"
  frontend_port                  = 8200
  backend_port                   = 8200
  frontend_ip_configuration_name = azurerm_lb.vault.frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.vault.id]
  probe_id                       = azurerm_lb_probe.vault_probe.id
}

output "vault_lb_ip" {
  value = azurerm_lb.vault.frontend_ip_configuration[0].private_ip_address
}
