# Build the action image FROM the published scorer image (public). Everything is inherited:
# the `score` binary, node, the docker CLI, and the baked action entrypoints
# (pre-score.sh, score.sh, score-<target>-challenges.sh on PATH / /usr/local/lib/ctf).
#
# Using `image: Dockerfile` (vs `image: docker://…`) makes the runner BUILD the action image
# locally — the FROM pull uses the now-public base — instead of pulling a docker:// action image.
FROM ghcr.io/owasp-ctf/score:latest
