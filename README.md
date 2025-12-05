```bash
sudo apt update
sudo apt install python3.10-venv python3.10-dev -y
chmod +x install.sh
./install.sh
```


```bash
# Первый раз — создаём диск
./app.py create secret_docs
# → просит PIN (можно просто Enter)

# Открываем диск
./app.py open secret_docs # просит PIN, если задан
# в текущей директории появится папка ./secret_docs

# Закрываем диск
./app.py close secret_docs

# Список всех созданных дисков
./app.py list
```