{{/*
Chart name.
*/}}
{{- define "freeipa.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified release name, truncated to the 63 character DNS limit.
*/}}
{{- define "freeipa.fullname" -}}
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

{{- define "freeipa.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "freeipa.labels" -}}
helm.sh/chart: {{ include "freeipa.chart" . }}
{{ include "freeipa.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: identity-server
app.kubernetes.io/part-of: freeipa-mesh
{{- end }}

{{- define "freeipa.selectorLabels" -}}
app.kubernetes.io/name: {{ include "freeipa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
=============================================================================
Derived values
=============================================================================
Everything below is computed from values.yaml so that an address, hostname or
domain is written in exactly one place. The original chart required the same
IP to be edited in three separate spots, which is what the "change this too"
comments in the old values files were warning about.
*/}}

{{/*
Kerberos realm. Defaults to the uppercased domain, per FreeIPA convention.
*/}}
{{- define "freeipa.realm" -}}
{{- if .Values.ipa.realm -}}
{{- .Values.ipa.realm | upper -}}
{{- else -}}
{{- .Values.ipa.domain | upper -}}
{{- end -}}
{{- end -}}

{{/*
FQDN of the server this release deploys.
*/}}
{{- define "freeipa.fqdn" -}}
{{- printf "%s.%s" (required "server.hostname is required" .Values.server.hostname) (required "ipa.domain is required" .Values.ipa.domain) -}}
{{- end -}}

{{/*
Short hostname of the master, taken from the topology list. Fails loudly when
the topology does not describe exactly one master, because installing two
masters for one realm produces two disjoint CAs and a broken deployment.
*/}}
{{- define "freeipa.masterHostname" -}}
{{- $masters := list -}}
{{- range .Values.topology.servers -}}
{{- if eq (default "replica" .role) "master" -}}
{{- $masters = append $masters .hostname -}}
{{- end -}}
{{- end -}}
{{- if ne (len $masters) 1 -}}
{{- fail (printf "topology.servers must contain exactly one entry with role: master, found %d" (len $masters)) -}}
{{- end -}}
{{- first $masters -}}
{{- end -}}

{{- define "freeipa.masterFqdn" -}}
{{- printf "%s.%s" (include "freeipa.masterHostname" .) .Values.ipa.domain -}}
{{- end -}}

{{/*
/etc/hosts entries for the whole mesh, as "ip fqdn short" records joined by
semicolons. Every server needs to resolve every other one during replication.
*/}}
{{- define "freeipa.hostsEntries" -}}
{{- $domain := .Values.ipa.domain -}}
{{- $out := list -}}
{{- range .Values.topology.servers -}}
{{- if .ip -}}
{{- $out = append $out (printf "%s %s.%s %s" .ip (required "each topology.servers entry needs a hostname" .hostname) $domain .hostname) -}}
{{- end -}}
{{- end -}}
{{- join ";" $out -}}
{{- end -}}

{{/*
Replica A records the master must publish, as "short=ip" pairs.
*/}}
{{- define "freeipa.replicaRecords" -}}
{{- $out := list -}}
{{- range .Values.topology.servers -}}
{{- if and (ne (default "replica" .role) "master") .ip -}}
{{- $out = append $out (printf "%s=%s" .hostname .ip) -}}
{{- end -}}
{{- end -}}
{{- join ";" $out -}}
{{- end -}}

{{/*
Name of the Secret holding the passwords.
*/}}
{{- define "freeipa.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
{{- printf "%s-auth" (include "freeipa.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Name of the NetworkAttachmentDefinition.
*/}}
{{- define "freeipa.attachmentName" -}}
{{- if .Values.network.macvlan.name -}}
{{- .Values.network.macvlan.name -}}
{{- else -}}
{{- printf "%s-macvlan" (include "freeipa.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Multus network annotation, generated from network.macvlan and server.ip so the
address is never duplicated by hand.
*/}}
{{- define "freeipa.networkAnnotation" -}}
{{- $m := .Values.network.macvlan -}}
{{- $ip := required "server.ip is required when network.macvlan.enabled is true" .Values.server.ip -}}
{{- $entry := dict "name" (include "freeipa.attachmentName" .) "ips" (list (printf "%s/%v" $ip $m.subnetPrefix)) -}}
{{- if $m.defaultGateway -}}
{{- $_ := set $entry "default-route" (list $m.defaultGateway) -}}
{{- end -}}
{{- list $entry | toJson -}}
{{- end -}}

{{/*
Validate that this release's own identity is consistent with the topology it
was given. A mismatch here is the single most likely cause of a failed join,
so it is cheaper to fail at template time than to debug a stuck pod.
*/}}
{{- define "freeipa.validate" -}}
{{- $hostname := .Values.server.hostname -}}
{{- $match := dict -}}
{{- range .Values.topology.servers -}}
{{- if eq .hostname $hostname -}}
{{- $match = . -}}
{{- end -}}
{{- end -}}
{{- if not $match.hostname -}}
{{- fail (printf "server.hostname %q does not appear in topology.servers; add it or correct the name" $hostname) -}}
{{- end -}}
{{- if .Values.network.macvlan.enabled -}}
{{- if ne (default "" $match.ip) (default "" .Values.server.ip) -}}
{{- fail (printf "server.ip %q does not match the ip %q listed for %q in topology.servers" .Values.server.ip $match.ip $hostname) -}}
{{- end -}}
{{- range .Values.topology.servers -}}
{{- if not .ip -}}
{{- fail (printf "topology.servers entry %q has no ip; every member needs a static address when macvlan is enabled" .hostname) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if ne (default "replica" $match.role) .Values.server.role -}}
{{- fail (printf "server.role %q does not match the role %q listed for %q in topology.servers" .Values.server.role (default "replica" $match.role) $hostname) -}}
{{- end -}}
{{- if not (has .Values.server.role (list "master" "replica")) -}}
{{- fail (printf "server.role must be \"master\" or \"replica\", got %q" .Values.server.role) -}}
{{- end -}}
{{- end -}}
