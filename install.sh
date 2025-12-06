#!/usr/bin/env bash
set -euo pipefail

echo "=== Установка TPM2-TSS 3.2.1 + FAPI + tpm2-tools 5.7 + tpm2-pytss 2.3.0 (декабрь 2025) ==="

VENV_DIR="$HOME/tpmapp_venv"
BUILD_BASE="/tmp/tpm2-build-$$"

# 1) Зачистка
echo "1) Удаляем старьё"
sudo apt remove --purge -y tpm2-tools tpm2-abrmd libtss2-* 2>/dev/null || true
sudo rm -rf /usr/local/lib/libtss2* /usr/lib/x86_64-linux-gnu/libtss2* 2>/dev/null || true
sudo ldconfig

# 2) Зависимости
echo "2) Устанавливаем зависимости"
sudo apt update
sudo apt install -y autoconf-archive pkg-config libtool automake gcc make git \
  libcmocka0 libcmocka-dev build-essential doxygen libssl-dev uthash-dev \
  libjson-c-dev libini-config-dev libcurl4-openssl-dev uuid-dev libusb-1.0-0-dev \
  swtpm swtpm-tools python3-venv python3-dev python3-pip jq

# 3) tpm2-tss 3.2.1 с FAPI
echo "3) Собираем tpm2-tss 3.2.1 + FAPI"
rm -rf "$BUILD_BASE"
mkdir -p "$BUILD_BASE" && cd "$BUILD_BASE"

git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 3.2.1
./bootstrap
./configure --prefix=/usr --enable-fapi --enable-integration
make -j"$(nproc)"
sudo make install
sudo ldconfig

# Умная проверка FAPI
echo "Проверяем наличие FAPI..."
if ldconfig -p | grep -q libtss2-fapi; then
    echo "libtss2-fapi установлен"
else
    echo "Всё равно не нашёл, но продолжаем — часто просто ссылки ещё не созданы"
fi

# 4) tpm2-tools 5.7
echo "4) Собираем tpm2-tools 5.7"
cd "$BUILD_BASE"
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
git checkout 5.7
./bootstrap
./configure --prefix=/usr
make -j"$(nproc)"
sudo make install
sudo ldconfig

# 5) Python venv + pytss 2.3.0
echo "5) Создаём venv и ставим tpm2-pytss 2.3.0"
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel
pip install pycryptodome tpm2-pytss==2.3.0

# 6) Финальная проверка через Python
echo "6) Тестируем FAPI из Python"
python -c "
from tpm2_pytss import FAPI
try:
    with FAPI() as f:
        print('FAPI РАБОТАЕТ →', f.GetInfo()[:150].replace('\n', ' '))
except Exception as e:
    print('FAPI не завёлся:', e)
    exit(1)
"

# 7) Алиасы
echo "7) Добавляем алиасы"
grep -q "tpmapp_venv" "$HOME/.bashrc" 2>/dev/null || cat <<'EOF' >> "$HOME/.bashrc"

# TPM2 + FAPI
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM venv активирован'"
alias tpmapp-info="tpmapp && python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
EOF

echo ""
echo "ГОТОВО! Всё установлено и FAPI работает"
echo "Активируй:   tpmapp"
echo "Проверь:     tpmapp-info"
rm -rf "$BUILD_BASE"