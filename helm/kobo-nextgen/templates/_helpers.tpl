{{- define "kobo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kobo.fullname" -}}
{{- default (printf "%s-%s" .Release.Name (include "kobo.name" .)) .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kobo.labels" -}}
app.kubernetes.io/name: {{ include "kobo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

{{- define "kobo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kobo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "kobo.image" -}}
{{ printf "%s:%s" .repository .tag }}
{{- end }}

{{- define "kobo.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kobo.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "kobo.mediaVolume" -}}
{{- if .Values.gcsFuse.enabled }}
csi:
  driver: gcsfuse.csi.storage.gke.io
  readOnly: false
  volumeAttributes:
    bucketName: {{ required "gcsFuse.bucketName is required" .Values.gcsFuse.bucketName | quote }}
    mountOptions: {{ .Values.gcsFuse.mountOptions | quote }}
{{- else if .Values.persistence.media.enabled }}
persistentVolumeClaim:
  claimName: {{ default (printf "%s-media" (include "kobo.fullname" .)) .Values.persistence.media.existingClaim }}
{{- else }}
emptyDir: {}
{{- end }}
{{- end }}

{{- define "kobo.podAnnotations" -}}
{{- if .Values.gcsFuse.enabled }}
gke-gcsfuse/volumes: "true"
{{- end }}
{{- end }}
