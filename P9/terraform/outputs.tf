output "namespaces_creados" {
  value = [for ns in kubernetes_namespace.ambiente : ns.metadata[0].name]
}
