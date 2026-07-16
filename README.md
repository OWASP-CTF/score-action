# score-action

**Composite** GitHub Action that scores an **OWASP CTF** patch PR against the scorer image and
records the result on the leaderboard.

It replaces the ~300 lines of near-identical `ctf-score.yml` every CTF fork copy-pastes. A
consumer checks out the PR head and mints an OIDC id-token, then hands off to this action.

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

First consumer: [`OWASP-CTF/DVWA`](https://github.com/OWASP-CTF/DVWA).

## Why composite (not a docker container action)

A docker **container** action has its image pulled by GitHub **anonymously** — no
`GITHUB_TOKEN`, no `packages: read` — so an **internal/private** image `401`s. The scorer image
bakes the rubric (answer key), so it must stay internal. A **composite** action runs on the host,
so it can `docker login` and pull the internal image explicitly. It then runs the image's baked
`entrypoint.sh` via `docker run` (host docker socket mounted), which builds + boots the PR app on
the `ctfnet` `--internal` network, scores it, and POSTs the result.

## Inputs

| input | required | default | description |
|-------|----------|---------|-------------|
| `target` | ✅ | | `juice-shop` \| `dvwa` \| `webgoat` \| `securityshepherd` \| `vampi` \| `vulnerableapp` |
| `app-url` | ✅ | | Base URL the scorer hits on `ctfnet` (e.g. `http://app`, `http://app:8080/WebGoat`) |
| `id-token` | ✅ | | OIDC id-token the leaderboard authorizes — the consumer mints it (audience `ctf-score`) |
| `github-token` | | `${{ github.token }}` | Token to log in to GHCR (pull the internal scorer image) |
| `score-image` | | `ghcr.io/owasp-ctf/score:latest` | Scorer image to pull + run |

`SCORE_API` comes from the org variable `vars.SCORE_API_URL` (falling back to the temp CloudFront
domain until `api.ctf.owasp.org` DNS lands).

## Required job permissions

```yaml
permissions:
  contents: read       # checkout the PR head to build it
  packages: read       # docker login + pull the internal scorer image
  id-token: write      # mint the OIDC id-token the leaderboard authorizes
  pull-requests: write # the result comment
```

## Security model

The PR's code is only ever `docker build`/`docker run` into containers on an `--internal`
(internet-less) network; it never executes on the runner host, so it can't read the OIDC
id-token or `GITHUB_TOKEN`. The scorer container joins that network only to make client HTTP
requests to the app. The leaderboard write carries no stored secret: the id-token is sent as a
bearer to `POST /score`, which the server authorizes by the token's `repository_owner`.
