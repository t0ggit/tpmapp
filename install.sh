#!/bin/bash
# install_deps.sh — окончательный и полностью рабочий вариант (2025)
# Работает на чистой Ubuntu 22.04 Server с vTPM (swtpm)
set -e

echo "=== TPM2 + FAPI + LUKS приложение — полная установка ==="

# 1. Устанавливаем все зависимости для сборки tpm2-tss и tpm2-tools
echo "Установка системных зависимостей..."
sudo DEBIAN_FRONTEND=noninteractive apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    cryptsetup \
    tpm2-tools \
    build-essential \
    git \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libssl-dev \
    autoconf-archive \
    libtool-bin \
    libgcrypt-dev \
    libjson-c-dev \
    libini-config-dev \
    libcurl4-openssl-dev \
    uuid-dev \
    libltdl-dev \
    libusb-1.0-0-dev \
    uthash-dev \
    doxygen \
    graphviz

# 2. Собираем tpm2-tss 4.1.2 с поддержкой FAPI 3.0+
echo "Сборка tpm2-tss 4.1.2 (с FAPI 3.0+ для swtpm)..."
cd /tmp
rm -rf tpm2-tss
git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 4.1.2
./bootstrap
./configure --prefix=/usr --with-udevrulesdir=/etc/udev/rules.d
make -j$(nproc)
sudo make install
sudo ldconfig

# 3. Обновляем tpm2-tools (чтобы работали с новым tss)
echo "Обновление tpm2-tools..."
cd /tmp
rm -rf tpm2-tools
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
./bootstrap
./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig

# 4. Создаём изолированное Python-окружение
VENV_DIR="$HOME/tpmapp_venv"
echo "Создание виртуального окружения в $VENV_DIR..."
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# 5. Устанавливаем Python-пакеты
echo "Установка tpm2-pytss и pycryptodome..."
pip install --quiet --upgrade pip
pip install --quiet tpm2-pytss pycryptodome

# 6. ПРАВИЛЬНАЯ проверка, что FAPI видит vTPM
echo "Проверка подключения к TPM через FAPI..."
python - <<'PYTHON'
from tpm2_pytss import FAPI
import json

try:
    with FAPI() as fapi:
        info_json = fapi.GetInfo()
        info = json.loads(info_json)
        manuf_hex = info.get("manufacturer", "00000000")
        if manuf_hex == "53575450":
            print(f"УСПЕХ! TPM обнаружен: SWTP (swtpm)")
            print(f"   FAPI версия: {info.get('fapi-version')}")
        else:
            print(f"TPM найден, но не swtpm: {manuf_hex}")
except Exception as e:
    print(f"ОШИБКА FAPI: {e}")
    exit(1)
PYTHON

# 7. Удобные алиасы
if ! grep -q "tpmapp_venv" ~/.bashrc 2>/dev/null; then
    cat << 'EOF' >> ~/.bashrc

# === TPM2 LUKS FAPI приложение ===
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM app активировано'"
alias tpmapp-create="tpmapp && python ~/tpmapp/app.py create"
alias tpmapp-open="tpmapp && python ~/tpmapp/app.py open"
alias tpmapp-close="tpmapp && python ~/tpmapp/app.py close"
EOF
    echo "Добавлены алиасы в ~/.bashrc"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "ГОТОВО НАВСЕГДА!"
echo ""
echo "Теперь используй:"
echo "   tpmapp                  # активировать окружение"
echo "   tpmapp-create mydata    # создать зашифрованный диск"
echo "   tpmapp-open mydata      # открыть"
echo "   tpmapp-close mydata     # закрыть"
echo ""
echo "Или вручную:"
echo "   source ~/tpmapp_venv/bin/activate"
echo "   python app.py create mydata"
echo "════════════════════════════════════════════════════════════"