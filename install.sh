#!/bin/sh
# AIQuota installer. Copies one script to ~/.local/bin, then, if you pass
# --display, adds one line to your shell startup file.
#
#   curl -fsSL https://raw.githubusercontent.com/francescobianco/aiquota/main/install.sh | sh -s -- --display=codex,claude
#
# Environment: PREFIX (default ~/.local).
set -eu

url=https://raw.githubusercontent.com/francescobianco/aiquota/main/bin/aiquota
dir=${PREFIX:-$HOME/.local}/bin
mkdir -p "$dir"

source_dir=$(dirname "$0")
if [ -f "$source_dir/bin/aiquota" ]; then
	cp "$source_dir/bin/aiquota" "$dir/aiquota.tmp"
else
	command -v curl >/dev/null 2>&1 || {
		echo "aiquota: curl is required" >&2
		exit 1
	}
	curl -fsSL "$url" -o "$dir/aiquota.tmp"
fi
chmod 755 "$dir/aiquota.tmp"
mv -f "$dir/aiquota.tmp" "$dir/aiquota"
echo "Installed $dir/aiquota"

case :$PATH: in
*:"$dir":*) ;;
*) echo "Note: $dir is not in your PATH." ;;
esac

if [ $# -gt 0 ]; then
	PATH=$dir:$PATH exec "$dir/aiquota" install "$@"
fi
echo "Now choose your accounts, in the order you want them:"
echo "  aiquota install --display=codex,claude,copilot,freebuff"
