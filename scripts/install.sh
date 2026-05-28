#!/bin/sh
set -e

REPO="runnon/devkat"
BINARY="devkat-push"
INSTALL_DIR="${HOME}/.local/bin"

echo ""
echo "  devkat — session tracking for AI coding tools"
echo ""

if [ "$(uname -s)" != "Darwin" ]; then
    echo "  Error: devkat currently only supports macOS."
    exit 1
fi

DOWNLOAD_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep "browser_download_url.*macos" | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "  Error: could not find a macOS release asset on $REPO."
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "  Downloading..."
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/devkat.tar.gz"
tar -xzf "$TMP_DIR/devkat.tar.gz" -C "$TMP_DIR"

mkdir -p "$INSTALL_DIR"

mv "$TMP_DIR/$BINARY" "$INSTALL_DIR/$BINARY"
chmod +x "$INSTALL_DIR/$BINARY"

export PATH="$INSTALL_DIR:$PATH"

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        SHELL_NAME=$(basename "$SHELL")
        if [ "$SHELL_NAME" = "zsh" ]; then
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$HOME/.zshrc"
        elif [ "$SHELL_NAME" = "bash" ]; then
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$HOME/.bashrc"
        fi
        ;;
esac

echo "  ✓ Installed"
echo ""

if "$INSTALL_DIR/$BINARY" --check-login >/dev/null 2>&1; then
    echo "  ✓ Existing login found"
    echo ""
    "$INSTALL_DIR/$BINARY" --install
else
    "$INSTALL_DIR/$BINARY" --login < /dev/tty
fi
