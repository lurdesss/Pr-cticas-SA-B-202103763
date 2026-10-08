variable "ambientes" {
  description = <<-DESC
    Los dos ambientes del sistema (decision confirmada: "dos
    namespaces" es suficiente). "staging" recibe cada version antes
    que nadie; "prod" es donde corre la demo de canary de Argo
    Rollouts y, en esta practica, tambien la demo de recuperacion ante
    desastres (destruccion/reconstruccion, restauracion de datos,
    perdida de nodo).
  DESC
  type = map(object({
    cpu_solicitada      = string
    memoria_solicitada  = string
    cpu_limite          = string
    memoria_limite      = string
    limite_cpu_pod      = string
    limite_memoria_pod  = string
  }))
  default = {
    aroma-staging = {
      cpu_solicitada     = "2"
      memoria_solicitada = "3Gi"
      cpu_limite         = "4"
      memoria_limite     = "6Gi"
      limite_cpu_pod     = "500m"
      limite_memoria_pod = "512Mi"
    }
    aroma-prod = {
      cpu_solicitada     = "3"
      memoria_solicitada = "4Gi"
      cpu_limite         = "6"
      memoria_limite     = "8Gi"
      limite_cpu_pod     = "500m"
      limite_memoria_pod = "512Mi"
    }
  }
}
