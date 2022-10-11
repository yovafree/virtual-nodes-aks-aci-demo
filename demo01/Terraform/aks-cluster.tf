provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "default" {
  name     = "${var.rg}-rg"
  location = "westus"

  tags = {
    environment = "Demo AKS ACI"
  }
}

resource "azurerm_user_assigned_identity" "main" {
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location

  name = "identity-${var.rg}"
}

resource "azurerm_virtual_network" "aks_vnet" {
  name                = "${azurerm_resource_group.default.name}-vnet"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  address_space       = ["10.0.0.0/12"]
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "${azurerm_resource_group.default.name}-aks_subnet"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "aks_aci_subnet" {
  name                 = "${azurerm_resource_group.default.name}-aks_aci_subnet"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes       = ["10.2.0.0/16"]

  delegation {
    name = "aciDelegation"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_role_assignment" "network" {
  scope                = azurerm_resource_group.default.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_kubernetes_cluster" "default" {
  name                = "${var.rg}-aks"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  dns_prefix          = "${var.rg}-k8s"

  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    load_balancer_sku  = "Standard"
  }

  default_node_pool {
    name            = "default"
    node_count      = 2
    vm_size         = "Standard_D2_v2"
    os_disk_size_gb = 30
    vnet_subnet_id      = azurerm_subnet.aks_subnet.id
  }

  service_principal {
    client_id     = var.appId
    client_secret = var.password
  }

  role_based_access_control {
    enabled = true
  }

  addon_profile {
    aci_connector_linux {
      enabled     = true
      subnet_name = azurerm_subnet.aks_aci_subnet.name
    }
  }

  tags = {
    environment = "Demo AKS ACI"
  }

  depends_on = [
    azurerm_resource_group.default,
    azurerm_role_assignment.network
  ]
}

/*
data "azuread_service_principal" "aks-aci_identity" {
  display_name = "aciconnectorlinux-${azurerm_kubernetes_cluster.default.name}"
  depends_on   = [azurerm_kubernetes_cluster.default]
}

data "azurerm_user_assigned_identity" "aks-aci_identity" {
  name = "aciconnectorlinux-${azurerm_kubernetes_cluster.default.name}"
  resource_group_name = azurerm_kubernetes_cluster.default.node_resource_group
}

resource "azurerm_role_assignment" "vnet_permissions_aci" {
  principal_id         = data.azurerm_user_assigned_identity.aks-aci_identity.principal_id
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Contributor"
}*/