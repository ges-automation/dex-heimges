# dex-heimges

HEIMGES-specific patches and build tooling for [Dex](https://github.com/dexidp/dex).

This repository builds a custom Dex container image from a pinned upstream
Dex commit and applies a small set of patches used by the HEIMGES Active
Directory environment.

## Patches

### Connector ID normalization

Normalizes HEIMGES Dex connector IDs when generating OIDC subjects so that
multiple authentication paths for the same user can produce a stable subject.

### Active Directory LDAP identifiers

Extends the Dex LDAP connector with support for:

- Multiple `idAttr` values
- A preferred ID attribute
- Active Directory `objectGUID`
- Active Directory `mS-DS-ConsistencyGuid`
- Active Directory `objectSID`

## Building

Run:

```sh
./build.sh
```

The build script fetches the configured upstream Dex commit, verifies and
applies the patches, and builds the resulting container image.

## Container Images

Pre-built container images are published to:

```text
ghcr.io/gesandrewmoore/dex-heimges
```

Image tags use the format:

```text
YYYYMMDDHHMM-dex_<upstream-sha>-patch_<repository-sha>
```

## License

The patches and original build tooling in this repository are licensed under
the Apache License 2.0.

Dex is maintained by the Dex project and is also licensed under the Apache
License 2.0.
