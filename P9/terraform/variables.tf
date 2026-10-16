variable "kube_context" {
  description = "Contexto de kubectl del cluster kind (kind create cluster --name aroma-p9)."
  type        = string
  default     = "kind-aroma-p9"
}

variable "repo_gitops" {
  description = "Repositorio GitOps que lee la Application raiz aroma-root."
  type        = string
  default     = "https://github.com/lurdesss/aroma-gitops.git"
}

variable "permitir_llave_nueva" {
  description = <<-DESC
    false (por defecto): el bootstrap falla si no existe la copia cifrada
    de la llave de Sealed Secrets, porque sin ella los SealedSecrets del
    repo GitOps no se descifran. true solo para el primer despliegue de
    la historia del sistema, cuando todavia no hay llave que conservar.
  DESC
  type        = bool
  default     = false
}
