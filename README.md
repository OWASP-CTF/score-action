# score-action

Composite GitHub Action that scores an **OWASP CTF** patch PR against the private scorer
image and records the result on the leaderboard.

It replaces the ~300 lines of near-identical YAML that every CTF fork used to copy-paste.
A consumer workflow now only does the part that's actually app-specific — **build + boot
the PR's app** — and hands the running app to this action for everything shared: pull the
scorer, run the rubric, record the score, and comment on the PR.

```yaml
- name: Score + record
  uses: OWASP-CTF/score-action@main
  with:
    target: dvwa
    app-url: http://app
```

## What it does

1. Logs in to GHCR and pulls the private scorer image.
2. Runs the scorer against the already-running app (`--target <target> --url <app-url>`),
   producing the `ctf-score.json` sidecar. The rubric is baked into the image — no answer
   key is ever checked out.
3. Mints a GitHub **OIDC id-token** and `POST`s the result to the scoring API. No stored
   datastore secret: the server authorizes the run by the token's `repository_owner`.
4. Upserts a single result comment on the PR (recorded / no-points-yet / did-not-complete).

## Inputs

| input | required | default | description |
|-------|----------|---------|-------------|
| `target` | ✅ | | `juice-shop` \| `dvwa` \| `webgoat` \| `securityshepherd` \| `vampi` \| `vulnerableapp` |
| `app-url` | ✅ | | Base URL the scorer hits, reachable on `network` (e.g. `http://app`, `http://app:8080/WebGoat`) |
| `network` | | `ctfnet` | Docker network the app runs on; the scorer joins it |
| `score-image` | | `ghcr.io/owasp-ctf/score:latest` | Private scorer image |
| `score-api` | | `https://api.ctf.owasp.org` | Scoring API base (`POST <score-api>/score`) |
| `audience` | | `ctf-score` | OIDC id-token audience the API requires |
| `extra-env` | | | Newline-separated `KEY=VALUE` pairs passed to the scorer as `-e` (e.g. `WEBWOLF_URL=…`) |
| `source-mount` | | | Host path mounted **read-only** at `/src` and exposed as `CTF_UPSTREAM_DIR` (source-analysis challenges) |
| `post-comment` | | `true` | Upsert the PR result comment |
| `leaderboard-url` | | `https://ctf.owasp.org/leaderboard` | URL shown in the comment |

## Outputs

| output | description |
|--------|-------------|
| `open` | Challenges still open (0 = all patched) |
| `recorded` | `'true'` if solves were sent to the leaderboard |

## Required job permissions

```yaml
permissions:
  contents: read       # checkout the PR head to build it
  packages: read       # pull the private scorer image
  id-token: write      # mint the OIDC token POST /score authorizes
  pull-requests: write # the result comment
```

## Security model

The action runs as **steps in one job**, so that job holds `id-token: write` and
`pull-requests: write` next to the untrusted `docker build`. This is safe **only because
the PR's code never runs on the runner host** — it is exclusively `docker build`/`docker
run` into containers on an `--internal` (internet-less) network, so it cannot read the
runner's OIDC request token or `GITHUB_TOKEN`.

> **Do not** add a step that executes PR-controlled code directly on the runner (for
> example `npm run` / `mvn` from the PR checkout, outside a container) in this job.

The leaderboard write carries **no secret**: the id-token is minted per-run (audience
`ctf-score`, via [`cnuss/actions-identity`](https://github.com/cnuss/actions-identity)) and
sent as a bearer to `POST /score`, which the server authorizes by `repository_owner`.
Author / PR / SHA travel in the request body from the trusted `github.event` context, not
from PR code.

## Examples

Full consumer workflows live in [`examples/`](examples/): `juice-shop.yml`, `dvwa.yml`,
`webgoat.yml`. Copy the matching one into a fork as `.github/workflows/ctf-score.yml`.
