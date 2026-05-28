#!/bin/sh
set -e

REPO="runnon/devkat"
BINARY="devkat-push"
INSTALL_DIR="${HOME}/.local/bin"
ARCH="$(uname -m)"

echo ""
echo "  devkat — session tracking for AI coding tools"
echo ""

if [ "$(uname -s)" != "Darwin" ]; then
    echo "  Error: devkat currently only supports macOS."
    exit 1
fi

RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
DOWNLOAD_URL=$(printf '%s\n' "$RELEASE_JSON" | grep 'browser_download_url.*macos-universal' | cut -d '"' -f 4 | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    case "$ARCH" in
        arm64)
            ARCH_PATTERN='browser_download_url.*\(darwin\|macos\).*\(arm64\|aarch64\)'
            ;;
        x86_64)
            ARCH_PATTERN='browser_download_url.*\(darwin\|macos\).*\(x86_64\|x64\|amd64\)'
            ;;
        *)
            echo "  Error: unsupported macOS architecture: $ARCH"
            exit 1
            ;;
    esac

    DOWNLOAD_URL=$(printf '%s\n' "$RELEASE_JSON" | grep "$ARCH_PATTERN" | cut -d '"' -f 4 | head -n 1)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(printf '%s\n' "$RELEASE_JSON" | grep 'browser_download_url.*macos' | cut -d '"' -f 4 | head -n 1)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    echo "  Error: could not find a macOS release asset on $REPO."
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "  Downloading..."
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/devkat.tar.gz"
tar -xzf "$TMP_DIR/devkat.tar.gz" -C "$TMP_DIR"

if [ ! -f "$TMP_DIR/$BINARY" ]; then
    echo "  Error: release asset did not contain $BINARY."
    exit 1
fi

FILE_INFO=$(file "$TMP_DIR/$BINARY")
case "$ARCH" in
    arm64)
        if ! printf '%s\n' "$FILE_INFO" | grep -q 'arm64'; then
            echo "  Error: latest release does not include an Apple Silicon binary."
            exit 1
        fi
        ;;
    x86_64)
        if ! printf '%s\n' "$FILE_INFO" | grep -q 'x86_64'; then
            echo "  Error: latest release does not include an Intel macOS binary."
            echo "  A new universal or x86_64 release asset needs to be published."
            exit 1
        fi
        ;;
esac

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

"$INSTALL_DIR/$BINARY" --login < /dev/tty
