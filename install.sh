#!/usr/bin/env bash
# Pemasang Tenun. Pakai: curl -fsSL https://raw.githubusercontent.com/TenunLang/Tenun/main/install.sh | bash
set -euo pipefail

REPO="TenunLang/Tenun"
DEST="$HOME/.tenun/bin"

os=""
case "$(uname -s)" in
  Linux) os="linux" ;;
  Darwin) os="macos" ;;
  *) echo "OS tidak didukung: $(uname -s)"; exit 1 ;;
esac

arch=""
case "$(uname -m)" in
  x86_64 | amd64) arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
  *) echo "Arsitektur tidak didukung: $(uname -m)"; exit 1 ;;
esac

asset="tenun-${os}-${arch}"
url="https://github.com/${REPO}/releases/latest/download/${asset}"

echo "Mengunduh ${asset} ..."
mkdir -p "$DEST"
curl -fsSL "$url" -o "$DEST/tenun"
chmod +x "$DEST/tenun"

# Tambahkan ke PATH lewat file rc shell
line='export PATH="$HOME/.tenun/bin:$PATH"'
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  if [ -f "$rc" ] && ! grep -qF "$line" "$rc"; then
    echo "$line" >> "$rc"
  fi
done

echo ""
echo "Tenun terpasang di $DEST/tenun"
echo "Buka terminal baru (atau jalankan: export PATH=\"\$HOME/.tenun/bin:\$PATH\"), lalu:"
echo "  tenun version"
