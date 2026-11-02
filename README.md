# AIQuota

[![CI](https://github.com/francescobianco/aiquota/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/francescobianco/aiquota/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/francescobianco/aiquota)](LICENSE)
[![Shell: POSIX sh](https://img.shields.io/badge/shell-POSIX%20sh-4EAA25?logo=gnubash&logoColor=white)](bin/aiquota)
[![Lint: ShellCheck](https://img.shields.io/badge/lint-ShellCheck-4B8BBE)](https://www.shellcheck.net/)
[![Platform: Linux | macOS](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-555)](#compatibility)
[![Needs: awk + curl](https://img.shields.io/badge/needs-awk%20%2B%20curl-informational)](#compatibility)

**See what's left of your AI subscriptions every time you open a terminal.**

<p align="center">
  <img src="docs/demo.svg" alt="A terminal whose title bar shows ChatGPT Plus at 12%, Claude Max 5x at 92% and Freebuff at 100%. A full-width grey band shows the same accounts, with a red dot next to ChatGPT and green dots next to the others. The aiquota command lists each subscription with bars and reset times, and the user opens Claude." width="100%">
</p>

ChatGPT nearly out until 3 pm? Open Claude instead. AIQuota tells you before you start the coding agent,
not halfway through a task.

- **A status band when a terminal opens**: one section per account, with a green, yellow or red dot showing how close it is to its limit
- **In the title bar**, always visible and refreshed in the background
- **Your accounts, your order**: only the ones you list are shown or queried
- **Instant**: opening a terminal never waits for the network
- **Tiny and portable**: one POSIX `sh` script that needs only `awk` and `curl`

## Install

List your accounts in the order you want them:

```sh
curl -fsSL https://raw.githubusercontent.com/francescobianco/aiquota/main/install.sh | sh -s -- --display=codex,claude,copilot,freebuff
```

Then open a new terminal. This installs the script to `~/.local/bin` and adds one line to your shell's
startup file. To change the accounts or their order, run it again; the line is replaced, not duplicated:

```sh
aiquota install --display=claude,codex
```

Prefer to do it by hand? Put `bin/aiquota` in your `PATH` and add this as the **last** line of your startup file:

| Shell | File | Line |
| --- | --- | --- |
| bash | `~/.bashrc` | `eval "$(aiquota init bash --display=codex,claude)"` |
| zsh | `~/.zshrc` | `eval "$(aiquota init zsh --display=codex,claude)"` |
| fish | `~/.config/fish/config.fish` | `aiquota init fish --display=codex,claude \| source` |
| dash, ash, sh, yash | `~/.profile` | `eval "$(aiquota init sh --display=codex,claude)"` |
| ksh, mksh | `~/.kshrc` | `eval "$(aiquota init ksh --display=codex,claude)"` |

## Usage

| Command | What it does |
| --- | --- |
| `aiquota` | Full view with bars and reset times, refreshed if stale |
| `aiquota line` | The color band from the cache, the same one printed when a terminal opens |
| `aiquota line --plain` | The same information as plain text, for status bars |
| `aiquota title` | Writes the summary to the title bar |
| `aiquota refresh --force` | Queries everything now |
| `aiquota --display=claude,codex` | Overrides the configured accounts for one command |

### The band

```text
 ● ChatGPT Plus [5h 12% ↻1h48m] [7d 61%] ┃ ● Claude Max 5x [5h 99%] [7d 92%] ┃ ● Freebuff Free [day 100%]
```

- **The dot** is a traffic light for the account's tightest window: green from 50% left, yellow from 20%, red below that. Grey means no data, for example after a login expires.
- **`[5h 12%]`** is one window and the share left. An account can have several.
- **`↻1h48m`** is the time until that window resets, shown when less than half is left.

An empty line separates the band from your first prompt. To remove it, add `--no-blank-line` to `aiquota install` or to your startup line.

On narrower terminals the band drops the plan names. If it still doesn't fit, each account gets its own row. It uses 256 colors where available and falls back to 16 colors and plain ASCII.

### The title bar

Title bars only show plain text, so there's no color here. For each account you get the window that will stop you first and the time until it resets.

A `~` before a value means it may be out of date: the login expired, the network failed, or the window
has reset since the last successful check.

To use it in a tmux status bar:

```tmux
set -g status-right '#(aiquota line --plain --display=codex,claude)'
```

## Accounts

| `--display` name | Subscription | Windows | Verified against |
| --- | --- | --- | --- |
| `claude` | Claude Pro, Max, Team | 5h, 7d | Live API |
| `codex` | ChatGPT plans, through Codex | 5h, 7d | Live API |
| `freebuff` | Freebuff daily allowance | day | Live API |
| `copilot` | GitHub Copilot | premium, chat | Live endpoint without a subscription, and test fixtures for the quota fields |
| `opencode` | OpenCode Go | 5h, 7d, monthly | Third-party client's schema and test fixtures |
| `gemini` | Gemini Code Assist Standard, Enterprise | pro, flash | Third-party docs and test fixtures |

> [!NOTE]
> These are mostly **undocumented endpoints**, the same ones the agents use for their own usage screens.
> They can change without notice. When one does, AIQuota keeps showing the last known values, marked `~`.

### Flat subscriptions only

This is a deliberate limit, not a missing feature. AIQuota answers one question: *which of the agents I
already pay for can I still use right now?* That means quota measured in time and resources until the next
reset. API keys and metered, usage-based plans are never queried or shown, even if they are on your machine.

## Good to know

**Logins expire while you're away.** AIQuota reads each agent's credentials but never refreshes them, because
refresh tokens can rotate and using one could log you out of the agent. So after a long break an account may
show `login expired`, or its last known values marked `~`, until you next open that agent. For example, the
Claude access token lasts for hours and the ChatGPT one for days.

**It replaces your title.** If your title bar normally shows the current directory, that's what you give up.
Set `AIQUOTA_TITLE=0` before the startup line to keep your title and only get the band when a terminal opens.

**IDE terminals show the band, not the title.** The band appears each time a terminal opens, in any terminal.
JetBrains IDEs use their own fixed tab names, so the title summary doesn't appear there. In VS Code, set
`"terminal.integrated.tabs.title": "${sequence}"` to see it in the tab. In either IDE, run `aiquota` for the full view.

**Gemini is limited by Google.** Since June 2026, Gemini CLI login has only been served for Standard and
Enterprise seats, so personal accounts show `no flat subscription found`.

## Settings

Set these as environment variables before the startup line, or in `~/.config/aiquota/config`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `AIQUOTA_TTL` | `300` | Seconds between refreshes |
| `AIQUOTA_TIMEOUT` | `8` | Seconds allowed per request |
| `AIQUOTA_BANNER` | `1` | Set to `0` for no band when a terminal opens |
| `AIQUOTA_TITLE` | `1` | Set to `0` to leave the title bar alone |
| `AIQUOTA_ASCII` | unset | Set to `1` for plain ASCII output |
| `NO_COLOR` | unset | Set to anything to turn colors off |

## Privacy and security

AIQuota has no server and no telemetry. Each token goes only to the service that issued it.

- Credentials are read-only, and are never copied to the cache or passed on a command line.
- The cache in `~/.cache/aiquota` holds only plan names, percentages and times, and only you can read it.
- Text from the network is stripped of control characters before it can reach your terminal.
- Redirects are not followed, so a token can't be forwarded to another host.

## Compatibility

Runs anywhere with a POSIX shell, `awk` and `curl`.

| | Status |
| --- | --- |
| Script | Tested on dash, BusyBox ash, `bash --posix` and mksh |
| Startup hooks | Tested in a real terminal session on bash, zsh, fish, dash and mksh |
| OS | Tested on Linux. macOS runs in CI, and also reads Claude's login from the Keychain |
| Windows | Should work in WSL or Git Bash, but isn't tested yet |

## Contributing

New accounts are welcome as long as they are flat subscriptions. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
