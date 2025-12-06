#!/usr/bin/env bash
set -euo pipefail

echo "=== Установка TPM2-TSS 3.2.3 + FAPI для Ubuntu 22.04 ==="

VENV_DIR="$HOME/tpmapp_venv"
BUILD_BASE="/tmp/tpm2-src"

echo "1) Удаление старых libtss2*"
sudo apt remove --purge -y tpm2-tools tpm2-tss libtss2-* || true
sudo rm -f /usr/lib/x86_64-linux-gnu/libtss2-*.so*
sudo rm -f /usr/local/lib/libtss2-*.so*
sudo ldconfig || true

echo "2) Установка зависимостей"
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

echo "3) Скачивание tpm2-tss 3.2.3"
rm -rf "$BUILD_BASE"
mkdir -p "$BUILD_BASE"
cd "$BUILD_BASE"

git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 3.2.3

echo "4) Патч m4 макросов (обязательно!)"
mkdir -p m4
wget -O m4/ax_code_coverage.m4 https://raw.githubusercontent.com/autoconf-archive/autoconf-archive/master/m4/ax_code_coverage.m4
wget -O m4/ax_prog_doxygen.m4 https://raw.githubusercontent.com/autoconf-archive/autoconf-archive/master/m4/ax_prog_doxygen.m4

echo "5) bootstrap"
./bootstrap

echo "6) configure"
./configure --prefix=/usr --with-fapi

echo "7) make + install"
make -j"$(nproc)"
sudo make install
sudo ldconfig

echo "8) Сборка tpm2-tools 3.2.3"
cd "$BUILD_BASE"
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
git checkout 3.2.3
./bootstrap
mkdir -p build
cd build
../configure --prefix=/usr --with-tcti=swtpm
make -j"$(nproc)"
sudo make install
sudo ldconfig

echo "9) Python venv + pytss"
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel
pip install tpm2-pytss pycryptodome

echo "10) Проверка FAPI"
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

echo "=== ГОТОВО ==="
echo "Активировать окружение: source ~/tpmapp_venv/bin/activate"
echo "Проверить FAPI: python3 -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
