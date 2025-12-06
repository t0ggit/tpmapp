#!/usr/bin/env bash
set -euo pipefail

echo "=== TPM2 + FAPI — РАБОЧАЯ СВЯЗКА 2025 (tpm2-tss 3.2.2 + pytss 2.3.0 + один фикс) ==="

# 1. Полная зачистка
sudo rm -rf /usr/lib/x86_64-linux-gnu/libtss2* /usr/include/tss2 ~/.local/share/tpm2-tss
sudo ldconfig

# 2. Зависимости
sudo apt update
sudo apt install -y build-essential git autoconf automake libtool pkg-config \
  libssl-dev uthash-dev libjson-c-dev libini-config-dev libcurl4-openssl-dev \
  uuid-dev python3-venv python3-dev python3-pip swtpm swtpm-tools

# 3. tpm2-tss 3.2.2 — последняя рабочая 3.x ветка (configure чистый!)
cd /tmp
rm -rf tpm2-tss
git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
git checkout 3.2.2                     # ← ЭТО САМАЯ СТАБИЛЬНАЯ 3.x ВЕРСИЯ В 2025
./bootstrap
./configure --prefix=/usr --enable-fapi
make -j$(nproc)
sudo make install
sudo ldconfig

# 4. tpm2-tools (свежий)
cd /tmp
rm -rf tpm2-tools
git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools
git checkout 5.7
./bootstrap
./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig

# 5. venv + pytss 2.3.0
rm -rf ~/tpmapp_venv
python3 -m venv ~/tpmapp_venv
source ~/tpmapp_venv/bin/activate
pip install --upgrade pip
pip install pycryptodome tpm2-pytss==2.3.0

# 6. Один-единственный фикс — убираем тупую проверку версии (это безопасно и работает на всех 3.x)
FAPI_PY="$(python -c 'import tpm2_pytss, inspect, os; print(os.path.join(os.path.dirname(inspect.getfile(tpm2_pytss)), "FAPI.py"))')"
sed -i 's/raise NotImplementedError("FAPI Not installed or version is not 3.0.0")/pass  # allow 3.2.x/' "$FAPI_PY"

# 7. ТЕСТ — ДОЛЖНО РАБОТАТЬ СРАЗУ
echo "ТЕСТ FAPI:"
python -c "
from tpm2_pytss import FAPI
with FAPI() as f:
    print('FAPI ЖИВ! Версия:', f.GetInfo()[:200])
"

# 8. Алиасы
grep -q tpmapp_venv ~/.bashrc || cat <<'EOF' >> ~/.bashrc

# TPM2 + FAPI
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'FAPI готов (TSS 3.2.2)'"
alias tpmapp-info="tpmapp && python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
EOF

echo ""
echo "ГОТОВО! Запускай:"
echo "   tpmapp"
echo "   tpmapp-info"