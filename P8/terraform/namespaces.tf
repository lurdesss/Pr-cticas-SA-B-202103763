# Los dos ambientes. Nada de esto se crea a mano (requisito explicito:
# "No se acepta infraestructura creada manualmente").
resource "kubernetes_namespace" "ambiente" {
  for_each = var.ambientes

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/part-of" = "aroma"
      "practica"                  = "p8-gitops"
    }
  }
}
