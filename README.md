# dex-heimges

HEIMGES-specific patches and build tooling for [Dex](https://github.com/dexidp/dex).

This repository builds a custom Dex container image from a pinned upstream
Dex commit and applies a small set of patches used by the HEIMGES Active
Directory environment.

Pre-built container images are published to:

```text
ghcr.io/ges-automation/dex-heimges
```

## Repository Layout

```text
dex-heimges/
├── .gitignore
├── LICENSE
├── Makefile
├── README.md
├── patches/
│   ├── ges-claims.go.patch
│   └── ges-ldap.go.patch
└── scripts/
    ├── cleanup-images.sh
    ├── image-push.sh
    └── image.sh
```

Patch files are stored in the `patches/` directory.

`scripts/image.sh` automatically discovers all `*.patch` files in that directory,
validates them, and applies them in lexical filename order.

If patch ordering becomes important, use numeric filename prefixes such as:

```text
patches/
├── 010-ges-claims.go.patch
├── 020-ges-ldap.go.patch
└── 030-example.patch
```

## Patches

### Connector ID normalization

Dex normally incorporates the connector ID into the generated OIDC subject.
That means the same upstream user authenticated through two different Dex
connectors would normally receive different OIDC `sub` values.

This patch normalizes any connector ID beginning with:

```text
heimges-
```

to the internal connector ID:

```text
heimges
```

when Dex generates the OIDC subject.

For example, these two connectors:

```yaml
connectors:
  - type: ldap
    id: heimges-ldap
    name: Password

  - type: authproxy
    id: heimges-windows
    name: Windows
```

are both treated internally as:

```text
heimges
```

for subject generation.

This allows the same upstream user ID to produce the same stable OIDC subject
regardless of whether the user authenticated through the LDAP/password path or
the Windows/authproxy path.

Only the subject-generation behavior is normalized. The configured connector
IDs remain distinct everywhere else in Dex.

### Active Directory LDAP identifiers

The LDAP patch extends Dex's `userSearch.idAttr` handling for Active Directory.

#### Multiple `idAttr` values

Upstream Dex expects a single `idAttr` value. This patch allows `idAttr` to be
either a single value or a list of values.

Example:

```yaml
userSearch:
  idAttr:
    - ms-DS-ConsistencyGuid
    - objectGUID
```

Dex evaluates the configured attributes in order and uses the first available
value.

#### `preferredIdAttr`

The patch also adds a new optional `preferredIdAttr` setting.

Example:

```yaml
userSearch:
  idAttr:
    - ms-DS-ConsistencyGuid
    - objectGUID

  preferredIdAttr: ms-DS-ConsistencyGuid
```

`preferredIdAttr` must also appear in `idAttr`.

When configured, Dex checks the preferred attribute first. If it is present
and has a usable value, that value is used as the user's stable ID. If it is
not available, Dex falls back through the remaining configured `idAttr`
values.

This allows HEIMGES to prefer `ms-DS-ConsistencyGuid` while falling back to
`objectGUID`.

A representative LDAP connector configuration is:

```yaml
connectors:
  - type: ldap
    id: heimges-ldap
    name: Password

    config:
      host: heimges.local:636

      userSearch:
        baseDN: DC=heimges,DC=local
        filter: "(&(objectClass=user)(!(objectClass=computer)))"

        username:
          - sAMAccountName
          - userPrincipalName
          - mail

        idAttr:
          - ms-DS-ConsistencyGuid
          - objectGUID

        preferredIdAttr: ms-DS-ConsistencyGuid

        emailAttr: mail
        nameAttr: displayName
        preferredUsernameAttr: sAMAccountName
```

The patch also adds Active Directory-aware binary conversion support for:

```text
objectGUID
ms-DS-ConsistencyGuid
objectSID
```

This allows those binary LDAP attributes to be converted into stable,
human-readable string values suitable for use as Dex user IDs and OIDC subject
inputs.

For example, the resulting stable user ID can be supplied through the
authproxy connector as well:

```yaml
connectors:
  - type: authproxy
    id: heimges-windows
    name: Windows

    config:
      userHeader: X-Remote-User
      userIDHeader: X-Remote-User-Id
      userNameHeader: X-Remote-User-Name
      emailHeader: X-Remote-User-Email
      groupHeader: X-Remote-Group
      groupHeaderSeparator: ";"
```

If the LDAP connector resolves the same stable user ID that the authproxy
supplies in `X-Remote-User-Id`, and both connector IDs begin with `heimges-`,
both authentication paths generate the same OIDC subject.

## Image Versioning

### Versioned images

Official versioned images use the GHCR namespace and the following tag format:

```text
ghcr.io/ges-automation/dex-heimges:YYYYMMDDHHMM-dex_<upstream-sha>-patch_<patch-commit-sha>
```

For example:

```text
ghcr.io/ges-automation/dex-heimges:202609181015-dex_7ace0e7-patch_f781d43
```

The components are:

- `YYYYMMDDHHMM` - image build time in UTC
- `dex_<upstream-sha>` - short commit SHA of the upstream Dex source
- `patch_<patch-commit-sha>` - short commit SHA of this `dex-heimges` repository

The patch commit SHA identifies the exact commit of this `dex-heimges`
repository, including the patch files, image script, image push script,
documentation, and other repository contents used to build the image.

### Development images

Development builds intentionally omit both the GHCR namespace and patch
commit SHA. They use the local-only format:

```text
dex-heimges:YYYYMMDDHHMM-dex_<upstream-sha>-dev
```

For example:

```text
dex-heimges:202609181015-dex_7ace0e7-dev
```

This makes development images visually distinct from pushable versioned
images and prevents them from being accepted by `scripts/image-push.sh`.

## Container Images

The repository uses `make` as the primary human-facing interface. The shell
scripts in `scripts/` remain independently runnable and contain the actual
image build, image push, and cleanup logic.

Run the self-documenting help target to see the available commands:

```sh
make help
```

Available Make targets are:

```text
make                 Build an official versioned image locally
make help            Show available targets
make image           Build a container image locally
make image-dev       Build a local development image
make image-push      Push the most recent versioned image to GHCR
make clean           Remove local dex-heimges versioned and development images
```

`image` is the default target, so plain `make` is equivalent to:

```sh
make image
```

### Versioned images

Create an official versioned image locally with:

```sh
make
```

or explicitly:

```sh
make image
```

The underlying script can also be run directly:

```sh
sh ./scripts/image.sh
```

Versioned image builds are intentionally strict. Before building, the script:

1. Verifies that Git and Docker are available.
2. Requires a clean Git working tree with no uncommitted or untracked files.
3. Fetches the latest `origin/main`.
4. Requires local `HEAD` to exactly match `origin/main`.
5. Checks the pinned Dex commit against the current tip of upstream `master`.
6. If upstream `master` differs, displays both short and full SHAs and asks
   whether to continue with the pinned commit.
7. Determines the current UTC build timestamp and patch repository commit.
8. Fetches the exact configured upstream Dex commit.
9. Discovers all `*.patch` files in `patches/`.
10. Verifies that every patch applies cleanly.
11. Applies all patches in lexical filename order.
12. Builds the resulting Docker image in the official GHCR namespace.
13. Records the exact image name in `.build-image` for use by `make image-push`.

The completed image will be named similar to:

```text
ghcr.io/ges-automation/dex-heimges:202609181015-dex_7ace0e7-patch_f781d43
```

If the local checkout is behind, ahead of, or otherwise different from
`origin/main`, the versioned image build is refused. Update the checkout with:

```sh
git pull --ff-only
```

The `.build-image` file is local build state and is excluded from Git.

### Development builds

Use development mode when creating or modifying patches that have not yet been
committed and pushed:

```sh
make image-dev
```

The explicit mode form is equivalent and can be useful in automation:

```sh
make image IMAGE_MODE=dev
```

The underlying script remains available directly:

```sh
sh ./scripts/image.sh --dev
```

Both forms use the same development image logic.

Development mode:

- Allows uncommitted and untracked repository changes.
- Does not require the checkout to match `origin/main`.
- Checks the pinned Dex commit against the current tip of upstream `master`
  and prompts before continuing if they differ.
- Uses the current files in `patches/`, including newly-created untracked patch files.
- Builds into the local `dex-heimges` namespace instead of `ghcr.io`.
- Omits the patch commit SHA from the image tag.
- Does not create `.build-image`.
- Removes any existing `.build-image` so a stale versioned image cannot be
  pushed after a development build.

A development image will be named similar to:

```text
dex-heimges:202609181015-dex_7ace0e7-dev
```

This mode is intended for iterating on patches directly on a Docker host,
running the resulting image locally, and validating changes before committing
them.

### Cleaning local images

Remove all local `dex-heimges` versioned and development images with:

```sh
make clean
```

This delegates to `scripts/cleanup-images.sh`, which targets only these two
image repositories:

```text
ghcr.io/ges-automation/dex-heimges
dex-heimges
```

It does not remove containers, volumes, networks, or Docker/BuildKit build
cache. Images currently required by a container may be refused by Docker until
that container is removed.

## Pushing to GitHub Container Registry

Registry publication is explicit and separate from building the image locally.

Run:

```sh
make image-push
```

The underlying script can also be run directly:

```sh
sh ./scripts/image-push.sh
```

The image push script:

1. Reads the image name recorded by the most recent successful versioned image build.
2. Refuses images outside `ghcr.io/ges-automation/dex-heimges`.
3. Verifies that the image exists locally.
4. Reads the GHCR username and personal access token from 1Password.
5. Reuses an existing 1Password CLI session if one is already active.
6. Otherwise performs an interactive 1Password sign-in for the duration of the script.
7. Authenticates Docker to `ghcr.io` using a temporary Docker configuration.
8. Pushes the recorded image to GitHub Container Registry.
9. Deletes the temporary Docker authentication state when the script exits.

Development builds cannot be pushed through this workflow: they do not
write `.build-image`, and the explicit GHCR namespace check provides an
additional safeguard against pushing a local development image.

After the versioned tag is pushed successfully, the same image is also
tagged and pushed as:

```text
ghcr.io/ges-automation/dex-heimges:latest
```

The immutable versioned tag remains available while `latest` moves to the most
recently pushed version.

### 1Password Configuration

Pushing requires the [1Password CLI](https://developer.1password.com/docs/cli/)
and a 1Password item containing these fields:

```text
username
credential
```

The `credential` field should contain a GitHub personal access token with
permission to write packages to GHCR.

The script expects the environment variable:

```text
GHCR_PAT_OP_REF
```

to contain a 1Password item reference, for example:

```text
op://<vault-id>/<item-id>
```

If `GHCR_PAT_OP_REF` is not set, `scripts/image-push.sh` prompts for the reference and
offers to save it to:

```text
~/.profile
```

Only the 1Password item reference is stored in the profile. The GitHub token
itself remains stored in 1Password.

The script reads the two required fields as:

```text
${GHCR_PAT_OP_REF}/username
${GHCR_PAT_OP_REF}/credential
```

### 1Password Authentication

If you are already signed into the 1Password CLI in the current shell,
`scripts/image-push.sh` reuses that session.

Otherwise, the script performs an interactive `op signin` internally. That
session exists only for the lifetime of `scripts/image-push.sh` and is not persisted back
into the parent interactive shell.

### Docker Authentication

`scripts/image-push.sh` creates a temporary `DOCKER_CONFIG` directory before logging into
GHCR.

This prevents the GitHub token from being persisted in:

```text
~/.docker/config.json
```

The temporary Docker configuration is deleted automatically when the script
finishes.

## First Publication

New GitHub Container Registry packages may need their visibility changed after
the initial push.

After the first image has been published:

1. Open the `dex-heimges` package on GitHub.
2. Open **Package settings**.
3. Change the package visibility to **Public**.

Once public, the image can be pulled anonymously without GitHub credentials.

## Pulling an Image

Pull a specific published image with:

```sh
docker pull ghcr.io/ges-automation/dex-heimges:202609181015-dex_7ace0e7-patch_f781d43
```

Deployments may either pin a specific immutable versioned tag or intentionally
track the moving `latest` tag. `latest` always points to the most recently
pushed version.

## Docker Compose

Reference either a specific version or the moving `latest` tag in `compose.yml`
or `docker-compose.yml`. For deployments that should track the current pushed
version:

```yaml
services:
  dex:
    image: ghcr.io/ges-automation/dex-heimges:latest
```

For deployments that should remain pinned until intentionally changed, use a
specific versioned tag instead.

Because the package is public, deployment hosts do not require a GitHub login.

After changing the image tag in the Compose file:

```sh
docker compose pull
docker compose up -d
```

To confirm the image currently used by the Compose project:

```sh
docker compose images
```

## Updating the Upstream Dex Revision

The upstream Dex source is pinned to an exact commit in `scripts/image.sh`. Both versioned
and development image builds compare that pin with the current tip of upstream Dex
`master`. If they differ, the build pauses and displays both the short and full
SHA for the pinned commit and current `master` before asking whether to
continue. The full current `master` SHA can be copied directly into
`DEX_COMMIT` when intentionally advancing the pin.

When updating Dex:

1. Select the desired upstream Dex commit.
2. Update `DEX_COMMIT` in `scripts/image.sh`.
3. Commit and push the change to this repository.
4. Run the build normally.
5. Confirm that all patches pass validation.
6. Test the resulting image.
7. Push the tested image with `make image-push`.

If the patch files do not need to change, the upstream Dex SHA changes while
the patch commit SHA reflects the commit containing the updated build
configuration.

## Adding or Updating Patches

Add new patch files to:

```text
patches/
```

No changes to `scripts/image.sh` are required for additional `*.patch` files.

While developing a patch, build and test the current working tree with:

```sh
make image-dev
```

The equivalent explicit mode form is:

```sh
make image IMAGE_MODE=dev
```

The direct script equivalent is:

```sh
sh ./scripts/image.sh --dev
```

After the patch has been validated, commit and push it:

```sh
git add patches/
git commit -m "Update Dex patches"
git push
```

Then create the official versioned image:

```sh
make
```

The versioned image build's clean-tree and `origin/main` checks ensure that the
patch commit SHA embedded in the image tag represents the exact source used to
build the image.

## License

The patches and original build tooling in this repository are licensed under
the Apache License 2.0.

Dex is maintained by the Dex project and is also licensed under the Apache
License 2.0.
