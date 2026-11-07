{{- define "auth.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "auth.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/part-of: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* usage: include "auth.selectorLabels" (list . "zitadel") */}}
{{- define "auth.selectorLabels" -}}
{{- $root := index . 0 -}}
app.kubernetes.io/name: {{ $root.Chart.Name }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/component: {{ index . 1 }}
{{- end -}}

{{- define "auth.secretName" -}}
{{- .Values.secrets.existingSecret | default (include "auth.fullname" .) -}}
{{- end -}}

{{- define "auth.postgresHost" -}}
{{- if .Values.postgres.enabled -}}
{{- printf "%s-postgres" (include "auth.fullname" .) -}}
{{- else -}}
{{- required "postgres.host is required when postgres.enabled is false" .Values.postgres.host -}}
{{- end -}}
{{- end -}}

{{/* usage: include "auth.secretEnv" (list . "ENV_NAME" "secret-key") */}}
{{- define "auth.secretEnv" -}}
- name: {{ index . 1 }}
  valueFrom:
    secretKeyRef:
      name: {{ include "auth.secretName" (index . 0) }}
      key: {{ index . 2 }}
{{- end -}}
