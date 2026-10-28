# Contributing

Thanks for considering a contribution. Bug reports, documentation fixes and
tested chart changes are all welcome.

## Ground rule: no real environment data

This repository must contain no real hostnames, addresses, domains or
credentials. Use the reserved ranges in examples and defaults:

| Use | Range or domain | Reference |
| --- | --- | --- |
| Domains | `example.test`, `example.com` | RFC 2606 / RFC 6761 |
| Addresses | `10.0.0.0/8`, `192.168.0.0/16`, `172.16.0.0/12` | RFC 1918 |
| Documentation addresses | `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` | RFC 5737 |

Never commit a working password, even a throwaway one — it ends up in git
history, and people reuse examples verbatim.

Before opening a pull request:

```bash
# No routable-looking addresses outside the reserved ranges
git grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}' -- ':!*.md' ':!brand/*'

# No obvious secrets
git grep -niE 'password[^a-z]*[:=][^"]*[a-z0-9]' -- ':!*.md'
```

## Developing the chart

```bash
# Lint
helm lint charts/freeipa-mesh \
  --values charts/freeipa-mesh/examples/sandbox.yaml \
  --set auth.adminPassword=Passw0rd123 --set auth.dmPassword=Passw0rd456

# Render every profile
for p in 01-master 02-replica sandbox; do
  helm template t charts/freeipa-mesh \
    --values "charts/freeipa-mesh/examples/$p.yaml" \
    --set auth.adminPassword=Passw0rd123 --set auth.dmPassword=Passw0rd456 \
    > /dev/null && echo "$p ok"
done

# Check the installer script
bash -n charts/freeipa-mesh/scripts/freeipa-install.sh
shellcheck charts/freeipa-mesh/scripts/freeipa-install.sh   # if installed
```

CI runs the same checks. See `.github/workflows/lint.yml`.

## Conventions

**The installer takes everything from the environment.** No chart values are
templated into `scripts/freeipa-install.sh`; the chart passes `IPA_*` variables
and the script reads them. This keeps the script runnable and reviewable outside
Kubernetes. Add a new input as an environment variable in `pod.yaml`, not as a
template directive in the script.

**Derive, never duplicate.** An address, hostname or domain is written once in
values and computed everywhere else in `_helpers.tpl`. The chart this grew from
required the same IP to be edited in three places, which is exactly the class of
bug the helpers exist to prevent.

**Fail at template time.** If a misconfiguration can be detected while
rendering, detect it there with `fail` in `freeipa.validate` rather than letting
a pod get stuck. A clear `helm template` error costs seconds; a stuck install
costs an afternoon.

**The installer must stay idempotent.** `postStart` runs on every container
start. Any new step needs to be safe to re-run, and should skip cleanly when its
work is already done.

**Document every value.** A new value needs a comment in `values.yaml` and a row
in the README's values reference. Keep the two consistent.

## Testing changes for real

Rendering is not evidence that FreeIPA installs. Before submitting a change that
touches the installer or pod spec, run it on a cluster: the sandbox profile on
kind or minikube is enough for most changes, and a multi-node mesh is needed for
anything touching replication or topology. Say in the pull request what you
actually tested, and on what.

## Repository metadata

If you maintain a fork, keep the discoverability metadata set:

- **Description:** High-availability FreeIPA on Kubernetes: N-replica full
  replication mesh with routable macvlan IPs, scheduled ipa-backup and restore
  for DR.
- **Topics:** `freeipa`, `kubernetes`, `helm`, `high-availability`,
  `disaster-recovery`, `kerberos`, `ldap`, `identity-management`, `macvlan`,
  `multus`, `pki`

## Credit

This project packages [FreeIPA](https://www.freeipa.org/) and claims none of its
work. Changes that improve how faithfully we represent upstream behaviour, or
that correct our documentation of it, are especially welcome. See
[NOTICE.md](NOTICE.md).
