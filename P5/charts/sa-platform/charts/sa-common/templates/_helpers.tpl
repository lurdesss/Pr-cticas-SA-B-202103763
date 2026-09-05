{{/*
Nombre completo del recurso: <release>-<chart>, truncado a 63 caracteres
porque varios objetos de Kubernetes (Service, entre otros) usan ese
nombre como etiqueta DNS. Es el primero de los "al menos dos named
templates" que pide la practica.
*/}}
{{- define "sa-common.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Etiquetas estandar de Helm/Kubernetes. Se aplican a TODOS los objetos de
TODOS los subcharts, asi que un "kubectl get all -l app.kubernetes.io/part-of=aroma"
en el namespace sa-p5 devuelve el sistema completo sin importar de que
subchart venga cada recurso.
*/}}
{{- define "sa-common.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | default .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: aroma
{{- end -}}

{{/*
Subconjunto minimo de etiquetas usado en selector de Service/Deployment.
Separado de sa-common.labels a proposito: el selector de un Deployment es
INMUTABLE una vez creado, mientras que las labels completas (con la
version) cambian en cada release. Si un upgrade cambiara el selector,
Kubernetes lo rechaza.
*/}}
{{- define "sa-common.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Referencia de imagen: repository:tag, con el tag resuelto por prioridad
(el explicito en values, si no el appVersion del chart, si no "latest").
Usa "default" para eso y "required" para exigir el repositorio: sin
repositorio no hay imagen que correr, y es mejor que el fallo aparezca en
"helm template" y no como un ImagePullBackOff media hora despues.
*/}}
{{- define "sa-common.image" -}}
{{- $repo := required (printf "Falta image.repository para %s" .Chart.Name) .Values.image.repository -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}

{{/*
securityContext a nivel de POD: aqui vive runAsNonRoot y el UID/GID fijo.
Compartido por los cinco subcharts para que ninguno "se olvide" de un
campo exigido por la rubrica.
*/}}
{{- define "sa-common.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
securityContext a nivel de CONTENEDOR: el sistema de archivos raiz de
solo lectura y sin escalado de privilegios. Se combina con el volumen
emptyDir montado en /tmp que cada Deployment declara, porque un proceso
Node o Python necesita poder escribir en /tmp aunque el resto de la
imagen sea inmutable.
*/}}
{{- define "sa-common.containerSecurityContext" -}}
runAsNonRoot: true
readOnlyRootFilesystem: true
allowPrivilegeEscalation: false
capabilities:
  drop: ["ALL"]
{{- end -}}

{{/*
Anotacion con el checksum del ConfigMap. Se calcula sobre el contenido
YA renderizado del propio ConfigMap del subchart que la use, y se coloca
en el Deployment. Cuando el ConfigMap cambia, el checksum cambia, la
anotacion del pod cambia, y Kubernetes reinicia el pod aunque la imagen
sea la misma: es como "helm upgrade" logra que un cambio de configuracion
se propague sin que el pod se entere de que existe un ConfigMap.
*/}}
{{- define "sa-common.checksumConfigAnnotation" -}}
checksum/config: {{ include (print .Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end -}}
