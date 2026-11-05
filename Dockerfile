FROM node:24-bookworm-slim

# Caddy owns the public port: DSH refuses to bind anything but loopback and has no password login.
COPY --from=caddy:2.10 /usr/bin/caddy /usr/local/bin/caddy

# What a coding agent reaches for on a server: git and gh for repos, the build tools and Python for
# the project's own builds and tests, ripgrep and tmux for its shell work.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git git-lfs gawk jq less procps ripgrep tini tmux unzip \
      python3 build-essential \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# upgrade: npm @deepseek-ai/dsh
ARG DSH_VERSION=0.2.2-rc.1
RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" && npm cache clean --force

# DSH's web client turns its settings off unless the page's own hostname is loopback, so the Models
# page can't save a key from a real domain, and there is no setting for it. Our login is the boundary
# here, and the proxy already gives the server its loopback Host. The assert fails the build if an
# upgrade reshapes this line, rather than shipping an image with a dead Settings page.
RUN F=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/client.browser.js \
  && python3 - "$F" <<'PY'
import pathlib, sys
f = pathlib.Path(sys.argv[1])
gate = "isLoopback: transport?.ownsHost === true || pageLocation === void 0 || isLoopbackHostname(pageLocation.hostname)"
text = f.read_text()
assert text.count(gate) == 1, f"settings gate found {text.count(gate)} times"
f.write_text(text.replace(gate, "isLoopback: true"))
PY

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 drop-file-cache /usr/local/bin/drop-file-cache

ENV HOME=/data DSH_HOME=/data/.dsh DSH_TELEMETRY_DISABLED=true PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
