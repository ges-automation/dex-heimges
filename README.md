# dex-heimges

HEIMGES-specific patches and build tooling for [Dex](https://github.com/dexidp/dex).

This repository builds a custom Dex container image from a pinned upstream
Dex commit and applies a small set of patches used by the HEIMGES Active
Directory environment.

Pre-built container images are published to:

```text
ghcr.io/gesandrewmoore/dex-heimges
```

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

## Image Versioning

Images use the following tag format:

```text
YYYYMMDDHHMM-dex_<upstream-sha>-patch_<repository-sha>
```

For example:

```text
202609181015-dex_7ace0e7-patch_f781d43
```

The components are:

- `YYYYMMDDHHMM` - image build time in UTC
- `dex_<upstream-sha>` - short commit SHA of the upstream Dex source
- `patch_<repository-sha>` - short commit SHA of this `dex-heimges` repository

The repository SHA identifies the exact version of the patch files, build
script, documentation, and other repository contents used for the build.

## Building

Builds should be performed from a clean checkout of this repository.

Update the local checkout:

```sh
git pull --ff-only
```

Verify that the working tree is clean:

```sh
git status
```

Build the image:

```sh
./build.sh
```

The build script:

1. Determines the current UTC build timestamp.
2. Determines the current `dex-heimges` repository commit.
3. Fetches the exact configured upstream Dex commit.
4. Verifies that each patch applies cleanly.
5. Applies the HEIMGES patches.
6. Builds the resulting Docker image.
7. Tags the image using the versioning convention documented above.

The completed image will be named similar to:

```text
ghcr.io/gesandrewmoore/dex-heimges:202609181015-dex_7ace0e7-patch_f781d43
```

## Publishing to GitHub Container Registry

Publishing requires authentication to the GitHub Container Registry.

Create a GitHub personal access token with permission to write packages, then
authenticate Docker to GHCR:

```sh
read -rsp "GitHub PAT: " CR_PAT
echo
echo "$CR_PAT" | docker login ghcr.io \
    -u gesandrewmoore \
    --password-stdin
unset CR_PAT
```

A successful login should report:

```text
Login Succeeded
```

To build and immediately publish a new image:

```sh
PUSH=1 ./build.sh
```

A normal build without `PUSH=1` remains local:

```sh
./build.sh
```

This is useful when testing changes before publishing them.

### First Publication

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
docker pull ghcr.io/gesandrewmoore/dex-heimges:202609181015-dex_7ace0e7-patch_f781d43
```

Deployments should reference a specific versioned tag rather than relying on a
moving tag such as `latest`.

## Docker Compose

Reference the desired image directly in `compose.yml` or
`docker-compose.yml`:

```yaml
services:
  dex:
    image: ghcr.io/gesandrewmoore/dex-heimges:202609181015-dex_7ace0e7-patch_f781d43
```

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

The upstream Dex source is pinned to an exact commit in `build.sh`.

When updating Dex:

1. Select the desired upstream Dex commit.
2. Update `DEX_COMMIT` in `build.sh`.
3. Commit and push the change to this repository.
4. Run the build normally.
5. Confirm that all patches pass `git apply --check`.
6. Test the resulting image.
7. Publish the tested image.

If the patch files do not need to change, the upstream Dex SHA changes while
the repository SHA reflects the commit containing the updated build
configuration.

## License

The patches and original build tooling in this repository are licensed under
the Apache License 2.0.

Dex is maintained by the Dex project and is also licensed under the Apache
License 2.0.
