# Cuota de recursos por namespace: sin esto, un Rollout con un paso de
# promocion mal calculado podria consumir todo el cluster local.
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

# Limite por defecto para cada contenedor que NO declare su propio
# limite explicito -- red de seguridad adicional a la cuota del
# namespace completo, y ademas es justo lo que despues verifica la
# politica de Kyverno "exigir limites de CPU y memoria" (kyverno-policies/).
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
