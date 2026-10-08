# ============================================================================
# Bootstrap de dia cero (requisito 3.2): "Terraform provisiona el
# cluster e instala ArgoCD, y a partir de ahi el patron app-of-apps...
# levanta el resto del sistema. No se admite ningun paso manual
# intermedio." Este archivo es ese unico punto de entrada.
#
# Orden real: (1) kind create cluster -> (2) instalar ArgoCD via Helm
# -> (3) [capa siguiente] la Application "app-of-apps" que hace que
# ArgoCD despliegue TODO lo demas (Rollouts, Kyverno, Velero, Sealed
# Secrets, los microservicios) sin que nadie corra kubectl apply a mano.
# ============================================================================

# --------------------------------------------------------- 1. el cluster
# No existe un provider oficial de Terraform para "kind", asi que se
# orquesta invocando el propio CLI de kind desde Terraform (local-exec).
# Sigue siendo Terraform quien decide CUANDO y CON QUE ejecutarlo -- el
# unico comando que la estudiante corre a mano es "terraform apply".
#
# El script es idempotente: si el cluster "aroma-p9" ya existe (por
# ejemplo, en una segunda corrida), no lo vuelve a crear ni falla.
resource "null_resource" "cluster_kind" {
  triggers = {
    nombre_cluster = var.kube_context
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      $nombre = "aroma-p9"
      $existe = kind get clusters 2>$null | Select-String -Pattern "^$nombre$"
      if (-not $existe) {
        kind create cluster --name $nombre --wait 90s
      } else {
        Write-Host "El cluster '$nombre' ya existe, no se recrea."
      }
    EOT
  }

  # Destruir este recurso (terraform destroy) SI destruye el cluster --
  # es literalmente la prueba de recuperacion cronometrada de la
  # seccion 3.2: "destruccion y reconstruccion completa del entorno".
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-Command"]
    command     = "kind delete cluster --name aroma-p9"
  }
}

# ------------------------------------------------- 2. instalar ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.11"

  # Valores minimos: server sin autenticacion TLS estricta (cluster
  # local, se accede por port-forward, ver README) y con el modo de
  # aplicaciones necesario para el patron app-of-apps.
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  depends_on = [null_resource.cluster_kind]
}
