#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TPM2 + FAPI + LUKS2 encrypted virtual disk manager
Работает на Ubuntu 22.04 с tpm2-tss 4.1.2 и tpm2-pytss 2.3.0+
"""

import os
import sys
import getpass
import subprocess
import json
from pathlib import Path
from tpm2_pytss import FAPI, PolicyPCR, PolicyAuthValue, TPM2B_PUBLIC_KEY_RSA
from Crypto.Random import get_random_bytes

# =========================== CONFIG ===========================
MOUNT_BASE = Path.cwd()
DISK_SIZE = "100M"
KEY_SIZE = 64  # 512 бит
TPM_PATH_PREFIX = "/HS/SRK/luks_disk_"
PCR_LIST = [0, 1, 2, 3, 4, 5, 6, 7]
# ==============================================================

def run(cmd, **kwargs):
    subprocess.run(cmd, check=True, **kwargs)

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
    with FAPI() as fapi:
        # Правильный способ создать политику
        policy = PolicyPCR(pcr_list=PCR_LIST)
        if pin:
            policy = policy & PolicyAuthValue()

        # create_seal теперь принимает bytes и policy как отдельный аргумент
        fapi.create_seal(
            path=tpm_path,
            data=luks_key,
            policy=policy  # или policy=policy.to_dict() в старых версиях
        )

    print("Инициализируем LUKS2 контейнер")
    run(["cryptsetup", "luksFormat", "--type", "luks2", str(img)], input=b"YES\n")

    print("Добавляем TPM2-токен в LUKS")
    # cryptsetup умеет читать из FAPI напрямую
    run([
        "cryptsetup", "token", "add", str(img),
        "--token-type", "tpm2",
        "--tpm2-path", tpm_path,
        "--tpm2-pcr-list", ";".join(map(str, PCR_LIST))
    ], input=luks_key)

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
    try:
        run([
            "cryptsetup", "open", str(img), mapper,
            "--token-only-token", "--type", "luks2"
        ])
    except subprocess.CalledProcessError as e:
        print("Не удалось открыть: PCR изменились или неверный PIN")
        sys.exit(1)

    run(["mount", f"/dev/mapper/{mapper}", str(mnt)])
    run(["chown", f"{os.getuid()}:{os.getgid()}", str(mnt)])
    print(f"Смонтирован в ./{name}")

def close_disk(name: str):
    mapper = f"tpmcrypt_{name}"
    mnt = MOUNT_BASE / name
    run(["umount", str(mnt)])
    run(["cryptsetup", "close", mapper])
    print(f"{name} закрыт")

def list_disks():
    for img in MOUNT_BASE.glob("*.img"):
        name = img.stem
        mounted = any((MOUNT_BASE / name).iterdir()) if (MOUNT_BASE / name).exists() else False
        print(f"{'OPEN' if mounted else 'CLOSED'} {name.ljust(20)} {img.name}")

# ============================= CLI =============================
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