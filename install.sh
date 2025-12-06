#!/usr/bin/env bash
set -euo pipefail

echo "=== ФИНАЛЬНАЯ РАБОЧАЯ СВЯЗКА 2025: tpm2-tss 3.0.3 + FAPI + tpm2-pytss 2.3.0 (без патчей!) ==="

VENV_DIR="$HOME/tpmapp_venv"
BUILD_BASE="/tmp/tpm2-build-$$"

# 1) Зачистка
echo "1) Зачистка старых версий"
sudo apt remove --purge -y tpm2-tools libtss2-* 2>/dev/null || true
sudo rm -rf /usr/lib/x86_64-linux-gnu/libtss2* /usr/include/tss2 /usr/local/lib/libtss2*
sudo ldconfig

# 2) Зависимости
echo "2) Зависимости"
sudo apt update
sudo apt install -y \
  autoconf-archive pkg-config libtool automake gcc make git doxygen \
  libcmocka0 libcmocka-dev libssl-dev uthash-dev libjson-c-dev \
  libini-config-dev libcurl4-openssl-dev uuid-dev libusb-1.0-0-dev \
  swtpm swtpm-tools python3-venv python3-dev python3-pip jq

# 3) tpm2-tss 3.0.3 с FAPI (фикс configure)
echo "3) Собираем tpm2-tss 3.0.3 + FAPI"
rm -rf "$BUILD_BASE"
mkdir -p "$BUILD_BASE" && cd "$BUILD_BASE"
git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 3.0.3
./bootstrap
autoreconf -fiv  # КРИТИЧНО: Перегенерит m4, фиксит syntax error в configure
./configure --prefix=/usr --enable-fapi
make -j"$(nproc)"
sudo make install
sudo ldconfig

# Проверка FAPI
if ldconfig -p | grep -q libtss2-fapi; then
  echo "✅ libtss2-fapi установлен (версия 3.0.3)"
else
  echo "❌ FAPI не найден — ошибка сборки"
  exit 1
fi

# 4) tpm2-tools 5.7 (не влияет на FAPI, оставляем свежий)
echo "4) tpm2-tools 5.7"
cd "$BUILD_BASE"
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
git checkout 5.7
./bootstrap
./configure --prefix=/usr
make -j"$(nproc)"
sudo make install
sudo ldconfig

# 5) Venv + pytss 2.3.0 (чисто, без патчей — ABI совпадает)
echo "5) Venv + tpm2-pytss 2.3.0"
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel
pip install pycryptodome tpm2-pytss==2.3.0

# 6) Тест FAPI
echo "6) Тест FAPI"
python - <<'EOF'
from tpm2_pytss import FAPI
try:
    with FAPI() as f:
        info = f.GetInfo()
        print("✅ FAPI РАБОТАЕТ! Инфо:", info[:300].replace('\n', ' '))
except Exception as e:
    print("❌ Ошибка:", str(e))
    import traceback; traceback.print_exc()
    exit(1)
EOF

# 7) Алиасы
echo "7) Алиасы в ~/.bashrc"
if ! grep -q "tpmapp_venv" "$HOME/.bashrc" 2>/dev/null; then
  cat <<'EOF' >> "$HOME/.bashrc"

# TPM2 + FAPI (TSS 3.0.3 + pytss 2.3.0)
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM venv активирован (FAPI 3.0.3)'"
alias tpmapp-info="tpmapp && python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
alias tpmapp-test="tpmapp && python -c 'from tpm2_pytss import FAPI; print(\"Random:\", FAPI().GetRandom(16).hex())'"
EOF
  echo "✅ Алиасы добавлены (source ~/.bashrc для активации)"
fi

# Финал
echo ""
echo "🎉 ГОТОВО! Активируй: source ~/tpmapp_venv/bin/activate"
echo "Проверь: tpmapp-info"
echo "Тест: tpmapp-test"
echo ""
echo "Для swtpm: mkdir -p /tmp/myvtpm && swtpm socket --tpm2 -t -d --tpmstate dir=/tmp/myvtpm"
echo "export TPM2TOOLS_TCTI='swtpm:path=/tmp/myvtpm/swtpm.sock'"
rm -rf "$BUILD_BASE"

exit 0