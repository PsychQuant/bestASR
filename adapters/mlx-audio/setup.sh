#!/bin/bash
# Set up the mlx-audio external-engine adapter (#51, spec
# external-engine-protocol, design D3): everything lives under
# ~/.bestasr/adapters/mlx-audio/ — its own venv, its own wrapper — and
# bestASR's binary carries zero Python knowledge. Re-run to upgrade.
set -euo pipefail

DEST="$HOME/.bestasr/adapters/mlx-audio"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINES_JSON="$HOME/.bestasr/engines.json"

command -v python3 >/dev/null || { echo "✗ python3 not found" >&2; exit 1; }

echo "→ venv at $DEST/venv"
mkdir -p "$DEST"
if command -v uv >/dev/null 2>&1; then
  uv venv --quiet "$DEST/venv" 2>/dev/null || uv venv "$DEST/venv"
  VENV_PY="$DEST/venv/bin/python"
  # transformers pin: mlx_lm's string-key AutoTokenizer.register breaks on
  # transformers >= 4.54 ('str' has no __module__ — probed 2026-07-06).
  uv pip install --quiet --python "$VENV_PY" mlx-audio soundfile 'transformers<4.54'
else
  python3 -m venv "$DEST/venv"
  VENV_PY="$DEST/venv/bin/python"
  "$VENV_PY" -m pip install --quiet --upgrade pip
  "$VENV_PY" -m pip install --quiet mlx-audio soundfile 'transformers<4.54'
fi

cp "$SRC_DIR/bestasr-mlx-adapter.py" "$DEST/bestasr-mlx-adapter.py"

cat > "$DEST/run.sh" <<WRAPPER
#!/bin/bash
# bestASR mlx-audio adapter wrapper — venv containment (#51 D3).
exec "$DEST/venv/bin/python" "$DEST/bestasr-mlx-adapter.py" "\$@"
WRAPPER
chmod +x "$DEST/run.sh"

echo "✓ adapter installed: $DEST/run.sh"
if [ -f "$ENGINES_JSON" ] && grep -q '"mlx-audio"' "$ENGINES_JSON"; then
  echo "✓ engines.json already registers mlx-audio"
else
  if [ ! -f "$ENGINES_JSON" ]; then
    printf '{"engines":[{"id":"mlx-audio","command":["%s"]}]}\n' "$DEST/run.sh" > "$ENGINES_JSON"
    echo "✓ registered in $ENGINES_JSON"
  else
    echo "⚠ $ENGINES_JSON exists without an mlx-audio entry — add:"
    printf '  {"id":"mlx-audio","command":["%s"]}\n' "$DEST/run.sh"
  fi
fi
echo "→ verify: bestasr list-backends  (mlx-audio should report available)"
