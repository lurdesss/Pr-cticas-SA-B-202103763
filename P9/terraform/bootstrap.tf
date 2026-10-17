# ============================================================================
# Bootstrap de dia cero (requisito 3.2): "Terraform provisiona el
# cluster e instala ArgoCD, y a partir de ahi el patron app-of-apps...
# levanta el resto del sistema. No se admite ningun paso manual
# intermedio." Este archivo es ese unico punto de entrada.
#
# Orden obligatorio (cada paso depende del anterior via depends_on):
#   1. null_resource.cluster_kind          -> kind create cluster (3 nodos)
#   2. null_resource.llave_sealed_secrets  -> llave de Sealed Secrets en
#                                             kube-system, ANTES del controlador
#   3. helm_release.argocd                 -> ArgoCD
#   4. helm_release.aroma_root             -> Application raiz "aroma-root"
#                                             (app-of-apps sobre aroma-gitops/apps)
# Desde el paso 4, ArgoCD despliega el resto (Sealed Secrets, Velero,
# Rollouts, Kyverno, microservicios). El punto de entrada que encadena
# esto es P9/bootstrap.ps1.
# ============================================================================

# --------------------------------------------------------- 1. el cluster
# No existe un provider oficial de Terraform para "kind", asi que se
# orquesta invocando el propio CLI de kind desde Terraform (local-exec).
#
# El script es idempotente: si el cluster "aroma-p9" ya existe (por
# ejemplo, en una segunda corrida), no lo vuelve a crear ni falla.
#
# kind-config.yaml NO esta en los triggers a proposito: si un cambio de
# topologia reemplazara este recurso, Terraform borraria el cluster pero
# conservaria en el estado los namespaces y ArgoCD del cluster viejo. Un
# cambio de topologia se aplica reconstruyendo con P9/bootstrap.ps1.
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
        kind create cluster --name $nombre --config "${path.module}/kind-config.yaml" --wait 180s
        if ($LASTEXITCODE -ne 0) { exit 1 }
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

# ------------------------------- 2. restaurar la llave de Sealed Secrets
# Debe ir antes de ArgoCD: si el controlador de Sealed Secrets arranca
# sin llave, genera una nueva y los SealedSecrets de aroma-gitops (por
# ejemplo, las credenciales de MinIO que necesita Velero) quedan
# ilegibles. La fuente es la copia cifrada con DPAPI fuera del repo
# (P9/scripts/exportar-llave-sealed-secrets.ps1); el script la descifra
# en memoria, asi que la llave NO entra al estado de Terraform.
resource "null_resource" "llave_sealed_secrets" {
  triggers = {
    # Se vuelve a ejecutar cada vez que el cluster se crea de nuevo.
    cluster = null_resource.cluster_kind.id
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = "& '${path.module}/../scripts/restaurar-llave-sealed-secrets.ps1' -Contexto '${var.kube_context}'${var.permitir_llave_nueva ? " -PermitirLlaveNueva" : ""}; exit $LASTEXITCODE"
  }

  depends_on = [null_resource.cluster_kind]
}

# ------------------------------------------------- 3. instalar ArgoCD
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

  values = [yamlencode({
    configs = {
      cm = {
        # Rastreo por anotacion en vez de etiqueta. Con la etiqueta por
        # defecto (argocd.argoproj.io/instance), Velero copia las
        # etiquetas del Schedule a cada Backup que genera; ArgoCD veria
        # esos Backups como recursos sobrantes de "velero-schedules" y,
        # con prune activo, los borraria. Las anotaciones no se copian.
        "application.resourceTrackingMethod" = "annotation"

        # Desde ArgoCD 1.8 una Application hija no reporta salud a su
        # padre, asi que los sync-wave de apps/ solo ordenan el "apply"
        # sin esperar. Este chequeo (receta oficial de la documentacion
        # de ArgoCD para app-of-apps) hace que aroma-root espere a que
        # cada ola este Healthy: sealed-secrets -> secretos sellados ->
        # velero -> schedules.
        "resource.customizations.health.argoproj.io_Application" = <<-EOT
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil then
            if obj.status.health ~= nil then
              hs.status = obj.status.health.status
              if obj.status.health.message ~= nil then
                hs.message = obj.status.health.message
              end
            end
          end
          return hs
        EOT
      }
    }
  })]

  depends_on = [null_resource.llave_sealed_secrets]
}

# ------------------------------------ 4. Application raiz (app-of-apps)
# Se instala con el chart oficial argocd-apps y no con kubernetes_manifest:
# kubernetes_manifest consulta la API durante el "plan" para validar el
# CRD Application, y en un bootstrap desde cero ni el cluster ni el CRD
# existen todavia, asi que el plan fallaria.
resource "helm_release" "aroma_root" {
  name      = "aroma-root"
  namespace = "argocd"

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.6"

  values = [yamlencode({
    applications = {
      aroma-root = {
        namespace = "argocd"
        # Al borrar la raiz, ArgoCD borra en cascada sus hijas.
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = "default"
        source = {
          repoURL        = var.repo_gitops
          targetRevision = "main"
          path           = "apps"
          directory      = { recurse = true }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
          retry = {
            limit   = 10
            backoff = { duration = "10s", factor = 2, maxDuration = "3m" }
          }
        }
      }
    }
  })]

  # La StorageClass de los datos debe existir antes de que ArgoCD cree el
  # PostgreSQL (ola 2 de aroma-root).
  depends_on = [helm_release.argocd, kubernetes_storage_class_v1.aroma_local]
}
