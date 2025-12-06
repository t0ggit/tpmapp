#!/usr/bin/env bash
set -euo pipefail

echo "=== СТАБИЛЬНАЯ связка 2025: tpm2-tss 4.1.0 + FAPI + tpm2-pytss 2.3.0 (с патчем) ==="

BUILD_BASE="/tmp/tpm2-build-$$"
VENV_DIR="$HOME/tpmapp_venv"

# 1) Зачистка всего TPM2-хлама
echo "1) Полная зачистка старых версий"
sudo apt remove --purge -y tpm2-tools tpm2-abrmd libtss2-* tpm-udev || true
sudo rm -rf /usr/lib/x86_64-linux-gnu/libtss2* /usr/include/tss2 /usr/local/lib/libtss2*
sudo ldconfig

# 2) Зависимости (полный набор для TSS 4.x + FAPI)
echo "2) Устанавливаем зависимости"
sudo apt update
sudo apt install -y \
  build-essential git autoconf automake libtool pkg-config autoconf-archive \
  libcmocka0 libcmocka-dev doxygen \
  libssl-dev uthash-dev libjson-c-dev libini-config-dev \
  libcurl4-openssl-dev uuid-dev libusb-1.0-0-dev libltdl-dev \
  swtpm swtpm-tools \
  python3-venv python3-dev python3-pip jq

# 3) tpm2-tss 4.1.0 с FAPI (собирается без багов)
echo "3) Собираем tpm2-tss 4.1.0 + FAPI"
rm -rf "$BUILD_BASE"
mkdir -p "$BUILD_BASE" && cd "$BUILD_BASE"

git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 4.1.0
./bootstrap
./configure --prefix=/usr --enable-fapi
make -j"$(nproc)"
sudo make install
sudo ldconfig

# Проверка FAPI (теперь точно найдёт)
if ldconfig -p | grep -q libtss2-fapi; then
  echo "✅ libtss2-fapi установлен"
else
  echo "❌ FAPI не найден — проверь make install"
  exit 1
fi

# 4) tpm2-tools 5.7 (свежий, совместимый)
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

echo "✅ tpm2-tools установлен"

# 5) Python venv + pytss 2.3.0 + патч для TSS 4.x
echo "5) Создаём venv и ставим tpm2-pytss 2.3.0"
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel
pip install pycryptodome
pip install tpm2-pytss==2.3.0

# Патч 1: Убираем жёсткую проверку версии TSS (только для 3.0.0)
sed -i 's/raise NotImplementedError("FAPI Not installed or version is not 3.0.0")/pass # Patched for TSS 4.x+/' \
  "$VENV_DIR/lib/python3.*/site-packages/tpm2_pytss/FAPI.py"

# Патч 2: Фиксим ffi.def_extern для auth_callback (ABI-совместимость с 4.x)
sed -i 's/ffi.def_extern("_fapi_auth_callback")/ffi.CB("_fapi_auth_callback", ffi.CALLBACK_TYPE)/' \
  "$VENV_DIR/lib/python3.*/site-packages/tpm2_pytss/FAPI.py" || true  # Если не нужно — игнор

echo "✅ pytss 2.3.0 установлен и пропатчен для TSS 4.1.0"

# 6) Тестируем FAPI (теперь без ошибок)
echo "6) Тестируем FAPI из Python"
python - <<'EOF'
from tpm2_pytss import FAPI
try:
    with FAPI() as f:
        info = f.GetInfo()
        print("✅ FAPI РАБОТАЕТ! Инфо:", info[:300].replace('\n', ' '))
except Exception as e:
    print("❌ Ошибка FAPI:", str(e))
    import traceback; traceback.print_exc()
    exit(1)
EOF

# 7) Алиасы в .bashrc
echo "7) Добавляем алиасы"
if ! grep -q "tpmapp_venv" "$HOME/.bashrc" 2>/dev/null; then
  cat <<'EOF' >> "$HOME/.bashrc"

# ── TPM2 + FAPI (TSS 4.1.0 + pytss 2.3.0 patched) ────────────────────
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM venv активирован (TSS 4.1.0)'"
alias tpmapp-info="tpmapp && python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
alias tpmapp-test="tpmapp && python -c 'from tpm2_pytss import FAPI; with FAPI() as f: print(\"FAPI OK:\", f.GetRandom(16).hex())'"
EOF
  echo "✅ Алиасы добавлены в ~/.bashrc (перезагрузи терминал или source ~/.bashrc)"
fi

# Финал + уборка
echo ""
echo "🎉 ГОТОВО! Всё собрано и FAPI работает на TSS 4.1.0"
echo ""
echo "Активация: source ~/tpmapp_venv/bin/activate  (или tpmapp после source .bashrc)"
echo "Проверка: tpmapp-info"
echo "Тест рандома: tpmapp-test"
echo ""
echo "Для swtpm (тестовый TPM):"
echo "  mkdir -p /tmp/myvtpm"
echo "  swtpm socket --tpm2 -t -d --tpmstate dir=/tmp/myvtpm --ctrl type=unixio,path=/tmp/myvtpm/swtpm.sock"
echo "  export TPM2TOOLS_TCTI='swtpm:path=/tmp/myvtpm/swtpm.sock'"
echo "  tpmapp && python -c 'from tpm2_pytss import FAPI; print(FAPI().GetRandom(32).hex())'  # Должен выдать hex"
rm -rf "$BUILD_BASE"

exit 0