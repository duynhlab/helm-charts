{{- define "vm-rules.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "vm-rules.bundledResource" -}}
{{- $root := .root }}
{{- $source := .source }}
{{- if hasKey $source "Error" }}{{ fail (printf "invalid bundled rule YAML: %s" $source.Error) }}{{ end }}
{{- $sourceName := required "rule metadata.name is required" $source.metadata.name }}
{{- $name := printf "%s-%s" (include "vm-rules.fullname" $root) $sourceName }}
{{- if gt (len $name) 253 }}{{ fail (printf "VMRule name is longer than 253 characters: %s" $name) }}{{ end }}
{{- $namespace := required "rule namespace is required" .namespace }}
{{- $identity := printf "%s/%s" $namespace $name }}
{{- if hasKey .seen $identity }}{{ fail (printf "duplicate VMRule %s" $identity) }}{{ end }}
{{- $_ := set .seen $identity true }}
{{- $_ := required (printf "%s: groups must not be empty" $identity) $source.spec.groups }}
{{- $labels := mergeOverwrite (include "vm-rules.labels" $root | fromYaml) (deepCopy (default dict $source.metadata.labels)) (deepCopy $root.Values.ruleSelectorLabels) }}
{{- $annotations := mergeOverwrite (deepCopy (default dict $source.metadata.annotations)) (dict "charts.duynhlab.dev/source-name" $sourceName) }}
---
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMRule
metadata:
  name: {{ $name }}
  namespace: {{ $namespace | quote }}
  labels:
    {{- toYaml $labels | nindent 4 }}
  annotations:
    {{- toYaml $annotations | nindent 4 }}
spec:
  {{- toYaml $source.spec | nindent 2 }}
{{ end }}

{{- define "vm-rules.fullname" -}}
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

{{- define "vm-rules.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "vm-rules.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
