#!/usr/bin/env bash
set -euo pipefail

# install_deps_improved.sh
# Универсальный установщик для qemu+swtpm (Ubuntu). 
# - пытается установить пакеты из репо (libtss2-*)
# - если библиотеки FAPI < 3.0.0 или отсутствуют -> собирает tpm2-tss из исходников (meson).
# - ставит swtpm, tpm2-tools, tpm2-pytss в venv
# - выполняет самотест FAPI -> GetInfo

# Конфигурация:
VENV_DIR="$HOME/tpmapp_venv"
TPM2_TSS_INSTALL_PREFIX="/usr/local"
BUILD_DIR="/tmp/tpm2-build"
PYTHON_BIN="python3"

echo "=== TPM2 LUKS FAPI — улучшенный установщик ==="

sudo apt update

echo "1) Устанавливаем общие зависимости (build tools, swtpm, python venv и т.п.)"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    build-essential git pkg-config meson ninja-build autoconf-archive \
    libcmocka-dev libssl-dev libjson-c-dev libini-config-dev libcurl4-openssl-dev \
    libtool automake autoconf doxygen python3-venv python3-dev python3-pip \
    swtpm swtpm-tools tpm2-tools jq || true

# Ensure universe / updates are enabled (so libtss2 packages available on jammy)
echo "Убедимся, что репозитории enabled..."
sudo apt install -y software-properties-common
sudo add-apt-repository -y universe || true
sudo add-apt-repository -y main || true
sudo apt update

echo "2) Попытка установки готовых пакетов libtss2 из репо (runtime + dev)"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    libtss2-dev libtss2-fapi1 libtss2-tcti-swtpm libtss2-esys-dev || true

# Проверка версии libtss2-fapi
echo "3) Проверяем установленную версию libtss2-fapi (если есть)..."
FAPI_VER_OK=0
if ldconfig -p | grep -q "libtss2-fapi"; then
    # получаем SONAME -> затем dpkg-query (если пакет установлен)
    if dpkg -s libtss2-fapi1 2>/dev/null | grep -E '^Version:' >/dev/null 2>&1; then
        pkgver=$(dpkg -s libtss2-fapi1 2>/dev/null | awk '/^Version:/ {print $2}')
        echo "Найден пакет libtss2-fapi1 версии: $pkgver"
        # простая проверка: версия >= 3.0.0
        ver_major=$(echo "$pkgver" | cut -d. -f1)
        if [ "$ver_major" -ge 3 ]; then
            FAPI_VER_OK=1
        fi
    else
        echo "libtss2-fapi1 не найден как пакет или версия неизвестна."
    fi
else
    echo "LD cache не видит libtss2-fapi."
fi

# Если системная версия не подходит -> соберём tpm2-tss (включая fapi) в /usr/local
if [ "$FAPI_VER_OK" -eq 0 ]; then
    echo "4) Сборка tpm2-tss из исходников (libtss2 >= 3.0.0). Это займёт некоторое время."
    echo "   (Будет установлен в $TPM2_TSS_INSTALL_PREFIX)"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Clone tpm2-tss
    if [ ! -d "$BUILD_DIR/tpm2-tss" ]; then
        git clone --depth 1 https://github.com/tpm2-software/tpm2-tss.git
    fi
    cd tpm2-tss
    git pull --ff-only || true

    meson setup build --prefix="$TPM2_TSS_INSTALL_PREFIX" -Dwith_fapi=true || meson configure build -Dwith_fapi=true || true
    meson compile -C build -j"$(nproc)"
    sudo meson install -C build

    # Optional: build/install tpm2-tools (recommended)
    cd "$BUILD_DIR"
    if [ ! -d "$BUILD_DIR/tpm2-tools" ]; then
        git clone --depth 1 https://github.com/tpm2-software/tpm2-tools.git
    fi
    cd tpm2-tools
    git pull --ff-only || true
    ./bootstrap || true
    mkdir -p build && cd build
    ../configure --with-tcti=swtpm --prefix="$TPM2_TSS_INSTALL_PREFIX"
    make -j"$(nproc)" || true
    sudo make install || true

    # обновим кэш библиотек
    sudo ldconfig
fi

echo "5) Создаём изолированное виртуальное окружение и ставим python-зависимости"
rm -rf "$VENV_DIR"
$PYTHON_BIN -m venv "$VENV_DIR"
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip setuptools wheel
# tpm2-pytss wheel обычно требует dev-headers for tpm2-tss; если библиотеки в /usr/local, ldconfig уже обновлён
pip install --no-cache-dir tpm2-pytss pycryptodome

echo "6) Проверка: импорт FAPI и GetInfo"
python - <<'PY'
import sys, json
from tpm2_pytss import FAPI
try:
    with FAPI() as fapi:
        info = fapi.GetInfo()
        # GetInfo может вернуть JSON string; попытка распарсить
        try:
            info_j = json.loads(info)
        except Exception:
            info_j = {"raw": str(info)}
        print("FAPI GetInfo OK:", json.dumps(info_j, indent=2, ensure_ascii=False))
except NotImplementedError as e:
    print("FAPI отсутствует или версия некорректна:", e)
    sys.exit(2)
except Exception as e:
    print("Ошибка при инициализации FAPI:", type(e).__name__, e)
    sys.exit(3)
PY

DEACT_MSG=""
if [ "$VENV_DIR" = "$HOME/tpmapp_venv" ]; then
    # добавим алиасы только если ещё нет
    if ! grep -q "tpmapp_venv" "$HOME/.bashrc" 2>/dev/null; then
        cat <<'EOF' >> "$HOME/.bashrc"
# === TPM2 LUKS FAPI приложение ===
alias tpmapp="source ~/tpmapp_venv/bin/activate && echo 'TPM app environment активировано'"
alias tpmapp-create="tpmapp && python ~/tpmapp/app.py create"
alias tpmapp-open="tpmapp && python ~/tpmapp/app.py open"
alias tpmapp-close="tpmapp && python ~/tpmapp/app.py close"
EOF
        echo "Алиасы добавлены в ~/.bashrc"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "ГОТОВО."
echo "Активируйте окружение: source $VENV_DIR/bin/activate"
echo "Проверка FAPI: source $VENV_DIR/bin/activate && python -c 'from tpm2_pytss import FAPI; print(FAPI().GetInfo())'"
echo "Если проверка не проходит — посмотрите вывод выше (ошибки сборки/ldconfig)."
echo "════════════════════════════════════════════════════════════"
