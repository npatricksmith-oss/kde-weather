#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"

echo "Installing kde-weather..."

# Install system dependencies (pyside6, qt6-charts are not on PyPI; must come from pacman).
# noto-fonts-emoji provides the color emoji font used by WeatherIcon.qml so weather
# glyphs render with natural colors (yellow sun, white clouds, etc.) instead of monochrome.
echo "Checking system packages..."
if ! pacman -Q pyside6 qt6-charts python-requests noto-fonts-emoji &>/dev/null; then
    echo "Installing system packages (requires sudo)..."
    sudo pacman -S --needed pyside6 qt6-charts python-requests noto-fonts-emoji
fi

# Create venv if it doesn't exist.
# --system-site-packages lets it see pyside6/qt6-charts installed by pacman.
if [ ! -f "$VENV/bin/python" ]; then
    echo "Creating virtual environment..."
    python -m venv --system-site-packages "$VENV"
fi

# Install the package in editable mode using the venv's pip
echo "Installing kde-weather into venv..."
"$VENV/bin/pip" install --quiet -e "$SCRIPT_DIR"

# Install a wrapper script to ~/.local/bin so 'kde-weather' is on PATH
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/kde-weather" <<EOF
#!/bin/bash
exec "$VENV/bin/kde-weather" "\$@"
EOF
chmod +x "$BIN_DIR/kde-weather"

# Install desktop entry
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$DESKTOP_DIR"
cp "$SCRIPT_DIR/kde-weather.desktop" "$DESKTOP_DIR/"

echo "Done!"
echo "  Launch from terminal:  kde-weather"
echo "  Launch from KDE:       search 'KDE Weather' in app launcher"
echo ""
echo "If 'kde-weather' is not found, add ~/.local/bin to your PATH:"
echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
