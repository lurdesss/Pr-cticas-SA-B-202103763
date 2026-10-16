terraform {
  required_version = ">= 1.15.0"

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "VerdictCorp"

    workspaces {
      name = "aroma-p9-infra"
    }
  }

  # HCP Terraform provides state locking for this remote workspace.
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# El proveedor de Kubernetes apunta al kind local -- el ESTADO vive en
# HCP Terraform (con bloqueo incluido, requisito 3.2 del enunciado:
# "el estado debe residir en un backend remoto con bloqueo"), pero los
# RECURSOS que Terraform administra siguen siendo tu cluster local.
# Nunca se sube ningun kubeconfig ni credencial de cluster a HCP: el
# proveedor lee el archivo local de tu maquina en cada "terraform apply"
# que TU ejecutas, HCP solo guarda el resultado (el estado).
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}
