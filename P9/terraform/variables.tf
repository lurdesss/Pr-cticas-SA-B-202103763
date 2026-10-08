variable "kube_context" {
  description = "Contexto de kubectl del cluster kind (kind create cluster --name aroma-p9)."
  type        = string
  default     = "kind-aroma-p9"
}
