# score-action

**Composite** GitHub Action that scores an **OWASP CTF** patch PR against the scorer image and
records the result on the leaderboard. Replaces the ~300-line `ctf-score.yml` each CTF fork
copy-pastes.

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

## Inputs

| input | required | default | description |
|-------|----------|---------|-------------|
| `target` | ✅ | | `juice-shop` \| `dvwa` \| `webgoat` \| `securityshepherd` \| `vampi` \| `vulnerableapp` |
| `app-url` | ✅ | | Base URL the scorer hits on `ctfnet` (e.g. `http://app`, `http://app:8080/WebGoat`) |
| `id-token` | ✅ | | OIDC id-token the leaderboard authorizes — the consumer mints it (audience `ctf-score`) |
| `github-token` | | `${{ github.token }}` | Token to log in to GHCR (pull the internal scorer image) |
| `score-image` | | `ghcr.io/owasp-ctf/score:latest` | Scorer image to pull + run |

## Required job permissions

```yaml
permissions:
  contents: read       # checkout the PR head to build it
  packages: read       # docker login + pull the internal scorer image
  id-token: write      # mint the OIDC id-token the leaderboard authorizes
  pull-requests: write # the result comment
```

## Why composite (not a container action)

A container action's image is pulled by GitHub **anonymously**, so an internal image `401`s — and
the scorer image bakes the rubric, so it must stay internal. A composite action runs on the host,
so it can `docker login` and pull it. The PR's code only ever runs inside containers on the
`--internal` `ctfnet` network, never on the host, so it can't read the id-token or `GITHUB_TOKEN`.
