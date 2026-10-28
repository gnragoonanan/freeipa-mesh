# freeipa-mesh (Helm chart)

High-availability FreeIPA on Kubernetes pods: an N-replica full replication
mesh with routable macvlan IPs, scheduled `ipa-backup` and restore for DR.

**The full documentation, including the complete values reference table, lives
in the [project README](../../README.md).** This file covers only what is
specific to installing the chart.

## Install

One Helm release installs one FreeIPA server. Install the master first and let
it finish, then add replicas.

```bash
# Credentials first, kept out of values files
kubectl create namespace freeipa
kubectl -n freeipa create secret generic freeipa-auth \
  --from-literal=admin-password='...' \
  --from-literal=dm-password='...'

# Master
helm install ipa1 . --namespace freeipa \
  --values examples/01-master.yaml

# Replicas, once the master is up
helm install ipa2 . --namespace freeipa --values examples/02-replica.yaml
```

For a single-pod smoke test with no Multus and no storage:

```bash
helm install sandbox . --namespace freeipa-sandbox --create-namespace \
  --values examples/sandbox.yaml \
  --set auth.adminPassword='ChangeMe123' \
  --set auth.dmPassword='ChangeMe456'
```

## What the chart creates

| Object | When |
| --- | --- |
| `Pod` | Always. One per release — a FreeIPA server has its own identity and is not interchangeable with its peers |
| `ConfigMap` | Always. Carries the installer script, mounted executable |
| `Secret` | Only when `auth.existingSecret` is empty |
| `NetworkAttachmentDefinition` | When `network.macvlan.enabled` and `createAttachment` are true |
| `PersistentVolumeClaim` | When `persistence.type=pvc` and no `existingClaim` is set |

No `Namespace` object is created, so several server releases can share one
namespace. Install with `--create-namespace` or create it yourself.

## Values

`values.yaml` is commented throughout, and every parameter is tabulated in the
[project README](../../README.md#values-reference). At minimum you must set
`ipa.domain`, the `auth` credentials, this server's `server` block, the
`topology.servers` list and the `network.macvlan` block.

## Notes

- `helm lint` and `helm template` fail by design when no password is supplied
  and `auth.existingSecret` is unset. Pass throwaway values when rendering for
  inspection.
- The chart cross-checks `server.hostname`, `server.ip` and `server.role`
  against `topology.servers` and refuses to render on a mismatch.
- `examples/` is excluded from the packaged chart by `.helmignore`.

## Credit

This chart packages [FreeIPA](https://www.freeipa.org/), which does all of the
identity management work. See [NOTICE.md](../../NOTICE.md).
