{{- define "reelops.selector" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{- define "reelops.labels" -}}
{{ include "reelops.selector" . }}
app.kubernetes.io/part-of: reelops
app.kubernetes.io/version: {{ .root.Values.image.tag | default .root.Chart.AppVersion | quote }}
reelops/env: {{ .root.Values.env }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end }}

{{- define "reelops.image" -}}
{{ .root.Values.image.registry }}/{{ .svc.repository }}:{{ .root.Values.image.tag | default .root.Chart.AppVersion }}
{{- end }}
