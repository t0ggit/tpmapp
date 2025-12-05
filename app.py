#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TPM2 + FAPI + LUKS2 encrypted virtual disk manager
Работает на Ubuntu (qemu+swtpm). Проверено с tpm2-tss >= 3.0.0 и tpm2-pytss >= 2.x
"""

import os
import sys
import getpass
import subprocess
import json
from pathlib import Path
from tpm2_pytss import FAPI, PolicyPCR, PolicyAuthValue
from Crypto.Random import get_random_bytes

# CONFIG
MOUNT_BASE = Path.cwd()
DISK_SIZE = "100M"
KEY_SIZE = 64  # bytes (512 бит)
TPM_PATH_PREFIX = "/HS/SRK/luks_disk_"
PCR_LIST = [0, 1, 2, 3, 4, 5, 6, 7]

def run(cmd, input_data=None, **kwargs):
    if input_data is not None and not isinstance(input_data, (bytes, bytearray)):
        input_data = str(input_data).encode()
    subprocess.run(cmd, check=True, input=input_data, **kwargs)

def ask_pin():
    pin = getpass.getpass("Задайте дополнительный PIN (Enter = без PIN): ")
    if not pin:
        return None
    pin2 = getpass.getpass("Повторите PIN: ")
    if pin != pin2:
        print("PIN не совпадают")
        sys.exit(1)
    return pin.encode()

def create(name: str):
    img = MOUNT_BASE / f"{name}.img"
    tpm_path = TPM_PATH_PREFIX + name

    if img.exists():
        print(f"Диск {name} уже существует")
        return

    print(f"Создаём образ {DISK_SIZE} → {img.name}")
    run(["truncate", "-s", DISK_SIZE, str(img)])
    run(["chmod", "0600", str(img)])

    luks_key = get_random_bytes(KEY_SIZE)
    pin = ask_pin()

    print("Запечатываем ключ в TPM (PCR 0–7 + PIN)…")
    try:
        with FAPI() as fapi:
            # PolicyPCR принимает list
            policy = PolicyPCR(pcr_list=PCR_LIST)
            if pin:
                policy = policy & PolicyAuthValue()

            # create_seal принимает path (str/bytes) и data=bytes
            # используем путь как строку
            fapi.create_seal(path=tpm_path, data=luks_key, policy=policy)
    except Exception as e:
        print("ОШИБКА при работе с FAPI:", type(e).__name__, e)
        print("Убедитесь, что libtss2-fapi установлен и FAPI доступен.")
        sys.exit(1)

    print("Инициализируем LUKS2 контейнер (используем ключ из TPM)...")
    # Используем --key-file - чтобы передать бинарный ключ через stdin и --batch-mode
    try:
        run([
            "cryptsetup", "luksFormat", "--type", "luks2",
            "--key-file", "-", "--batch-mode", str(img)
        ], input_data=luks_key)
    except subprocess.CalledProcessError as e:
        print("Не удалось выполнить luksFormat:", e)
        sys.exit(1)

    print("Добавляем TPM2-токен в LUKS (cryptsetup token add)...")
    # cryptsetup token add <luks-device> --token-type tpm2 --tpm2-path <path> --tpm2-pcr-list "0;1;..."
    # Передаём ключ через stdin
    tpm2_pcr_arg = ";".join(map(str, PCR_LIST))
    try:
        run([
            "cryptsetup", "token", "add", str(img),
            "--token-type", "tpm2",
            "--tpm2-path", tpm_path,
            "--tpm2-pcr-list", tpm2_pcr_arg,
            "--key-file", "-"
        ], input_data=luks_key)
    except subprocess.CalledProcessError as e:
        print("Не удалось добавить TPM токен в LUKS:", e)
        sys.exit(1)

    print(f"\nГотово! Диск {name} защищён TPM + PCR")
    print(f"   ./app.py open {name}\n")

def open_disk(name: str):
    img = MOUNT_BASE / f"{name}.img"
    mnt = MOUNT_BASE / name
    mapper = f"tpmcrypt_{name}"

    if not img.exists():
        print(f"Диск {name} не найден")
        return

    mnt.mkdir(parents=True, exist_ok=True)
    if any(mnt.iterdir()):
        print(f"Уже открыт в ./{name}")
        return

    print(f"Открываем {name} через TPM…")
    # В зависимости от версии cryptsetup и конфигурации, команда может отличаться.
    # Пробуем token-only режим (использует внешний токен)
    try:
        run([
            "cryptsetup", "open", "--type", "luks2",
            "--token-only", str(img), mapper
        ])
    except subprocess.CalledProcessError:
        # fallback: попробовать без --token-only (некоторые cryptsetup старых версий)
        try:
            run(["cryptsetup", "open", "--type", "luks2", str(img), mapper])
        except subprocess.CalledProcessError as e:
            print("Не удалось открыть: PCR изменились или неверный PIN/токен.")
            sys.exit(1)

    run(["mount", f"/dev/mapper/{mapper}", str(mnt)])
    run(["chown", f"{os.getuid()}:{os.getgid()}", str(mnt)])
    print(f"Смонтирован в ./{name}")

def close_disk(name: str):
    mapper = f"tpmcrypt_{name}"
    mnt = MOUNT_BASE / name
    if mnt.exists():
        try:
            run(["umount", str(mnt)])
        except subprocess.CalledProcessError:
            print("Ошибка при отмонтировании (возможно не был смонтирован).")
    try:
        run(["cryptsetup", "close", mapper])
    except subprocess.CalledProcessError:
        print("Ошибка при закрытии mapper (возможно уже закрыт).")
    print(f"{name} закрыт")

def list_disks():
    for img in MOUNT_BASE.glob("*.img"):
        name = img.stem
        mounted = False
        mnt_dir = (MOUNT_BASE / name)
        if mnt_dir.exists():
            try:
                mounted = any(mnt_dir.iterdir())
            except Exception:
                mounted = False
        print(f"{'OPEN' if mounted else 'CLOSED'} {name.ljust(20)} {img.name}")

# CLI
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Использование: {Path(sys.argv[0]).name} <create|open|close|list> [имя]")
        sys.exit(1)

    cmd = sys.argv[1].lower()
    name = sys.argv[2] if len(sys.argv) >= 3 else None

    if cmd == "create" and name:
        create(name)
    elif cmd == "open" and name:
        open_disk(name)
    elif cmd == "close" and name:
        close_disk(name)
    elif cmd == "list":
        list_disks()
    else:
        print("Неизвестная команда")
        sys.exit(1)
