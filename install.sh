#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing kde-weather..."

# Install system dependencies
echo "Checking system packages..."
if ! pacman -Q pyside6 qt6-charts python-requests &>/dev/null; then
    echo "Installing system packages (requires sudo)..."
    sudo pacman -S --needed pyside6 qt6-charts python-requests
fi

# Install with pip in editable mode
echo "Installing kde-weather..."
pip install --user -e "$SCRIPT_DIR"

# Install desktop entry
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$DESKTOP_DIR"
cp "$SCRIPT_DIR/kde-weather.desktop" "$DESKTOP_DIR/"

echo "Done! Run 'kde-weather' to start."
