# summerwind-runner

`summerwind/actions-runner` with `docker buildx` embedded as a CLI plugin, plus a
docker CLI bumped to match the dind sidecar version.

Why: the upstream summerwind runner image ships a docker CLI without the buildx
plugin, so `docker buildx build` fails in ARC runner pods even when a dind
sidecar is attached.

## Image

```
ghcr.io/royceshen/summerwind-runner:ubuntu-24.04
ghcr.io/royceshen/summerwind-runner:ubuntu-24.04-buildx0.35.0-docker29.1.3
ghcr.io/royceshen/summerwind-runner:latest
```

Each tag is a single multi-arch manifest list covering `linux/amd64` and
`linux/arm64` — the same reference works on x86 and Graviton nodes, and the
kubelet picks the right variant. Confirm with:

```sh
docker buildx imagetools inspect ghcr.io/royceshen/summerwind-runner:ubuntu-24.04
```

## Build

Pushes to `main` that touch `Dockerfile` build and push automatically. Otherwise
run the `build-runner-image` workflow manually and override:

| input | default |
| --- | --- |
| `runner_tag` | `ubuntu-24.04` |
| `buildx_version` | `0.35.0` |
| `docker_version` | `29.1.3` |
| `platforms` | `linux/amd64,linux/arm64` |

The arm64 layers are built under QEMU on the amd64 hosted runner. That is cheap
here because the Dockerfile only downloads prebuilt binaries — nothing compiles.
If arm64 build time ever matters, split the job across `ubuntu-latest` and
`ubuntu-24.04-arm` and merge with `docker buildx imagetools create`; the hosted
arm64 runners are free for public repos but billed for private ones.

The final step re-inspects the pushed tag and fails the run if the manifest list
does not cover every requested platform, so a silently single-arch push can't
slip through.

Locally (needs `docker buildx` + binfmt for the non-native arch):

```sh
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg BUILDX_VERSION=0.35.0 \
  --build-arg DOCKER_VERSION=29.1.3 \
  -t summerwind-runner:local .
```

Multi-platform builds can't load into the local docker image store — add
`--push` to a registry, or build one `--platform` at a time with `--load`.

## First push: make the package public

GHCR packages are private on first publish. After the first successful run:

1. https://github.com/royceshen?tab=packages → `summerwind-runner`
2. Package settings → Danger Zone → **Change visibility** → Public
3. Package settings → Manage Actions access → add this repo with **Write** so
   later runs can push (added automatically when the workflow is in the same
   repo as the package).

## Usage in ARC

```yaml
spec:
  image: ghcr.io/royceshen/summerwind-runner:ubuntu-24.04
  dockerdWithinRunnerContainer: false
  dockerMTU: 1400  # match your CNI if you see hangs pulling base images
```

`buildx` lands at `/usr/local/lib/docker/cli-plugins/docker-buildx`, which is a
system-wide plugin path, so it resolves for the `runner` user without any
`~/.docker` config.
