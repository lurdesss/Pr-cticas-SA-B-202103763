# StorageClass para los datos que se respaldan con Velero (PostgreSQL).
#
# Por que no la clase "standard" de kind: el provisionador local-path crea
# por defecto PV de tipo hostPath. El kubelet no monta un PV hostPath dentro
# de /var/lib/kubelet/pods/<pod>/volumes, que es donde el node-agent de
# Velero busca los volumenes para copiarlos con Kopia, asi que Velero los
# omite sin error: el backup sale "Completed" pero sin los datos (detectado
# en el Bloque 8a al revisar los PodVolumeBackups: solo aparecian los
# emptyDir). Con volumeType "local" el provisionador crea PV de tipo local,
# que el kubelet si monta en el directorio del pod y Velero si respalda.
resource "kubernetes_storage_class_v1" "aroma_local" {
  metadata {
    name = "aroma-local"
    labels = {
      "app.kubernetes.io/part-of" = "aroma"
    }
  }

  storage_provisioner = "rancher.io/local-path"
  reclaim_policy      = "Delete"
  # Espera a que el pod se programe para crear el volumen en ESE nodo
  # (con anti-afinidad, cada instancia de PostgreSQL en su worker).
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    volumeType = "local"
  }

  depends_on = [null_resource.cluster_kind]
}
