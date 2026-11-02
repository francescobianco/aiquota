# Contributing

## The one rule about scope

AIQuota is for **flat subscriptions only**: quota measured as time and resources left until the next
reset. Pay-per-token and metered billing are out of scope, and a provider must report `RC_HIDDEN` when
it finds them (an API key, a usage-based plan). This keeps the tool small and the question it answers
simple: *which of the agents I already pay for can I still use right now?*

## Code rules

- POSIX `sh`, `awk` and `curl` only. No bashisms, no `local`, no `jq`, no extra dependencies.
- Don't rely on 64-bit shell arithmetic: some shells have 32-bit integers. Use `awk` for big numbers.
- Don't use `date -d`, `sed -i` or other flags that differ between GNU and BSD.
- Shell startup must never wait for the network. Hooks read the cache and refresh in the background.

## Adding an account

1. Write `provider_<name>()` in `bin/aiquota`, using the `name() ( ... )` subshell form.
2. Add `<name>` to `KNOWN_ACCOUNTS`, and its display name to `pretty_name()` in the renderer.
3. Add fixtures to `tests/fixtures/`, a URL case to `tests/fake-curl`, and cases to `tests/run.sh`.
4. Add a row to the table in `README.md`, and say honestly how it was verified.

A provider prints `emit_plan "Name"` and `emit_win <label> <percent-used> <reset-epoch>`, and returns:

| Code | Meaning |
| --- | --- |
| `RC_OK` | Fresh numbers |
| `RC_HIDDEN` | Not logged in, or not a flat subscription |
| `RC_AUTH` | Login expired. `emit_msg` tells the user what to do |
| `RC_ERROR` | Network or API failure. The last known numbers stay on screen, marked `~` |

A provider must:

- **Only read credentials.** Never refresh them or write them back: refresh tokens can rotate, and
  using one could log the user out of their agent.
- **Pass tokens through `http`'s stdin**, after checking them with `safe_token`, so they stay out of `ps`.
- **Make read-only requests** that don't consume quota or start a session.

## Testing

```sh
tests/run.sh                          # dash, busybox sh, bash --posix
tests/run.sh mksh "bash --posix"      # the shells you choose
shellcheck -s sh -S warning bin/aiquota install.sh tests/run.sh tests/fake-curl
```

The tests use a fake `curl` and a temporary `$HOME`, so they never touch the network or your credentials.
Hook tests run in a real pty for each of bash, zsh, fish, dash and mksh that is installed.
