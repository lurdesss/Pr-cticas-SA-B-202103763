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
    cpu_solicitada     = string
    memoria_solicitada = string
    cpu_limite         = string
    memoria_limite     = string
    limite_cpu_pod     = string
    limite_memoria_pod = string
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
      # 10 (antes 6): en el ensayo de restauracion (Bloque 8b) la suma de
      # LIMITES llego a 5800m al reiniciar servicios (cada Deployment
      # levanta un pod extra con maxSurge 1 mientras el viejo sigue vivo) y
      # la cuota rechazo pods nuevos. Es la suma de techos, no consumo
      # real: las requests (lo reservado) siguen en 3 y el nodo tiene 12 CPU.
      cpu_limite         = "10"
      memoria_limite     = "8Gi"
      limite_cpu_pod     = "500m"
      limite_memoria_pod = "512Mi"
    }
  }
}
