# RBAC de minimo privilegio para el proceso que despliega la aplicacion
# en cada ambiente (misma filosofia que el RBAC por microservicio de la
# Practica 5, aplicada ahora a nivel de ambiente completo). No se usa
# cluster-admin en ningun punto de este archivo.
#
# Nota de diseño (documentada, no oculta): ArgoCD instalado con su
# manifiesto oficial trae su propio ClusterRole/ClusterRoleBinding
# amplio para el "application-controller" (necesita poder gestionar
# recursos arbitrarios en cualquier namespace que una Application le
# pida). Este archivo NO reemplaza esa instalacion -- eso rompería
# ArgoCD. Lo que SI hace: (1) crea el ServiceAccount y el Role que
# representan el acceso minimo real que la aplicacion necesita, y (2)
# el control que efectivamente restringe a QUE namespaces puede
# desplegar ArgoCD es el campo "destinations" del AppProject (ver
# argocd/app-project.yaml, capa siguiente) -- son dos mecanismos
# complementarios, no uno solo, y aqui se documenta cual hace que cosa.
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
    resources  = ["services", "configmaps", "secrets", "pods", "pods/log"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
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
