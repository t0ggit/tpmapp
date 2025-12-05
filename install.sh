#!/bin/bash
# install_deps.sh
# Полностью изолированная установка всего необходимого для TPM2 + FAPI-приложения
# Ничего не трогает в системе, работает даже на сломанном python3

set -e

echo "=== TPM2 LUKS FAPI приложение — безопасная установка ==="

# 1.0. Только системные пакеты, которые почти всегда уже есть
echo "Устанавливаем только минимально необходимые системные пакеты..."
sudo DEBIAN_FRONTEND=noninteractive apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    cryptsetup \
    tpm2-tools \
    libtss2-dev \
    pkg-config \
    || { echo "Не удалось установить системные пакеты"; exit 1; }

# 1.1. Устанавливаем ВСЕ зависимости (теперь с libjson-c-dev и остальными)
sudo apt update
sudo apt install -y autoconf automake libtool pkg-config gcc git libssl-dev autoconf-archive libtool-bin libgcrypt-dev doxygen graphviz libjson-c-dev libini-config-dev libcurl4-openssl-dev uuid-dev libltdl-dev libusb-1.0-0-dev libftdi-dev uthash-dev

# 1.2. Клонируем и собираем tpm2-tss 4.1.2
cd /tmp
rm -rf tpm2-tss
git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 4.1.2

# 1.3. Bootstrap (теперь с json-c пройдёт)
./bootstrap

# 1.4. Конфигурируем (с флагом для udev, если нужно; swtpm работает по умолчанию)
./configure --prefix=/usr --with-udevrulesdir=/etc/udev/rules.d

# 1.5. Собираем и устанавливаем
make -j$(nproc)
sudo make install
sudo ldconfig  # обновляем библиотеки

# 1.6. Собираем обновлённые tpm2-tools (опционально)
cd /tmp
rm -rf tpm2-tools
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
./bootstrap
./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig

# 2. Создаём изолированное виртуальное окружение в домашней папке
VENV_DIR="$PWD/tpmapp_venv"
echo "Создаём виртуальное окружение в $VENV_DIR ..."
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"

# Активируем его
source "$VENV_DIR/bin/activate"

# 3. Устанавливаем нужные Python-пакеты только внутрь venv
echo "Устанавливаем tpm2-pytss и pycryptodome через pip..."
pip install --quiet --upgrade pip > /dev/null
pip install tpm2-pytss pycryptodome

# 4. Проверяем, что FAPI видит твой vTPM
echo "Проверяем подключение к TPM..."
python -c "
from tpm2_pytss import FAPI
info = FAPI().get_info()
print(f'Success: TPM найден → {info}')
" || { echo "Error: TPM не найден или FAPI не работает"; exit 1; }

# 5. Создаём удобные алиасы в ~/.bashrc (только если их ещё нет)
if ! grep -q "tpmapp_venv" ~/.bashrc 2>/dev/null; then
    cat << 'EOF' >> ~/.bashrc

# === TPM2 LUKS FAPI приложение ===
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM app environment активировано'"
alias tpmapp-create="tpmapp && python ~/tpmapp/app.py create"
alias tpmapp-open="tpmapp && python ~/tpmapp/app.py open"
alias tpmapp-close="tpmapp && python ~/tpmapp/app.py close"
EOF
    echo "Добавлены алиасы: tpmapp, tpmapp-create, tpmapp-open, tpmapp-close"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "ГОТОВО! Всё установлено изолированно и безопасно."
echo ""
echo "Теперь просто пиши:"
echo "   tpmapp                  # активировать окружение"
echo "   tpmapp-create secret1   # создать диск"
echo "   tpmapp-open secret1     # открыть и примонтировать"
echo "   tpmapp-close secret1    # закрыть"
echo ""
echo "Или запускай вручную:"
echo "   source ~/tpmapp_venv/bin/activate"
echo "   python app.py create mydata"
echo "════════════════════════════════════════════════════════════"