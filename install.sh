#!/usr/bin/env bash
set -euo pipefail

echo "=== РАБОЧАЯ связка 2025: tpm2-tss 3.0.3 + FAPI + tpm2-pytss 2.3.0 ==="

# Зачистка
sudo rm -rf /usr/lib/x86_64-linux-gnu/libtss2* /usr/include/tss2
sudo ldconfig

# Зависимости
sudo apt update
sudo apt install -y build-essential git autoconf-archive pkg-config libtool automake \
  libssl-dev uthash-dev libjson-c-dev libini-config-dev libcurl4-openssl-dev \
  uuid-dev python3-venv python3-dev python3-pip swtpm swtpm-tools

# tpm2-tss 3.0.3 — единственная рабочая версия
cd /tmp
rm -rf tpm2-tss
git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 3.0.3
./bootstrap
./configure --prefix=/usr --enable-fapi
make -j$(nproc)
sudo make install
sudo ldconfig

# tpm2-tools (можно свежий, он не влияет на FAPI)
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
git checkout 5.7
./bootstrap
./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig

# Python
rm -rf ~/tpmapp_venv
python3 -m venv ~/tpmapp_venv
source ~/tpmapp_venv/bin/activate
pip install --upgrade pip
pip install pycryptodome tpm2-pytss==2.3.0

# Проверка
echo "Проверка FAPI..."
python -c "from tpm2_pytss import FAPI, FAPIConfig; print(FAPI().GetInfo())" | head -5

echo "ГОТОВО! Активируй: source ~/tpmapp_venv/bin/activate"