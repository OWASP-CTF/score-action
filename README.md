# score-action

Docker **container** GitHub Action that scores an **OWASP CTF** patch PR against the scorer
image and records the result on the leaderboard.

It replaces the ~300 lines of near-identical `ctf-score.yml` every CTF fork copy-pastes. The
action **is** the scorer image (`image: docker://ghcr.io/OWASP-CTF/score:latest`, org-internal,
pulled by the runner under `pull_request_target`), so there's no separate login/pull — its
entrypoints run *inside* the image, which already ships the rubric, the `score` binary, node,
curl and the docker CLI.

```yaml
- uses: actions/checkout@v5 # PR head, so the action can docker-build it
  with:
    ref: ${{ github.event.pull_request.head.sha }}
- id: identity # mint the OIDC id-token
  uses: cnuss/actions-identity@v1.1.0
  with:
    id-token-audience: ctf-score
- uses: OWASP-CTF/score-action@main
  with:
    target: dvwa
    app-url: http://app
    id-token: ${{ steps.identity.outputs.id-token }}
```

First consumer: [`OWASP-CTF/DVWA#28`](https://github.com/OWASP-CTF/DVWA/pull/28).

## How it works (two baked scripts, one image)

- **`pre-entrypoint: pre-score.sh`** — evaluates `target`, creates the `ctfnet` `--internal`
  (internet-less) network, `docker build`s the PR's app image, and brings it up **daemonized**
  via the per-target `score-<target>-challenges.sh` (e.g. DVWA also boots MariaDB + inits the DB).
  Drives the host daemon through the bind-mounted socket.
- **`entrypoint: score.sh`** — joins `ctfnet`, then runs `score --post`: scores the running app
  against the embedded rubric and HTTP `POST`s the result to the scoring API.

Both scripts are baked into the scorer image (dc34 `.github/actions/ctf-score/`), so
`pre-entrypoint`/`entrypoint` resolve on `PATH`.

## Inputs

| input | required | description |
|-------|----------|-------------|
| `target` | ✅ | `juice-shop` \| `dvwa` \| `webgoat` \| `securityshepherd` \| `vampi` \| `vulnerableapp` |
| `app-url` | ✅ | Base URL `score.sh` hits on `ctfnet` (e.g. `http://app`, `http://app:8080/WebGoat`) |
| `id-token` | ✅ | OIDC id-token the leaderboard authorizes — **the consumer mints it** (e.g. `cnuss/actions-identity`, audience `ctf-score`) |

Everything else is hardcoded (one CTF = one leaderboard + one scorer): `SCORE_API`,
`LEADERBOARD_URL`, network `ctfnet`, image `…/score:latest`. `GH_TOKEN` for the PR comment comes
from `${{ github.token }}` in `env` (container actions don't get it for free).

## Required job permissions

```yaml
permissions:
  contents: read       # checkout the PR head to build it
  packages: read       # runner pulls the org-internal scorer image
  id-token: write      # mint the OIDC id-token the leaderboard authorizes
  pull-requests: write # the result comment
```

## Leaderboard auth — no stored secret

The consumer mints the id-token; `score --post` sends it as a bearer to `POST /score`, which the
server authorizes by the token's `repository_owner`. Author / PR / SHA travel in the body from
the trusted `github.event` context, never from PR code.

## Security — one-job model

`id-token: write` + `pull-requests: write` sit next to the untrusted `docker build`. Safe **only
because PR code never runs on the runner host** — it is exclusively `docker build`/`docker run`
into containers on an `--internal` (internet-less) network. The action container joins that
network only to make client HTTP requests to the app; it runs no inbound service and doesn't
route the app's traffic out, so the app stays internet-less.

> **Do not** add a consumer step that executes PR-controlled code directly on the runner (for
> example `npm run` / `mvn` from the PR checkout, outside a container).
