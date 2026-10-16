variable "kube_context" {
  description = "Contexto de kubectl a usar (el que crea 'kind create cluster --name aroma-p8')."
  type        = string
  default     = "kind-aroma-p8"
}

variable "ambientes" {
  description = <<-DESC
    Los dos ambientes que pide el enunciado ("basta con dos ambientes,
    y perfectamente pueden ser dos namespaces" -- respuesta del
    auxiliar). "staging" recibe cada version antes que nadie; "prod" es
    donde corre la demo de canary con Argo Rollouts.
  DESC
  type = map(object({
    cpu_solicitada    = string
    memoria_solicitada = string
    cpu_limite        = string
    memoria_limite    = string
    limite_cpu_pod    = string
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
      cpu_solicitada     = "2"
      memoria_solicitada = "3Gi"
      cpu_limite         = "4"
      memoria_limite     = "6Gi"
      limite_cpu_pod     = "500m"
      limite_memoria_pod = "512Mi"
    }
  }
}
