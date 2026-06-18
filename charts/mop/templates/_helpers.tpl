{{/*
Expand the name of the chart.
*/}}
{{- define "mop.name" -}}
{{- .Values.name | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "mop.fullname" -}}
{{- .Values.name | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mop.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mop.labels" -}}
helm.sh/chart: {{ include "mop.chart" . }}
{{ include "mop.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.labels }}
{{- range $key, $value := .Values.labels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mop.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mop.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "mop.name" . }}
{{- end }}

{{/*
Create the image name
Format: repository (full path) + tag
Example: repository: ghcr.io/duynhne/auth, tag: v6
Result: ghcr.io/duynhne/auth:v6
*/}}
{{- define "mop.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}

{{/*
Create namespace
*/}}
{{- define "mop.namespace" -}}
{{- .Values.namespace | default .Release.Namespace }}
{{- end }}

