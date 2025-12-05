#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
TPM2 + FAPI + LUKS2 encrypted virtual disk manager
"""

import os
import sys
import getpass
import subprocess
from pathlib import Path
from tpm2_pytss import FAPI, PolicyPCR, PolicyAuthValue
from Crypto.Random import get_random_bytes

# =========================== CONFIG ===========================
MOUNT_BASE = Path.cwd()                   # где лежат .img и монтируются папки
DISK_SIZE = "100M"                        # размер нового образа
KEY_SIZE = 64                             # 512 бит — максимум для LUKS2
TPM_PATH_PREFIX = "/HS/SRK/luks_disk_"    # путь в TPM
PCR_LIST = [0, 1, 2, 3, 4, 5, 6, 7]       # измеряем всю загрузочную цепочку
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
    return pin

def create(name: str):
    img = MOUNT_BASE / f"{name}.img"
    mnt = MOUNT_BASE / name
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
        policy = PolicyPCR(PCR_LIST)
        if pin:
            policy &= PolicyAuthValue(pin.encode())
        fapi.create_seal(tpm_path, luks_key, policy)

    print("Инициализируем LUKS2 + добавляем TPM-токен")
    run(["cryptsetup", "luksFormat", "--type", "luks2", str(img)], input=b"YES\n")
    run([
        "cryptsetup", "token", "add", str(img),
        "--token-type", "tpm2",
        "--tpm2-seal", f"path={tpm_path}",
        "--tpm2-pcr-list", ";".join(map(str, PCR_LIST))
    ], input=luks_key)

    print(f"\nГотово! Диск {name} защищён TPM")
    print(f"   ./app.py open {name}")
    print(f"   ./app.py close {name}\n")

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
    run([
        "cryptsetup", "open", str(img), mapper,
        "--token-only", "--type", "luks2"
    ])

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
        print(f"{'OPEN' if mounted else 'CLOSED'}  {name.ljust(20)}  {img.name}")

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