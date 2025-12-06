#!/usr/bin/env bash
set -euo pipefail

echo "=== Установка TPM2-TSS 3.0.0 + FAPI + tpm2-tools 4.0.1 + tpm2-pytss 2.3.0 ==="

VENV_DIR="$HOME/tpmapp_venv"
BUILD_BASE="/tmp/tpm2-src"

echo "1) Удаление любых старых tpm2-tss/tpm2-tools/libtss2"
sudo apt remove --purge -y tpm2-tools tpm2-tss libtss2-* || true
sudo rm -f /usr/lib/x86_64-linux-gnu/libtss2-*.so*
sudo rm -f /usr/local/lib/libtss2-*.so*
sudo ldconfig || true

echo "2) Зависимости"
sudo apt update
sudo apt install -y \
  autoconf-archive \
  libcmocka0 \
  libcmocka-dev \
  procps \
  iproute2 \
  build-essential \
  git \
  pkg-config \
  gcc \
  libtool \
  automake \
  libssl-dev \
  uthash-dev \
  autoconf \
  doxygen \
  libjson-c-dev \
  libini-config-dev \
  libcurl4-openssl-dev \
  uuid-dev \
  libltdl-dev \
  libusb-1.0-0-dev \
  libftdi-dev \
  swtpm swtpm-tools \
  python3-venv python3-dev python3-pip \
  jq

echo "3) Скачивание и сборка tpm2-tss 3.0.0"
rm -rf "$BUILD_BASE"
mkdir -p "$BUILD_BASE"
cd "$BUILD_BASE"

git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 3.0.0

./bootstrap
./configure --prefix=/usr --with-fapi
make -j"$(nproc)"
sudo make install
sudo ldconfig

echo "Проверка наличия libtss2-fapi..."
if ! ldconfig -p | grep -q libtss2-fapi; then
  echo "ОШИБКА: FAPI не установлен!"
  exit 1
fi

echo "4) Скачивание и сборка tpm2-tools 4.0.1 (совместимые с TSS 3.0.0)"
cd "$BUILD_BASE"
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
git checkout 4.0.1

./bootstrap
mkdir build
cd build
../configure --prefix=/usr --with-tcti=swtpm
make -j"$(nproc)"
sudo make install
sudo ldconfig

echo "5) Python-venv + tpm2-pytss 2.3.0 (единственная версия с FAPI)"
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"

source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel
pip install pycryptodome

# Устанавливаем pytss строго 2.3.0
pip install tpm2-pytss==2.3.0

echo "6) Проверка FAPI через Python"
python3 <<'EOF'
from tpm2_pytss import FAPI
import json
try:
    with FAPI() as f:
        info = f.GetInfo()
        try:
            j = json.loads(info)
        except:
            j = {"raw": info}
        print(json.dumps(j, indent=2, ensure_ascii=False))
except Exception as e:
    print("Ошибка FAPI:", type(e).__name__, e)
    raise
EOF

echo "7) Алиасы"
if ! grep -q "tpmapp_venv" "$HOME/.bashrc"; then
cat <<'EOF' >> "$HOME/.bashrc"
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM app activated'"
alias tpmapp-create="tpmapp && python ~/tpmapp/app.py create"
alias tpmapp-open="tpmapp && python ~/tpmapp/app.py open"
alias tpmapp-close="tpmapp && python ~/tpmapp/app.py close"
EOF
fi

echo "=== ГОТОВО ==="
echo "Активировать окружение: source ~/tpmapp_venv/bin/activate"
echo "Проверить FAPI: python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
