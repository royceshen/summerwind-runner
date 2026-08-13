# summerwind-runner

`summerwind/actions-runner` plus the tooling ARC jobs assume is present:

| tool | why |
| --- | --- |
| `docker buildx` (CLI plugin) | upstream ships a docker CLI without it, so `docker buildx build` fails in runner pods even with a dind sidecar attached |
| `docker` CLI, version-matched | keeps the client in step with the dind server |
| `aws` CLI v2 | upstream ships no `aws` binary at all — job steps fail with `aws: command not found` (e.g. `aws ecr get-login-password`, `aws s3 cp`) |
| `yq` v4 (mikefarah) | CD jobs patch gitops values with `yq e '.image.tag = "..."' -i`, which is v4 syntax |
| `jq` | relied on by ad-hoc CI steps; installed explicitly rather than assumed from the base |

## Image

```
ghcr.io/royceshen/summerwind-runner:ubuntu-24.04                                    # mutable
ghcr.io/royceshen/summerwind-runner:ubuntu-24.04-buildx0.35.0-docker29.1.3-aws2.36.21-yq4.53.3
ghcr.io/royceshen/summerwind-runner:sha-<short>                                     # immutable, pin this in ARC
ghcr.io/royceshen/summerwind-runner:latest                                          # mutable
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
| `awscli_version` | `2.36.21` (use `latest` to track the moving installer) |
| `yq_version` | `4.53.3` |
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
  --build-arg AWSCLI_VERSION=2.36.21 \
  --build-arg YQ_VERSION=4.53.3 \
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
`~/.docker` config. `aws` lands at `/usr/local/bin/aws` (install dir
`/usr/local/aws-cli`), on the default PATH for both the runner user and job
steps.

Installing the CLI does not give it credentials. For ECR access, attach an IAM
role to the runner service account via IRSA (or Pod Identity) — the CLI picks up
the projected token automatically:

```yaml
serviceAccountName: <sa-annotated-with-role-arn>
```
