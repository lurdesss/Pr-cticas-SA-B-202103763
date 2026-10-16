terraform {
  required_version = ">= 1.7.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

# El proveedor lee tu kubeconfig LOCAL (el de tu kind), nunca un secreto
# de GitHub Actions -- Terraform lo corre la propia estudiante desde su
# maquina, contra su cluster local, como cualquier IaC "de verdad": el
# pipeline de CI/CD (P8/.github, ver mas abajo) nunca invoca terraform
# apply ni tiene ninguna credencial de cluster (requisito explicito del
# enunciado: "prohibicion de despliegue directo").
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}
