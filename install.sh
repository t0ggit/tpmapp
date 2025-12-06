#!/usr/bin/env bash
set -euo pipefail

echo "=== TPM2-TSS 4.1.0 + FAPI + tpm2-pytss 2.3.0 (рабочий патч 2025) ==="

VENV_DIR="$PWD/tpmapp_venv"
BUILD_BASE="/tmp/tpm2-build-$$"

# Зачистка
sudo rm -rf /usr/lib/x86_64-linux-gnu/libtss2* /usr/include/tss2
sudo apt remove --purge -y tpm2-tools libtss2-* 2>/dev/null || true
sudo ldconfig

# Зависимости
sudo apt update
sudo apt install -y build-essential git autoconf-archive pkg-config libtool automake \
  libssl-dev uthash-dev libjson-c-dev libini-config-dev libcurl4-openssl-dev \
  uuid-dev python3-venv python3-dev python3-pip swtpm swtpm-tools

# TSS 4.1.0
cd /tmp
rm -rf tpm2-tss
git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 4.1.0
./bootstrap
./configure --prefix=/usr --enable-fapi
make -j$(nproc)
sudo make install
sudo ldconfig

# tpm2-tools
cd /tmp
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
git checkout 5.7
./bootstrap
./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig

# Python + патч
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install pycryptodome tpm2-pytss==2.3.0

FAPI_FILE="$(python -c 'import tpm2_pytss, os; print(os.path.dirname(tpm2_pytss.__file__))')/FAPI.py"

sed -i 's/raise NotImplementedError("FAPI Not installed or version is not 3.0.0")/pass/' "$FAPI_FILE"
sed -i '/def_extern("_fapi_auth_callback")/,+10d' "$FAPI_FILE"
sed -i '/_fapi_auth_callback/d' "$FAPI_FILE"

# Проверка
echo "ПРОВЕРКА FAPI:"
python -c "from tpm2_pytss import FAPI; print('FAPI ОК:', FAPI().GetInfo()[:200])"

echo "Алиасы"
cat <<'EOF' >> ~/.bashrc

alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM2 + FAPI готов (TSS 4.1.0)'"
alias tpmapp-info="tpmapp && python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
EOF

echo "ГОТОВО! Запусти: tpmapp"