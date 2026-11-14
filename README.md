# claude-kilo

Run [Claude Code](https://code.claude.com) through [Kilo Gateway](https://kilo.ai/gateway): Claude and other vendors' models in the same Claude Code, billed to your personal Kilo account or to your company's Kilo organization.

```
claude-kilo  ->  LiteLLM on 127.0.0.1:4000  ->  Kilo Gateway  ->  Anthropic, OpenAI, Google, DeepSeek, Z.ai, Moonshot
```

- `claude-kilo` is a separate command. Your normal `claude` command and subscription stay untouched.
- Claude models go to Kilo's Anthropic-format endpoint, so prompt caching and thinking keep working.
- Other models go to Kilo's OpenAI-compatible endpoint; LiteLLM translates.
- Pick a model per role: main conversation, plan mode, background tasks, each subagent.
- On macOS and Linux desktops with systemd, the proxy can start at login, restart itself if it dies and reload when you edit its config.

## Personal or organization

|  | Personal | Organization |
| --- | --- | --- |
| Who pays | your Kilo balance | your company's Kilo organization |
| You need | a Kilo account with credits | membership in the organization and its ID |
| Install with | `./install.sh --personal` | `./install.sh --org <organization-id>` |
| Policies | none | the organization's model allow-list and per-user spend limits apply; admins see your usage |

In both cases the API key is your own: [app.kilo.ai](https://app.kilo.ai), switch to your personal account, Profile, bottom of the page. In organization mode every request carries `X-KiloCode-OrganizationId`; Kilo answers 403 if you are not a member, so a wrong ID never bills anyone else. The organization ID is the UUID in the dashboard URL when the organization is selected, or ask an admin.

## Requirements

- macOS or Linux; Linux autostart requires a systemd user session (standard on Arch, Ubuntu and CentOS/Fedora desktops)
- Claude Code (`claude --version`)
- Python 3.10 to 3.14, `curl`, `openssl`

## Install

```bash
git clone https://github.com/ktaraszk/claude-kilo.git ~/claude-kilo
cd ~/claude-kilo
./install.sh --personal
```

For company billing run `./install.sh --org <organization-id>` instead. The installer:

1. installs LiteLLM (pinned, `LITELLM_VERSION` to override) into `.venv`
2. asks for your Kilo API key with hidden input and stores it in `~/.config/claude-kilo/kilo.key` (mode 600), plus a random local master key
3. checks the key with one 1-token request (402 = no credits, 403 = not a member)
4. creates `config.yaml` and `claude-kilo.env` from the templates in `config/`
5. links `claude-kilo` into `~/.local/bin` (`CLAUDE_KILO_BIN_DIR` to change)
6. offers autostart on macOS and Linux

Re-run it any time: keys and config are kept. To switch between personal and organization billing, run it again with the other flag; the old `config.yaml` is backed up. Non-interactive: `KILO_API_KEY=... ./install.sh --org <organization-id> --autostart`.

## Use

```bash
claude-kilo
claude-kilo --continue
claude-kilo --resume
KILO_MODEL=claude-compat-glm-5.3 claude-kilo
claude-kilo --model opusplan
```

Inside a session, `/model opus`, `/model haiku` or `/model claude-compat-kimi-k3.1-pro` switch on the fly, and `/status` shows `127.0.0.1:4000` as the base URL. On exit Claude Code prints `claude-kilo --resume <id>`. Resume with `claude-kilo`, not plain `claude`: the session's model names only exist behind the proxy.

## Models

The default `config.yaml` exposes these models:

| Name in Claude Code | Kilo model | Route |
| --- | --- | --- |
| `claude-opus-5.5` | `anthropic/claude-opus-5.5` | Anthropic |
| `claude-sonnet-5.5` | `anthropic/claude-sonnet-5.5` | Anthropic |
| `claude-haiku-5.5` | `anthropic/claude-haiku-5.5` | Anthropic |
| `claude-compat-gpt-6.1-sol` | `openai/gpt-6.1-sol` | OpenAI-compatible |
| `claude-compat-gemini-4-carbon` | `google/gemini-4-carbon` | OpenAI-compatible |
| `claude-compat-kimi-k3.1-pro` | `moonshotai/kimi-k3.1-pro` | OpenAI-compatible |
| `claude-compat-glm-5.3` | `z-ai/glm-5.3` | OpenAI-compatible |
| `claude-compat-glm-5.3-flash` | `z-ai/glm-5.3-flash` | OpenAI-compatible |
| `claude-compat-deepseek-v4.1-flash-1017` | `deepseek/deepseek-v4.1-flash-1017` | OpenAI-compatible |

Claude Code asks for a model per role. `claude-kilo` maps each role to a name from `config.yaml`:

| Role | Default | Variable |
| --- | --- | --- |
| Main conversation | the sonnet slot | `KILO_MODEL` |
| Opus slot (`/model opus`, plan mode with `opusplan`) | `claude-opus-5.5` | `KILO_OPUS` |
| Sonnet slot | `claude-sonnet-5.5` | `KILO_SONNET` |
| Haiku slot (background tasks such as session titles) | `claude-haiku-5.5` | `KILO_HAIKU` |
| General-purpose subagents | the main model | `KILO_SUBAGENT` |

Set the variables per run (`KILO_HAIKU=claude-compat-glm-5.3-flash claude-kilo`) or permanently in `claude-kilo.env`; a variable set in your shell wins over the file.

### Add a model

Pick an ID from `https://ai-gateway.kilo.ai/api/v1/models` (no key needed; each entry also lists its hosting providers and `mayTrainOnYourPrompts`), then copy an existing entry in `config.yaml`:

- the `model_name` must contain `claude`, or the `/model` picker will not list it
- Claude models: `model: anthropic/<kilo id>` with `api_base: https://api.kilo.ai/api/gateway` and the `Authorization` header. The OpenAI route drops cache markers and every turn is billed at full price
- other models: `model: openai/<kilo id>` with `api_base: https://ai-gateway.kilo.ai/api/v1`
- organization mode: keep the `X-KiloCode-OrganizationId` header on every entry
- for a 1M-context model, add `[1m]` where you reference it from Claude Code (`KILO_MODEL='claude-compat-glm-5.3[1m]'`, or in `agents.json`); Claude Code otherwise assumes 200K for names it does not know

With autostart the proxy reloads by itself; otherwise restart `bin/claude-kilo-proxy`.

## Subagents per task

```bash
cp config/agents.example.json agents.json
```

The example adds a `reviewer` on GPT 6.1 Sol and replaces the built-in `Explore` with GLM 5.3 Flash. Each `model` is a name from `config.yaml`. Only `claude-kilo` sessions load `agents.json`; your normal `claude` never sees these agents. A prompt that says "read-only" is not enforcement: only the `tools` list is.

## Autostart and reload

`./install.sh --autostart` installs autostart for your user, not a system-wide root service. The proxy starts at login and restarts within 5 seconds if it dies. A second job watches `config.yaml` and `claude-kilo.env`, validates the YAML, then restarts the proxy. A broken file is logged and the running proxy is left alone.

On macOS these are the `claude-kilo.proxy` and `claude-kilo.reload` LaunchAgents:

```bash
launchctl kickstart -k gui/$(id -u)/claude-kilo.proxy
launchctl print gui/$(id -u)/claude-kilo.proxy | grep -E 'state|pid'
```

On Linux these are `claude-kilo.proxy.service` and `claude-kilo.reload.path` in `${XDG_CONFIG_HOME:-~/.config}/systemd/user`:

```bash
systemctl --user restart claude-kilo.proxy.service
systemctl --user status claude-kilo.proxy.service claude-kilo.reload.path
```

Logs for both platforms are in `logs/proxy.log` and `logs/reload.log`:

```bash
tail -f logs/proxy.log logs/reload.log
```

The key files are not watched: after replacing your Kilo key, restart the proxy with the command above. macOS may show a "Background Items Added" notice; if you switch the items off under System Settings, General, Login Items, the proxy will not start at login. On Linux the user units start with your login session; root, `sudo`, and enabling lingering are not required. Without autostart, run `bin/claude-kilo-proxy` in a terminal and keep it open.

## Check it works

```bash
bin/claude-kilo-smoke claude-haiku-5.5
```

It runs a short Claude Code task (write a file, run it, report the output) in a throwaway directory and config, then prints PASS or FAIL with token counts. Claude models should show a non-zero `cache_read`.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `claude-kilo: no proxy on 127.0.0.1:4000` | the proxy is not running | `bin/claude-kilo-proxy`, or `./install.sh --autostart` |
| `ECONNREFUSED` inside a session | the proxy died mid-session | autostart restarts it; otherwise start it and resend |
| HTTP 402 Credits Required | the billed account has no credits | add credits, or check you installed the right mode |
| HTTP 403 not a member | wrong organization ID | fix `KILO_ORG_ID` in `claude-kilo.env` |
| HTTP 401 | the Kilo key is wrong or revoked | replace `~/.config/claude-kilo/kilo.key`, then restart the proxy |
| no resume hint on exit | the session was not saved: you exited before the first message, or started it from inside another Claude Code session | send a message first; start it from a normal terminal |
| `cache_read` stays 0 on a Claude model | the entry uses the OpenAI route | switch it to the Anthropic route |
| the cost Claude Code shows looks wrong | Claude Code prices names it does not know at Anthropic rates | trust Kilo's usage page |

## Caveats

- Anthropic supports Claude Code with Claude models only. Other models work, but tool-use quality varies by model and nobody will support it when it breaks.
- Privacy: each session sends your `CLAUDE.md`, memory and the files Claude reads to the chosen model's provider. Check where a model is hosted before using it on client code.
- Kilo does not document its Anthropic-format endpoint. If it ever breaks, move the Claude entries to the OpenAI route and accept the lost caching.
- Avoid `kilo-auto/*` as a main model: it changes model per request, which breaks multi-turn tool use and caching. `kilo-auto/free` may log prompts.
- Remote Control and voice dictation do not work while a gateway credential is set.

## Uninstall

```bash
./uninstall.sh
```

It removes the LaunchAgents or systemd user units and the `claude-kilo` link, and keeps your config and keys; it prints where they are.

## License

MIT
