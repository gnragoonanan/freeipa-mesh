# Security

## Reporting a vulnerability

Report suspected vulnerabilities in **this chart** privately, through GitHub's
"Report a vulnerability" button under the Security tab, rather than in a public
issue. Please include the chart version, your Kubernetes and Helm versions, and
the steps to reproduce.

Vulnerabilities in **FreeIPA itself** belong upstream, not here:
<https://www.freeipa.org/page/Security>.

## What you are agreeing to when you run this chart

This is an unusually privileged workload, and you should understand why before
deploying it.

### The container is privileged

`securityContext.privileged: true` plus `SYS_ADMIN`, `SYS_MODULE` and
`NET_ADMIN`. FreeIPA is a systemd-managed appliance that sets the system
hostname, manages network configuration, loads kernel modules and writes to the
host cgroup hierarchy. None of that works in a restricted container.

A privileged container is close to root on the node. Consequences:

- Run these pods on nodes you are willing to treat as part of the identity tier,
  ideally a dedicated node pool.
- A Pod Security Admission label of `privileged` is required on the namespace.
  `baseline` and `restricted` will reject the pod.
- `/sys/fs/cgroup` is mounted from the host. It is read-only, but it is still a
  host mount.

If that trade is unacceptable, the upstream
[freeipa-container](https://github.com/freeipa/freeipa-container) images and the
experimental [freeipa-operator](https://github.com/freeipa/freeipa-operator) are
worth evaluating instead.

### Credential handling

What the chart does well:

- Passwords live in a Secret and are injected with `secretKeyRef`, so they do
  not appear in the pod spec, in `kubectl get pod -o yaml`, or in
  `helm get manifest`.
- Installing with no password fails rather than defaulting to something weak.

What you still need to know:

- **`auth.adminPassword` and `auth.dmPassword` set through values are stored in
  the Helm release Secret in the cluster**, and in your shell history if passed
  with `--set`. Use `auth.existingSecret` for anything real.
- **The unattended FreeIPA installers accept passwords only as command-line
  arguments.** During installation they are briefly visible in the process table
  *inside the container*. This is a property of `ipa-server-install`, not of the
  chart. The window is the length of the install, and the container is already
  privileged.
- Kubernetes Secrets are base64-encoded, not encrypted, unless you have enabled
  [encryption at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/).
  Enable it before storing a Directory Manager password.

### Network exposure

macvlan attaches the pod directly to your physical network, bypassing
NetworkPolicy, which operates on the cluster network. **A pod on a macvlan
interface is not protected by NetworkPolicy.** Filter at the switch, router or
host firewall instead.

The chart deliberately does not configure a firewall inside the pod. An earlier
version of the installer ran `ufw` in the container, which does not reliably
work there (`sysctl` changes do not apply as expected) and gave a false sense of
protection.

### What to review before production

- [ ] Encryption at rest is enabled for Secrets
- [ ] The namespace is labelled for privileged Pod Security Admission, deliberately
- [ ] Admin and Directory Manager passwords are different, and strong
- [ ] `auth.existingSecret` is used; no passwords in values files or CI logs
- [ ] Network access to ports 389/636/88/464/53 is restricted at the network layer
- [ ] `persistence` points at storage that is itself backed up
- [ ] A restore has been tested end to end, not just a backup taken
- [ ] `/root/cacert.p12` on the master is backed up somewhere safe — replicas
      cannot be created without it

## Supported versions

This chart is pre-1.0 and only the latest tag receives fixes.
