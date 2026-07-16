# score-action

Docker **container** GitHub Action that scores an **OWASP CTF** patch PR against the scorer
image and records the result on the leaderboard.

It replaces the ~300 lines of near-identical YAML that every CTF fork used to copy-paste.
The action **is** the scorer image (`docker://ghcr.io/OWASP-CTF/score:latest`, org-internal),
so there's no separate login/pull — its entrypoint runs *inside* the image, which already
ships the rubric, the `score` binary, node, curl, and the docker CLI. A consumer only supplies
the one app-specific part — **build + boot the PR's app** — via the `run:` input.

```yaml
- name: Score + record
  uses: OWASP-CTF/score-action@main
  with:
    target: dvwa
    app-url: http://app
    run: |
      docker build -t ctf-app:pr .
      docker network create --internal "$NETWORK"
      docker run -d --name app --network "$NETWORK" ctf-app:pr
      # ...wait for health...
```

## What it does (one container, in order)

1. Runs your `run:` setup on the **host** docker daemon (the socket is bind-mounted into
   container actions) — build + boot the PR app on `network`.
2. Attaches **this** container to `network` so the in-process scorer can reach the app
   (which sits on an `--internal`, internet-less network).
3. Scores the running app with the embedded rubric (`--target <target> --url <app-url>`),
   producing the `ctf-score.json` sidecar. The rubric is baked in — no answer key is checked out.
4. Mints the job's GitHub **OIDC id-token** and `POST`s the result to the scoring API. No
   stored secret: the server authorizes the run by the token's `repository_owner`.
5. Upserts a single result comment on the PR (recorded / no-points-yet / did-not-complete).

## Inputs

| input | required | default | description |
|-------|----------|---------|-------------|
| `target` | ✅ | | `juice-shop` \| `dvwa` \| `webgoat` \| `securityshepherd` \| `vampi` \| `vulnerableapp` |
| `app-url` | ✅ | | Base URL the scorer hits, reachable on `ctfnet` (e.g. `http://app`, `http://app:8080/WebGoat`) |
| `run` | | | App-specific setup (bash) run **before** scoring: build the PR image, create `ctfnet`, boot the app + deps, wait for health. Runs inside the action container, drives the host daemon via the mounted socket. `$SCORER_IMAGE` and `$NETWORK` are exported. Trusted consumer YAML — docker build/run PR code only, never execute it directly |

Everything else is hardcoded (one CTF = one leaderboard + one scorer): network `ctfnet`,
image `ghcr.io/OWASP-CTF/score:latest`, API `https://api.ctf.owasp.org`, audience `ctf-score`,
leaderboard `https://ctf.owasp.org/leaderboard`. The PR-comment token comes from the caller's
`${{ github.token }}` automatically (needs `pull-requests: write`).

## Outputs

| output | description |
|--------|-------------|
| `open` | Challenges still open (0 = all patched) |
| `recorded` | `'true'` if solves were sent to the leaderboard |

## Required job permissions

```yaml
permissions:
  contents: read       # checkout the PR head to build it
  packages: read       # runner pulls the org-internal scorer/action image
  id-token: write      # mint the OIDC token POST /score authorizes
  pull-requests: write # the result comment
```

## Security model

The action runs as **one step (one container)**, so its job holds `id-token: write` and
`pull-requests: write` next to the untrusted `docker build`. This is safe **only because the
PR's code never runs on the runner host** — it is exclusively `docker build`/`docker run`
into containers on an `--internal` (internet-less) network, so it cannot read the OIDC request
token or `GITHUB_TOKEN`. The action container attaches to that internal network only to make
client HTTP requests to the app — it runs no inbound service and does not route the app's
traffic out, so the app stays internet-less.

> **Do not** add a consumer step (or `run:` line) that executes PR-controlled code directly
> (for example `npm run` / `mvn` from the PR checkout, outside a container).

The leaderboard write carries **no secret**: the id-token is minted per-run (audience
`ctf-score`) and sent as a bearer to `POST /score`, which the server authorizes by
`repository_owner`. Author / PR / SHA travel in the request body from the trusted
`github.event` context, not from PR code.
