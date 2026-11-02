#!/bin/sh
# Test suite. Never touches the network or your real credentials.
#   tests/run.sh [shell-command ...]     e.g. tests/run.sh dash "busybox sh"
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin/aiquota
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
TAB=$(printf '\t')
pass=0 fail=0

mkdir "$WORK/path"
cp "$ROOT/tests/fake-curl" "$WORK/path/curl"
export PATH="$WORK/path:$PATH" FAKE_FIXTURES="$ROOT/tests/fixtures" TERM=xterm
export LC_ALL=C AIQUOTA_TTL=300
unset NO_COLOR AIQUOTA_DISPLAY XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME CLAUDE_CONFIG_DIR CODEX_HOME ZDOTDIR LOCALAPPDATA 2>/dev/null

ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); printf '  FAIL [%s] %s\n' "$SH" "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
has() { case $2 in *"$3"*) ok ;; *) ko "$1: expected '$3'" "$2" ;; esac; }
hasnt() { case $2 in *"$3"*) ko "$1: unexpected '$3'" "$2" ;; *) ok ;; esac; }
eq() { [ "$2" = "$3" ] && ok || ko "$1: expected '$3', got '$2'"; }

fresh() {
	HOME=$WORK/home
	rm -rf "$HOME"
	mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.gemini" "$HOME/.config/github-copilot" \
		"$HOME/.config/manicode" "$HOME/.local/share/opencode"
	export HOME FAKE_LOG="$WORK/log"
	rm -f "$WORK"/log.*
	unset FAKE_CLAUDE FAKE_CODEX FAKE_GEMINI FAKE_COPILOT FAKE_STATUS 2>/dev/null
	cat >"$HOME/.claude/.credentials.json" <<-X
	{"claudeAiOauth":{"accessToken":"CLAUDE_SECRET","refreshToken":"r","expiresAt":4000000000000,"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}
	X
	echo '{"auth_mode":"chatgpt","tokens":{"access_token":"CODEX_SECRET","account_id":"acct-1"}}' >"$HOME/.codex/auth.json"
	echo '{"access_token":"ya29.GEMINI_SECRET","expiry_date":4000000000000}' >"$HOME/.gemini/oauth_creds.json"
	echo '{"github.com:Iv1":{"user":"u","oauth_token":"ghu_COPILOT_SECRET","githubAppId":"Iv1"}}' >"$HOME/.config/github-copilot/apps.json"
	echo '{"opencode":{"type":"api","key":"ZEN_SECRET"},"opencode-go":{"type":"api","key":"GO_SECRET"}}' >"$HOME/.local/share/opencode/auth.json"
	echo '{"default":{"id":"1","authToken":"FREEBUFF_SECRET"}}' >"$HOME/.config/manicode/credentials.json"
}

aq() { $SH "$BIN" "$@" 2>&1; }

suite() {
	fresh
	out=$(aq) ; eq "no accounts exits 2" "$?" 2
	has "no accounts explains" "$out" "aiquota install --display="
	out=$(aq --display=claud); eq "typo exits 2" "$?" 2
	has "typo named" "$out" "'claud'"

	fresh
	out=$(aq --display=claude); has "claude plan" "$out" "Max 5x"
	has "claude 5h" "$out" "75%"; has "claude 7d rounds" "$out" "30%"
	win=$(grep "^win${TAB}5h" "$HOME/.cache/aiquota/claude.tsv" | cut -f4)
	eq "offset dates" "$win" 4070908800

	fresh
	out=$(aq --display=codex); has "codex plan" "$out" "Plus"
	has "codex window from seconds" "$out" "5h"; has "codex left" "$out" "12%"; has "codex 7d" "$out" "60%"

	fresh; out=$(aq --display=gemini)
	has "gemini tier" "$out" "Gemini Code Assist Standard"
	has "gemini lowest pro" "$out" "50%"; has "gemini flash" "$out" "100%"
	fresh; FAKE_GEMINI=gemini-load-consumer; export FAKE_GEMINI; out=$(aq --display=gemini)
	has "gemini consumer tier" "$out" "no flat subscription"

	fresh; out=$(aq --display=copilot)
	has "copilot premium" "$out" "premium"; has "copilot left" "$out" "10%"
	hasnt "copilot unlimited chat" "$out" "chat"
	fresh; FAKE_COPILOT=copilot-none; export FAKE_COPILOT; out=$(aq --display=copilot)
	has "copilot no access" "$out" "no flat subscription"

	fresh; out=$(aq --display=opencode)
	has "opencode 5h" "$out" "88%"; has "opencode month" "$out" "20%"
	grep -q GO_SECRET "$FAKE_LOG.stdin" && ok || ko "opencode uses Go key"
	grep -q ZEN_SECRET "$FAKE_LOG.stdin" && ko "metered Zen key was sent" || ok

	fresh; out=$(aq --display=freebuff); has "freebuff left" "$out" "75%"; has "freebuff plan" "$out" "Free"

	# Flat subscriptions only.
	fresh; echo '{"auth_mode":"apikey","OPENAI_API_KEY":"k"}' >"$HOME/.codex/auth.json"
	out=$(aq --display=codex); has "api key hidden" "$out" "no flat subscription"
	[ -e "$FAKE_LOG.argv" ] && ko "api key caused a request" || ok
	fresh; FAKE_CODEX=codex-metered; export FAKE_CODEX; out=$(aq --display=codex)
	has "metered plan hidden" "$out" "no flat subscription"
	fresh; rm "$HOME/.claude/.credentials.json"; out=$(PATH="$WORK/path:$PATH" aq --display=claude)
	has "no credentials" "$out" "no flat subscription"

	# Order and selection.
	fresh; aq --display=freebuff,claude,codex, >/dev/null
	out=$(aq --display=freebuff,claude,codex, line --plain)
	eq "windows are grouped" "$(printf '%s' "$out" | sed 's/ | .*//')" "Freebuff Free [day 75%]"
	case $out in Freebuff*Claude*ChatGPT*) ok ;; *) ko "order kept" "$out" ;; esac
	hasnt "unselected not shown" "$out" "OpenCode"
	grep -q GO_SECRET "$FAKE_LOG.stdin" && ko "unselected account was queried" || ok
	title=$(cat "$HOME/.cache/aiquota/title")
	case $title in "Freebuff 75% | Claude 30% "*" | ChatGPT 12% "*) ok ;; *) ko "title is short, with the tightest window" "$title" ;; esac
	hasnt "title has no plan" "$title" "Max 5x"
	hasnt "no reset above half" "$title" "Freebuff 75% 2"

	# Secrets.
	fresh; aq --display=claude,codex,copilot,opencode,freebuff,gemini >/dev/null
	grep -q SECRET "$FAKE_LOG.argv" && ko "token on argv" "$(cat "$FAKE_LOG.argv")" || ok
	grep -q CLAUDE_SECRET "$FAKE_LOG.stdin" && ok || ko "token sent on stdin"
	grep -rq SECRET "$HOME/.cache/aiquota" && ko "token in cache" || ok
	grep -qE '(^| )(-L|--location)( |$)' "$FAKE_LOG.argv" && ko "follows redirects" || ok
	mode=$(ls -ld "$HOME/.cache/aiquota" | cut -c1-10); eq "cache is private" "$mode" drwx------

	# Hostile API output cannot reach the terminal.
	fresh; FAKE_CODEX=codex-evil; export FAKE_CODEX; out=$(aq --display=codex)
	esc=$(printf '\033'); bel=$(printf '\007')
	hasnt "ESC stripped" "$(cat "$HOME/.cache/aiquota/codex.tsv")" "$esc"
	hasnt "BEL stripped" "$(cat "$HOME/.cache/aiquota/codex.tsv")" "$bel"
	hasnt "dollar stripped" "$(cat "$HOME/.cache/aiquota/title")" '$'

	# Failures keep the last known values, marked approximate.
	fresh; aq --display=claude >/dev/null
	FAKE_STATUS=000; export FAKE_STATUS
	out=$(aq --display=claude refresh --force; aq --display=claude line --plain)
	has "offline keeps values" "$out" "~75%"
	out=$(aq --display=claude); has "offline explained" "$out" "offline"
	FAKE_STATUS=401; out=$(aq --display=claude refresh --force; aq --display=claude); has "401 explained" "$out" "open claude once"
	unset FAKE_STATUS
	fresh; aq --display=claude >/dev/null
	echo '{"claudeAiOauth":{"accessToken":"t","expiresAt":1000,"subscriptionType":"pro"}}' >"$HOME/.claude/.credentials.json"
	rm -f "$FAKE_LOG.argv"; out=$(aq --display=claude refresh --force; aq --display=claude line --plain)
	has "expired keeps values" "$out" "~75%"; has "expired plan" "$out" "Claude Pro"
	[ -e "$FAKE_LOG.argv" ] && ko "expired token was sent" || ok

	# A window that reset since the last look is shown as full, but approximate.
	fresh; aq --display=claude >/dev/null
	sed "s/^\(win${TAB}5h${TAB}[^$TAB]*${TAB}\).*/\11000/" "$HOME/.cache/aiquota/claude.tsv" >"$WORK/c" && cat "$WORK/c" >"$HOME/.cache/aiquota/claude.tsv"
	out=$(aq --display=claude line --plain); has "elapsed window" "$out" "5h ~100%"

	# TTL: a fresh cache means no network.
	fresh; aq --display=claude >/dev/null; rm -f "$FAKE_LOG.argv"; aq --display=claude >/dev/null
	[ -e "$FAKE_LOG.argv" ] && ko "fresh cache refetched" || ok

	# Background refresh returns at once and cleans up.
	fresh; AIQUOTA_DISPLAY=claude; export AIQUOTA_DISPLAY; aq refresh --background >/dev/null
	i=0; while [ "$i" -lt 50 ] && { [ ! -f "$HOME/.cache/aiquota/title" ] || [ -d "$HOME/.cache/aiquota/lock" ]; }; do sleep 0.1; i=$((i + 1)); done
	[ -f "$HOME/.cache/aiquota/title" ] && ok || ko "background wrote title"
	[ -d "$HOME/.cache/aiquota/lock" ] && ko "lock left behind" || ok
	unset AIQUOTA_DISPLAY

	# Rendering options.
	fresh; aq --display=claude >/dev/null
	hasnt "no color when piped" "$(aq --display=claude line)" "$esc"
	out=$(LC_ALL=C.UTF-8 aq --display=claude); has "unicode bars" "$out" "$(printf '\342\226\210')"
	out=$(LC_ALL=C aq --display=claude); has "ascii fallback" "$out" "####"

	# Install: idempotent, replaces the old line, keeps symlinks and content.
	fresh; echo 'alias ll=ls' >"$HOME/real_rc"; ln -s "$HOME/real_rc" "$HOME/.bashrc"
	aq --display=claude install bash >/dev/null; aq --display=codex,claude install bash >/dev/null
	[ -L "$HOME/.bashrc" ] && ok || ko "symlink kept"
	grep -q 'alias ll=ls' "$HOME/.bashrc" && ok || ko "content kept"
	eq "one line only" "$(grep -c 'init bash' "$HOME/.bashrc")" 1
	grep -q -- '--display=codex,claude' "$HOME/.bashrc" && ok || ko "line updated"
	out=$(aq install bash); has "install needs accounts" "$out" "choose your accounts"
	aq --display=claude --no-blank-line install bash >/dev/null
	grep -q -- '--display=claude --no-blank-line)"$' "$HOME/.bashrc" && ok || ko "install keeps --no-blank-line"
	eq "still one line" "$(grep -c 'init bash' "$HOME/.bashrc")" 1
	aq --display=claude install bash >/dev/null
	grep -q -- 'no-blank-line' "$HOME/.bashrc" && ko "install should drop --no-blank-line" || ok

	# The empty line after the band.
	fresh; aq --display=claude,codex >/dev/null
	for shell_name in bash zsh fish sh; do
		has "$shell_name hook has blank line" "$(aq init "$shell_name" --display=claude)" "line --blank-line"
		hasnt "$shell_name hook without blank line" "$(aq init "$shell_name" --display=claude --no-blank-line)" "--blank-line"
	done
	eq "blank line printed" "$(aq --display=claude line --blank-line | wc -l | tr -d ' ')" 2
	eq "no blank line by default" "$(aq --display=claude line | wc -l | tr -d ' ')" 1
	fresh; FAKE_COPILOT=copilot-none; export FAKE_COPILOT; aq --display=copilot >/dev/null
	eq "no blank line without a band" "$(aq --display=copilot line --blank-line | wc -l | tr -d ' ')" 0
	unset FAKE_COPILOT

	fresh; echo 'alias ll=ls' >"$HOME/.bashrc"
	aq --display=claude install fish >/dev/null
	grep -q 'init fish --display=claude | source' "$HOME/.config/fish/config.fish" && ok || ko "fish line"
}

# Interactive hooks, in a real pty. util-linux `script` only: skipped elsewhere.
hook_test() {
	name=$1 cmdline=$2 file=$3 snippet=$4
	command -v "$name" >/dev/null 2>&1 || { echo "  skip hook: $name not found"; return; }
	SH=dash
	fresh; aq --display=claude >/dev/null
	mkdir -p "$(dirname "$file")"
	printf '%s\n' "$snippet" >"$file"
	raw=$(printf 'exit\n' | AIQUOTA_DISPLAY='' timeout 20 script -qec "$cmdline" /dev/null 2>&1)
	SH="hook $name"
	has "banner" "$raw" "Claude"
	has "title set" "$raw" ";Claude 30%"
}

if [ $# -eq 0 ]; then set -- dash "busybox sh" "bash --posix"; fi
for SH in "$@"; do
	case $SH in *busybox*) command -v busybox >/dev/null 2>&1 ;; *) command -v "${SH%% *}" >/dev/null 2>&1 ;; esac || { echo "skip: $SH"; continue; }
	echo "== $SH"
	suite
done

if script -qec true /dev/null >/dev/null 2>&1; then
	echo "== interactive hooks"
	SH=dash
	# Ubuntu's default prompt rewrites the title on every prompt: we must come after it.
	hook_test bash "bash --rcfile $WORK/home/.bashrc -i" "$WORK/home/.bashrc" \
"PS1='\\[\\e]0;user@host: \\w\\a\\]\\u@\\h:\\w\\$ '
eval \"\$($BIN init bash --display=claude)\""
	last=$(printf '%s' "$raw" | LC_ALL=C sed 's/\x1b]/\n&/g' | grep -a "^$(printf '\033')]" | tail -1)
	has "bash: last title is ours" "$last" "Claude 30%"
	after=$(printf '%s\n' "$raw" | LC_ALL=C sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' | awk '/Claude Max 5x \[5h/ && !done { getline x; print "[" x "]"; done = 1 }')
	eq "bash: empty line before the first prompt" "$after" "[]"
	hook_test zsh "zsh -i" "$WORK/home/.zshrc" "eval \"\$($BIN init zsh --display=claude)\""
	hook_test fish "fish -i" "$WORK/home/.config/fish/config.fish" "$BIN init fish --display=claude | source"
	hook_test dash "env ENV=$WORK/home/env dash -i" "$WORK/home/env" "eval \"\$($BIN init sh --display=claude)\""
	hook_test mksh "env ENV=$WORK/home/env mksh -i" "$WORK/home/env" "eval \"\$($BIN init mksh --display=claude)\""
fi

if script -qec true /dev/null >/dev/null 2>&1 && LC_ALL=C.UTF-8 awk 'BEGIN { exit 0 }'; then
	echo "== banner band"
	SH=dash
	fresh
	band() { # columns, TERM, locale, extra env
		env TERM="$2" LC_ALL="$3" $4 script -qec "stty cols $1; dash $BIN --display=freebuff,claude,codex line" /dev/null </dev/null | tr -d '\r'
	}
	width() { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | LC_ALL=C.UTF-8 awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }'; }
	aq --display=freebuff,claude,codex >/dev/null
	out=$(band 130 xterm-256color C.UTF-8 A=1)
	has "grouped in the band" "$(printf '%s' "$out" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g')" "[5h 75%] [7d 30% "
	has "green dot" "$out" "38;5;46m"; has "yellow dot" "$out" "38;5;220m"; has "red dot" "$out" "38;5;203m"
	has "dot glyph" "$out" "$(printf '\342\227\217')"
	eq "uniform background" "$(printf '%s' "$out" | grep -ao '48;5;[0-9]*' | sort -u)" "48;5;236"
	hasnt "no gauge" "$out" "$(printf '\342\226')"
	has "tall separator" "$out" "$(printf '\342\224\203')"
	has "plan shown" "$out" "Max 5x"
	has "right label with room" "$out" "AIQuota"
	hasnt "no label without room" "$(band 124 xterm-256color C.UTF-8 A=1)" "AIQuota"
	has "plan still fits" "$(band 124 xterm-256color C.UTF-8 A=1)" "Max 5x"
	has "reset on low window" "$out" "$(printf '\342\206\273')"
	eq "fills the width" "$(printf '%s\n' "$out" | width)" 129
	eq "one row" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
	out=$(band 110 xterm-256color C.UTF-8 A=1); hasnt "compact drops plan" "$out" "Max 5x"
	eq "compact one row" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
	out=$(band 40 xterm-256color C.UTF-8 A=1); eq "stacks when narrow" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 3
	has "stack is complete" "$out" "Max 5x"
	out=$(band 120 xterm C.UTF-8 A=1); has "16 colors" "$out" "40;92m"; hasnt "no 256 on 16" "$out" "48;5"
	out=$(band 120 xterm-256color C A=1); has "ascii separator" "$out" "|"
	case $out in *[!\ -~]*) non=$(printf '%s' "$out" | LC_ALL=C tr -d '\33\12\40-\176' | wc -c | tr -d ' '); eq "pure ascii" "$non" 0 ;; esac
	out=$(band 120 xterm-256color C.UTF-8 NO_COLOR=1); hasnt "NO_COLOR" "$out" "$(printf '\033')"
fi

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
