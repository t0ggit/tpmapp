#!/usr/bin/env bash
set -euo pipefail

echo "=== Полная чистая установка TPM2-TSS 3.0.0 + FAPI ==="

VENV_DIR="$HOME/tpmapp_venv"
BUILD_BASE="/tmp/tpm2-src"

echo "1) Удаление старых libtss2*"
sudo apt remove --purge -y tpm2-tools tpm2-tss libtss2-* || true
sudo rm -f /usr/lib/x86_64-linux-gnu/libtss2-*.so*
sudo rm -f /usr/local/lib/libtss2-*.so*
sudo ldconfig || true

echo "2) Установка системных зависимостей"
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

echo "3) Скачивание tpm2-tss 3.0.0"
rm -rf "$BUILD_BASE"
mkdir -p "$BUILD_BASE"
cd "$BUILD_BASE"

git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 3.0.0

./bootstrap

echo "4) Конфигурация tpm2-tss с FAPI"
./configure --prefix=/usr --with-fapi

echo "5) Сборка и установка tpm2-tss 3.0.0"
make -j"$(nproc)"
sudo make install
sudo ldconfig

echo "6) Проверка FAPI"
if ! ldconfig -p | grep -q libtss2-fapi; then
    echo "FAPI не был установлен. Ошибка."
    exit 1
fi

echo "Найдена библиотека:"
ldconfig -p | grep libtss2-fapi

echo "7) Скачивание и сборка tpm2-tools 5.4 (совместимая версия)"
cd "$BUILD_BASE"
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
git checkout 5.4

./bootstrap
mkdir -p build
cd build
../configure --prefix=/usr --with-tcti=swtpm
make -j"$(nproc)"
sudo make install
sudo ldconfig

echo "8) Python venv и tpm2-pytss"
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel
pip install tpm2-pytss pycryptodome

echo "9) Проверка FAPI через Python"
python3 <<'EOF'
from tpm2_pytss import FAPI
import json
with FAPI() as f:
    info = f.GetInfo()
    try:
        j = json.loads(info)
    except:
        j = {"raw": info}
    print(j)
EOF

echo "10) Алиасы"
if ! grep -q "tpmapp_venv" "$HOME/.bashrc"; then
cat <<'EOF' >> "$HOME/.bashrc"
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM app activated'"
alias tpmapp-create="tpmapp && python ~/tpmapp/app.py create"
alias tpmapp-open="tpmapp && python ~/tpmapp/app.py open"
alias tpmapp-close="tpmapp && python ~/tpmapp/app.py close"
EOF
fi

echo "=== УСТАНОВКА ГОТОВА (TPM2-TSS 3.0.0, TOOLS 5.4) ==="
echo "source ~/tpmapp_venv/bin/activate"
echo "python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
