{{/*
Named templates del chart padre. Los subcharts tienen los suyos propios
en sa-common/templates/_helpers.tpl; estos son solo para los objetos que
vive directamente en charts/sa-platform/templates (cuotas, redes, cronjobs).
*/}}

{{- define "sa-platform.labels" -}}
app.kubernetes.io/part-of: aroma
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "sa-platform.nombreCronInsertar" -}}
cronjob-insertar
{{- end -}}

{{- define "sa-platform.nombreCronResumen" -}}
cronjob-resumen
{{- end -}}
