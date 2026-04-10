# myvless — VLESS + Reality + 3x-ui

## Установка на чистый сервер (Ubuntu 24.04)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SkyTMT/myvless/main/setup.sh)
```

Скрипт:
- Установит Docker
- Настроит UFW, fail2ban, BBR
- Найдёт лучший SNI для твоей страны
- Запустит 3x-ui в контейнере

## Переезд на новый сервер

Та же одна команда. Если хочешь перенести клиентов — скопируй папку `data/`:

```bash
scp -r /root/myvless/data root@НОВЫЙ_IP:/root/myvless/
```
