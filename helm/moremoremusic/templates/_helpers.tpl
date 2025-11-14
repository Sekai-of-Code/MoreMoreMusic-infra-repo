{{/*
Expand the name of the chart.
*/}}
{{- define "moremoremusic.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "moremoremusic.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "moremoremusic.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "moremoremusic.labels" -}}
helm.sh/chart: {{ include "moremoremusic.chart" . }}
{{ include "moremoremusic.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "moremoremusic.selectorLabels" -}}
app.kubernetes.io/name: {{ include "moremoremusic.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
PostgreSQL host helper
*/}}
{{- define "moremoremusic.postgresql.host" -}}
{{- if .Values.postgresql.enabled -}}
{{ include "moremoremusic.fullname" . }}-postgresql
{{- else -}}
{{ .Values.postgresql.externalHost }}
{{- end -}}
{{- end }}

{{/*
Redis host helper
*/}}
{{- define "moremoremusic.redis.host" -}}
{{- if .Values.redis.enabled -}}
{{ include "moremoremusic.fullname" . }}-redis-master
{{- else -}}
{{ .Values.redis.externalHost }}
{{- end -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "moremoremusic.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "moremoremusic.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}