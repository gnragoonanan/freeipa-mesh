# Credits and attribution

## Powered by FreeIPA

This project does not implement identity management. It packages and operates
[**FreeIPA**](https://www.freeipa.org/), the integrated identity and
authentication solution that does all of the real work here: Kerberos KDC,
389 Directory Server, Dogtag PKI, BIND DNS and the Web UI.

Every capability this project advertises — the replication mesh, the certificate
authority, the backup and restore path — is FreeIPA functionality. What lives in
this repository is Helm packaging, pod networking and lifecycle automation on top
of it.

Our thanks to the FreeIPA maintainers and contributors for a decade and a half of
work on free software identity management.

- Project home: https://www.freeipa.org/
- Source: https://github.com/freeipa/freeipa
- Upstream container images: https://github.com/freeipa/freeipa-container
- Mailing lists and support: https://www.freeipa.org/page/Mailing_Lists_and_IRC

FreeIPA is free software. Refer to the licence terms in the upstream source for
the exact terms that apply to each component.

## Trademarks

Red Hat and FreeIPA are trademarks of Red Hat, Inc., registered in the U.S. and
other countries. All other trademarks are the property of their respective
owners.

This project is an independent effort. It is **not** affiliated with, sponsored
by, or endorsed by Red Hat, Inc. or the FreeIPA project. The phrase "Powered by
FreeIPA" is used descriptively, to state the factual relationship that this
project deploys FreeIPA.

No FreeIPA logo artwork is included in this repository. Content on freeipa.org is
licensed CC BY-SA 4.0, but that licence
[expressly excludes trademarks](https://www.freeipa.org/page/Legal.html),
"including the FreeIPA logomark and logotype". The credit assets in `brand/` are
therefore text-only and original. If you want to display the official logomark,
request permission from the FreeIPA project first, then paste the artwork into
the `#freeipa-logo-slot` group in `brand/banner-freeipa-mesh.svg`.

## Other components

- Container base image: [`buluma/fedora-systemd`](https://hub.docker.com/r/buluma/fedora-systemd)
- Multiple pod networks: [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)
  with the `macvlan` CNI plugin
- Packaging: [Helm](https://helm.sh/)

## Brand assets in this repository

The marks in `brand/` (`logo-freeipa-mesh.svg`, `banner-freeipa-mesh.svg`,
`powered-by-freeipa.svg`) are original artwork for this project and are not
derived from FreeIPA or Red Hat trademarks.

## Copyright

Copyright 2026 GnR (gnragoonanan).

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
