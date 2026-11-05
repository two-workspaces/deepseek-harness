#!/bin/bash
set -euo pipefail

INTERNAL_PORT=3082

: "${WEB_USER:=admin}"
: "${WEB_PASSWORD:?WEB_PASSWORD is required: this page runs an agent with full access to the container}"

# An empty value outranks a key saved later in Settings > Models, so the save would look like it did nothing.
[ -n "${DEEPSEEK_API_KEY:-}" ] || unset DEEPSEEK_API_KEY
[ -n "${GH_TOKEN:-}" ] || unset GH_TOKEN

mkdir -p "$DSH_HOME" /data/workspace
chmod 700 "$DSH_HOME"
cd /data/workspace

# gh reads GH_TOKEN itself; this makes plain git clone and push use it too.
if [ -n "${GH_TOKEN:-}" ]; then
  gh auth setup-git || echo "==> gh could not set up git credentials; check GH_TOKEN" >&2
fi

# Hashed per boot so the variable stays plaintext and can be read back in Railway.
PASSWORD_HASH="$(caddy hash-password --plaintext "$WEB_PASSWORD")"

# The agent runs with full access to the container, so it doesn't get the password.
unset WEB_PASSWORD

TOKEN_FILE="$(mktemp)"
LOG_PIPE="$(mktemp -u)"
mkfifo "$LOG_PIPE"
# The login token goes to a file and never to the deploy logs.
gawk -v out="$TOKEN_FILE" '{
  if (match($0, /token=[A-Za-z0-9_-]+/)) {
    print substr($0, RSTART + 6, RLENGTH - 6) > out; close(out)
    gsub(/token=[A-Za-z0-9_-]+/, "token=[redacted]")
  }
  print; fflush()
}' < "$LOG_PIPE" &

dsh --profile web --no-open --host 127.0.0.1 --port "$INTERNAL_PORT" > "$LOG_PIPE" 2>&1 &
DSH_PID=$!
CADDY_PID=
trap 'kill "$DSH_PID" ${CADDY_PID:+"$CADDY_PID"} 2>/dev/null || true' TERM INT

# DSH answers 401 to anyone without its token, and that answer is what ready looks like.
echo "==> waiting for DSH on 127.0.0.1:${INTERNAL_PORT}"
ready=
for _ in $(seq 1 280); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${INTERNAL_PORT}/" || true)"
  if [ -s "$TOKEN_FILE" ] && [ "$code" = 401 ]; then ready=1; break; fi
  kill -0 "$DSH_PID" 2>/dev/null || { echo "FATAL: dsh exited during startup" >&2; exit 1; }
  sleep 1
done
[ -n "$ready" ] || { echo "FATAL: DSH did not answer (last status ${code:-none})" >&2; exit 1; }
DSH_TOKEN="$(cat "$TOKEN_FILE")"
rm -f "$TOKEN_FILE"

cat > /tmp/Caddyfile <<CADDY
{
	admin off
	auto_https off
	persist_config off
	servers {
		trusted_proxies static private_ranges
	}
}

(dsh) {
	reverse_proxy 127.0.0.1:${INTERNAL_PORT} {
		# DSH accepts only a loopback Host. With that rewritten, a browser Origin of the Railway
		# domain would no longer match it; an absent Origin is accepted.
		header_up Host 127.0.0.1:${INTERNAL_PORT}
		header_up -Origin
	}
}

:${PORT} {
	# route: Caddy would otherwise reorder these, and the checks must come before the proxy.
	route {
		# For Railway's healthcheck, which sends no password. Caddy only starts once DSH answers, and
		# the container exits if either dies, so answering at all means both are up.
		respond /healthz "ok" 200

		basic_auth {
			${WEB_USER} ${PASSWORD_HASH}
		}

		# Browsers attach a saved login to requests from any site, and stripping Origin below removes
		# the upstream check against that, so it is done here. This also covers WebSockets.
		@foreign expression "{http.request.header.Origin} != '' && {http.request.header.Origin} != 'https://' + {http.request.host}"
		respond @foreign "Cross-site request refused" 403

		# Past our login: hand the browser DSH's per-process token, which it trades for its own cookie.
		handle /__dsh_login {
			rewrite * /?token=${DSH_TOKEN}
			import dsh
		}

		handle / {
			reverse_proxy 127.0.0.1:${INTERNAL_PORT} {
				header_up Host 127.0.0.1:${INTERNAL_PORT}
				header_up -Origin
				@unauthenticated status 401
				handle_response @unauthenticated {
					header Location /__dsh_login
					respond 302
				}
			}
		}

		handle {
			import dsh
		}
	}
}
CADDY
chmod 600 /tmp/Caddyfile

echo "==> DSH is up on :${PORT}, login user ${WEB_USER}"
caddy run --config /tmp/Caddyfile --adapter caddyfile &
CADDY_PID=$!

# Railway counts the kernel's cache of files this container touched as its memory, and with no
# memory pressure it is never freed: one clone shows as hundreds of MB.
( while sleep 900; do nice -n 19 drop-file-cache /data /tmp /usr/local/lib/node_modules || true; done ) &

# Either half dying restarts the pair, so a live proxy never fronts a dead dsh.
status=0
wait -n "$DSH_PID" "$CADDY_PID" || status=$?
echo "==> a supervised process exited (status ${status}); shutting down"
kill "$DSH_PID" "$CADDY_PID" 2>/dev/null || true
wait "$DSH_PID" 2>/dev/null || true
exit "$status"
