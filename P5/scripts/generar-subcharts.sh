#!/usr/bin/env bash
# Genera los subcharts catalogo / inventario / resenas: son estructuralmente
# identicos y solo cambian puerto, base de datos y esquema de conexion.
# No es parte del despliegue; documenta como se generaron esos subcharts.
set -euo pipefail

BASE="charts/sa-platform/charts"

generar_uno() {
  local nombre="$1" descripcion="$2" puerto="$3" repo_imagen="$4" \
        db_nombre="$5" db_esquema="$6" \
        cpu_req="$7" mem_req="$8" cpu_lim="$9" mem_lim="${10}"

  local carpeta="$BASE/$nombre"
  local t="$carpeta/templates"
  mkdir -p "$t"

  cat > "$carpeta/Chart.yaml" <<EOF
apiVersion: v2
name: $nombre
description: $descripcion
type: application
version: 0.1.0
appVersion: "1.0.0"
dependencies:
  - name: sa-common
    version: "0.1.0"
    repository: "file://../sa-common"
EOF

  cat > "$carpeta/values.yaml" <<EOF
image:
  repository: $repo_imagen
  tag: ""
  pullPolicy: IfNotPresent

replicaCount: 2

servicio:
  puerto: $puerto

db:
  nombre: $db_nombre
  esquemaUrl: $db_esquema

recursos:
  requests: { cpu: $cpu_req, memory: $mem_req }
  limits:   { cpu: $cpu_lim, memory: $mem_lim }

registro:
  nivel: info

hpa:
  habilitado: true
  minReplicas: 2
  maxReplicas: 5
  cpuObjetivoPorcentaje: 70

pdb:
  minDisponibles: 1

sondas:
  arranque:   { rutaHttp: /salud, delayInicialSeg: 0, periodoSeg: 3, fallosPermitidos: 20 }
  vida:       { rutaHttp: /salud, delayInicialSeg: 0, periodoSeg: 10, timeoutSeg: 3, fallosPermitidos: 3 }
  disponible: { rutaHttp: /salud, delayInicialSeg: 0, periodoSeg: 5,  timeoutSeg: 2, fallosPermitidos: 2 }
EOF

  cat > "$t/serviceaccount.yaml" <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
EOF

  cat > "$t/role.yaml" <<'EOF'
# RBAC de minimo privilegio: el proceso no llama a la API de Kubernetes,
# pero la practica exige un ServiceAccount dedicado con Role y RoleBinding
# propios (nunca el ServiceAccount default). Se concede solo lectura de
# SU propio ConfigMap y Secret, acotada por nombre.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    resourceNames: ["{{ include "sa-common.fullname" . }}"]
    verbs: ["get", "list", "watch"]
EOF

  cat > "$t/rolebinding.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "sa-common.fullname" . }}
subjects:
  - kind: ServiceAccount
    name: {{ include "sa-common.fullname" . }}
    namespace: {{ .Release.Namespace }}
EOF

  cat > "$t/configmap.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
data:
  PUERTO: {{ .Values.servicio.puerto | quote }}
  NIVEL_LOG: {{ .Values.registro.nivel | default "info" | quote }}
EOF

  cat > "$t/secret.yaml" <<'EOF'
# Credenciales de base de datos. Nunca se escriben en el repositorio: el
# valor real llega en el momento de "helm install/upgrade" a traves de
# --values (values-dev.yaml / values-prod.yaml), nunca commiteado.
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
type: Opaque
stringData:
  DATABASE_URL: "{{ .Values.db.esquemaUrl }}://{{ required "Falta global.db.username" .Values.global.db.username }}:{{ required "Falta global.db.password" .Values.global.db.password }}@{{ .Values.global.db.host }}:{{ .Values.global.db.port }}/{{ .Values.db.nombre }}"
EOF

  cat > "$t/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels: {{ include "sa-common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels: {{ include "sa-common.labels" . | nindent 8 }}
      annotations:
        {{ include "sa-common.checksumConfigAnnotation" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "sa-common.fullname" . }}
      securityContext: {{ include "sa-common.podSecurityContext" . | nindent 8 }}
      containers:
        - name: $nombre
          image: {{ include "sa-common.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          securityContext: {{ include "sa-common.containerSecurityContext" . | nindent 12 }}
          ports:
            - name: http
              containerPort: {{ .Values.servicio.puerto }}
          envFrom:
            - configMapRef:
                name: {{ include "sa-common.fullname" . }}
            - secretRef:
                name: {{ include "sa-common.fullname" . }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
          resources: {{ .Values.recursos | toYaml | nindent 12 }}
          startupProbe:
            httpGet: { path: {{ .Values.sondas.arranque.rutaHttp }}, port: http }
            initialDelaySeconds: {{ .Values.sondas.arranque.delayInicialSeg }}
            periodSeconds: {{ .Values.sondas.arranque.periodoSeg }}
            failureThreshold: {{ .Values.sondas.arranque.fallosPermitidos }}
          livenessProbe:
            httpGet: { path: {{ .Values.sondas.vida.rutaHttp }}, port: http }
            periodSeconds: {{ .Values.sondas.vida.periodoSeg }}
            timeoutSeconds: {{ .Values.sondas.vida.timeoutSeg }}
            failureThreshold: {{ .Values.sondas.vida.fallosPermitidos }}
          readinessProbe:
            httpGet: { path: {{ .Values.sondas.disponible.rutaHttp }}, port: http }
            periodSeconds: {{ .Values.sondas.disponible.periodoSeg }}
            timeoutSeconds: {{ .Values.sondas.disponible.timeoutSeg }}
            failureThreshold: {{ .Values.sondas.disponible.fallosPermitidos }}
      volumes:
        - name: tmp
          emptyDir: {}
EOF

  cat > "$t/service.yaml" <<'EOF'
# ClusterIP: alcanzable solo dentro del cluster. La NetworkPolicy del
# chart padre es la que decide quien puede llamarlo (solo el gateway).
apiVersion: v1
kind: Service
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector: {{ include "sa-common.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.servicio.puerto }}
      targetPort: http
EOF

  cat > "$t/hpa.yaml" <<'EOF'
{{- if .Values.hpa.habilitado }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "sa-common.fullname" . }}
  minReplicas: {{ .Values.hpa.minReplicas }}
  maxReplicas: {{ .Values.hpa.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.hpa.cpuObjetivoPorcentaje }}
{{- end }}
EOF

  cat > "$t/pdb.yaml" <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "sa-common.fullname" . }}
  labels: {{ include "sa-common.labels" . | nindent 4 }}
spec:
  minAvailable: {{ .Values.pdb.minDisponibles }}
  selector:
    matchLabels: {{ include "sa-common.selectorLabels" . | nindent 6 }}
EOF

  echo "$nombre: listo"
}

generar_uno "catalogo"    "Catalogo de productos de Aroma. API GraphQL (Node.js)."    4001 "aroma/catalogo-service"    catalogo_db    postgres              80m 96Mi  400m 256Mi
generar_uno "inventario"  "Inventario de insumos de Aroma. API GraphQL (Python)."     4002 "aroma/inventario-service"  inventario_db  "postgresql+psycopg"  80m 128Mi 400m 320Mi
generar_uno "resenas"     "Resenas de productos de Aroma. API REST (Python)."         4004 "aroma/resenas-service"     resenas_db     "postgresql+psycopg"  80m 128Mi 400m 320Mi
