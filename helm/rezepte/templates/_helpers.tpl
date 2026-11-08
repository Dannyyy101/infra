{{- define "rezepte.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "rezepte.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/part-of: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* usage: include "rezepte.selectorLabels" (list . "app") */}}
{{- define "rezepte.selectorLabels" -}}
{{- $root := index . 0 -}}
app.kubernetes.io/name: {{ $root.Chart.Name }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/component: {{ index . 1 }}
{{- end -}}

{{- define "rezepte.secretName" -}}
{{- .Values.secrets.existingSecret | default (include "rezepte.fullname" .) -}}
{{- end -}}

{{/* usage: include "rezepte.secretEnv" (list . "ENV_NAME" "secret-key") */}}
{{- define "rezepte.secretEnv" -}}
- name: {{ index . 1 }}
  valueFrom:
    secretKeyRef:
      name: {{ include "rezepte.secretName" (index . 0) }}
      key: {{ index . 2 }}
{{- end -}}
