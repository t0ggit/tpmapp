#!/usr/bin/env bash
set -euo pipefail

echo "=== Установка TPM2-TSS 3.2.1 + FAPI + tpm2-tools 5.7 + tpm2-pytss 2.3.0 (рабочая связка 2025) ==="

VENV_DIR="$HOME/tpmapp_venv"
BUILD_BASE="/tmp/tpm2-build-$$"

# 1) Полная зачистка старого хлама
echo "1) Удаляем старые пакеты и библиотеки tpm2-*"
sudo apt remove --purge -y tpm2-tools tpm2-abrmd tpm2-tss libtss2-* || true
sudo rm -rf /usr/local/lib/libtss2* /usr/lib/x86_64-linux-gnu/libtss2* || true
sudo ldconfig || true

# 2) Установка всех зависимостей
echo "2) Устанавливаем зависимости"
sudo apt update
sudo apt install -y \
  autoconf-archive pkg-config libtool automake gcc make git \
  libcmocka0 libcmocka-dev \
  build-essential doxygen \
  libssl-dev uthash-dev libjson-c-dev libini-config-dev \
  libcurl4-openssl-dev uuid-dev libusb-1.0-0-dev \
  swtpm swtpm-tools \
  python3-venv python3-dev python3-pip jq

# 3) Собираем tpm2-tss 3.2.1 с включённым FAPI
echo "3) Собираем tpm2-tss 3.2.1 (с FAPI)"
rm -rf "$BUILD_BASE"
mkdir -p "$BUILD_BASE"
cd "$BUILD_BASE"

git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 3.2.1
./bootstrap
./configure --prefix=/usr --enable-fapi
make -j"$(nproc)"
sudo make install
sudo ldconfig

# Проверка, что FAPI реально собрался
echo "Проверяем, что FAPI действительно установился..."
if [ -f "/usr/lib/x86_64-linux-gnu/libtss2-fapi.so.1" ] || \
   || [ -f "/usr/lib/x86_64-linux-gnu/libtss2-fapi.so" ] \
   || ldconfig -p | grep -q libtss2-fapi; then
    echo "libtss2-fapi успешно установлен и виден системе"
else
    echo "ОШИБКА: libtss2-fapi.so не найден даже после установки"
    exit 1
fi

# 4) Собираем tpm2-tools 5.7 (последняя стабильная на декабрь 2025)
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

echo "tpm2-tools 5.7 установлен"

# 5) Создаём виртуальное окружение и ставим tpm2-pytss 2.3.0
echo "5) Создаём Python venv и ставим tpm2-pytss 2.3.0"
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel
pip install pycryptodome
pip install tpm2-pytss==2.3.0

# 6) Быстрая проверка FAPI из Python
echo "6) Проверяем работу FAPI через Python"
python - <<'EOF'
from tpm2_pytss import FAPI, FAPIConfig
import os
try:
    # Для swtpm FAPI сам найдёт сокет, если переменная не задана
    with FAPI() as fapi:
        info = fapi.GetInfo()
        print("FAPI работает! Версия/инфо:")
        print(info[:200] + "..." if len(info) > 200 else info)
except Exception as e:
    print("Ошибка FAPI:", e)
    exit(1)
EOF

# 7) Удобные алиасы в .bashrc
echo "7) Добавляем алиасы в ~/.bashrc"
if ! grep -q "tpmapp_venv" "$HOME/.bashrc" 2>/dev/null; then
  cat <<'EOF' >> "$HOME/.bashrc"

# ── TPM2 + FAPI окружение ─────────────────────────────────────
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM venv активирован'"
alias tpmapp-create="tpmapp && python ~/tpmapp/app.py create"
alias tpmapp-open="tpmapp && python ~/tpmapp/app.py open"
alias tpmapp-close="tpmapp && python ~/tpmapp/app.py close"
alias tpmapp-info="tpmapp && python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
EOF
  echo "Алиасы добавлены в ~/.bashrc"
fi

# Финал
echo ""
echo "ГОТОВО! Всё собрано и работает"
echo ""
echo "Активировать окружение:"
echo "   source ~/tpmapp_venv/bin/activate   или просто   tpmapp"
echo ""
echo "Быстрая проверка FAPI:"
echo "   tpmapp-info"
echo ""
echo "Если хочешь сразу запустить swtpm для тестов:"
echo "   mkdir -p /tmp/myvtpm && swtpm socket --tpm2 -t -d --tpmstate dir=/tmp/myvtpm --ctrl type=unixio,path=/tmp/myvtpm/swtpm.sock"
echo "   export TPM2TOOLS_TCTI=\"swtpm:path=/tmp/myvtpm/swtpm.sock\""

# Уборка за собой
rm -rf "$BUILD_BASE"

exit 0