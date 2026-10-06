{{/*
The measured service; required by every template.
*/}}
{{- define "slo.service" -}}
{{- required "service is required" .Values.service }}
{{- end }}

{{/*
Namespace the objects are created in.
*/}}
{{- define "slo.namespace" -}}
{{- .Values.namespace | default .Release.Namespace }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "slo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "slo.labels" -}}
helm.sh/chart: {{ include "slo.chart" . }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ include "slo.service" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Label matchers for the service's request series, as a PromQL matcher list
(sorted, without braces). Pass a dict with "root" and optional "extra"
(a string appended as one more matcher).
*/}}
{{- define "slo.matchers" -}}
{{- $root := .root }}
{{- $sel := dict "app" (include "slo.service" $root) "namespace" $root.Release.Namespace }}
{{- with $root.Values.selector }}{{ $sel = . }}{{ end }}
{{- $parts := list }}
{{- range $k := keys $sel | sortAlpha }}
{{- $parts = append $parts (printf "%s=%q" $k (index $sel $k | toString)) }}
{{- end }}
{{- with .extra }}{{ $parts = append $parts . }}{{ end }}
{{- join ", " $parts }}
{{- end }}

{{/*
Alert name for one SLO: alertNames.<slo> or <Service><suffix>.
*/}}
{{- define "slo.alertName" -}}
{{- $root := .root }}
{{- $set := index $root.Values.alertNames .slo }}
{{- $set | default (printf "%s%s" (include "slo.service" $root | title) .suffix) }}
{{- end }}
