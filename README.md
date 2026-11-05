# Deploy and Host DeepSeek Harness on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/deepseek-harness?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=deepseek-harness)

DeepSeek Harness is DeepSeek's open-source coding agent. It reads and edits code, runs commands and works through tasks with you from a browser. This template runs its web UI as a Railway service behind a password, with sessions and repos kept on a volume.

This is a community template, not made or supported by DeepSeek.

## About Hosting DeepSeek Harness

The web UI refuses to listen on anything but loopback and logs in with a one-time token printed to the console, which doesn't suit a server. This template puts Caddy in front on Railway's public port. You sign in with `WEB_USER` and `WEB_PASSWORD`, and the proxy passes DSH's token on for you, so you never handle it and it never reaches the deploy logs.

Settings is usually disabled on any address other than localhost. The image patches that one check so the Models page works from your Railway domain, and the build fails if a new DSH version changes that code.

After deploying, open the service's domain and sign in. Set `DEEPSEEK_API_KEY`, or save a key under Settings > Models from the account menu at the bottom left. Then choose **Add workspace**, pick the `workspace` folder, and start a session. Without a key the UI opens but the agent can't answer. Model usage is billed by your provider, not by this template.

**The agent has full shell access to this container.** Anyone who has the password can run commands in it and read its variables, including `GH_TOKEN` and your API key. Use a long password and a token limited to the repos the agent should touch.

## Common Use Cases

- Run a coding agent that keeps working after you close your laptop
- Use the same agent and sessions from a phone, tablet or a second computer
- Give the agent its own machine to clone, build and test in, away from your own files

## Dependencies for DeepSeek Harness Hosting

- A DeepSeek API key or another model provider's key
- Optionally, a GitHub token for private repos and pushing

### Deployment Dependencies

- [DeepSeek Harness on GitHub](https://github.com/deepseek-ai/deepseek-harness)
- [DeepSeek API keys](https://platform.deepseek.com/api_keys)
- [GitHub fine-grained tokens](https://github.com/settings/personal-access-tokens)

### Implementation Details

- **Volume:** `/data` is the home directory. Sessions and settings live in `/data/.dsh`, and `/data/workspace` is there for your projects. All of it survives redeploys, including files the agent wrote.
- **Tools included:** git, git-lfs, `gh`, ripgrep, tmux, Python 3, Node.js 24 and build-essential. Packages the agent installs with `apt` go away on redeploy; anything under `/data` stays.
- **Memory:** a real project with builds and tests needs more than the 0.5 GB of Railway's Free plan. The UI itself runs in that, but expect the agent's builds to be killed there.
- **Other providers:** Settings > Models takes a custom Anthropic-compatible base URL and model names, or a provider from the built-in catalog under Add model provider.
- **Version:** pinned to a tested release, and upstream is still publishing release candidates, so expect its interface to change between updates.

## Why Deploy DeepSeek Harness on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying DeepSeek Harness on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
