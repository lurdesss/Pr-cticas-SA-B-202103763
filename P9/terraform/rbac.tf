# RBAC de minimo privilegio por ambiente (misma filosofia que P5/P8).
# ArgoCD trae su propio ClusterRole amplio via su manifiesto oficial
# de instalacion (necesario para que funcione); lo que este archivo
# aporta es el ServiceAccount+Role que representa el acceso minimo
# real de la aplicacion, documentado igual que en P8.
resource "kubernetes_service_account" "desplegador" {
  for_each = var.ambientes

  metadata {
    name      = "aroma-desplegador"
    namespace = kubernetes_namespace.ambiente[each.key].metadata[0].name
  }
}

resource "kubernetes_role" "desplegador" {
  for_each = var.ambientes

  metadata {
    name      = "aroma-desplegador"
    namespace = kubernetes_namespace.ambiente[each.key].metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "secrets", "pods", "pods/log", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["rollouts", "rollouts/status", "analysisruns", "analysistemplates"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding" "desplegador" {
  for_each = var.ambientes

  metadata {
    name      = "aroma-desplegador"
    namespace = kubernetes_namespace.ambiente[each.key].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.desplegador[each.key].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.desplegador[each.key].metadata[0].name
    namespace = kubernetes_namespace.ambiente[each.key].metadata[0].name
  }
}
