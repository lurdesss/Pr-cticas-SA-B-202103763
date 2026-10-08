# Nada de esto se crea a mano ("No se acepta infraestructura creada
# manualmente"). Cubre lo que en P8 correspondia a "namespaces, cuotas
# de recursos, limites y RBAC del cluster definidos y aplicados con
# Terraform" -- construido aqui porque P8 nunca se entrego por
# separado (ver README, seccion "Alcance combinado con la Practica 8").
resource "kubernetes_namespace" "ambiente" {
  for_each = var.ambientes

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/part-of" = "aroma"
      "practica"                  = "p9-dr"
    }
  }
}

resource "kubernetes_resource_quota" "cuota" {
  for_each = var.ambientes

  metadata {
    name      = "cuota-${each.key}"
    namespace = kubernetes_namespace.ambiente[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = each.value.cpu_solicitada
      "requests.memory" = each.value.memoria_solicitada
      "limits.cpu"      = each.value.cpu_limite
      "limits.memory"   = each.value.memoria_limite
    }
  }
}

resource "kubernetes_limit_range" "limites" {
  for_each = var.ambientes

  metadata {
    name      = "limites-${each.key}"
    namespace = kubernetes_namespace.ambiente[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = each.value.limite_cpu_pod
        memory = each.value.limite_memoria_pod
      }
      default_request = {
        cpu    = "50m"
        memory = "64Mi"
      }
    }
  }
}
