# Скрипт администрирования Whitelist для сервера

Этот скрипт предназначен для управления белым списком IP-адресов с помощью iptables во время соревнований Red Team vs Blue Team.

## Особенности

- ✅ Постоянные IP-адреса (45.67.230.62 и 109.225.41.64) - нельзя удалить
- ✅ Поддержка одиночных IP-адресов и подсетей (CIDR)
- ✅ Автоматическое создание и управление цепочкой iptables
- ✅ Резервное копирование и восстановление конфигурации
- ✅ Детальное логирование всех действий
- ✅ Интерактивный и командный режимы работы
- ✅ Валидация IP-адресов
- ✅ Цветной вывод для удобства

## Быстрая установка

```bash
# 1. Делаем скрипт исполняемым
chmod +x /home/akuma/Desktop/projects/kibers/st16/firewall/whitelist_admin.sh

# 2. Копируем systemd service (опционально)
sudo cp /home/akuma/Desktop/projects/kibers/st16/firewall/whitelist-firewall.service /etc/systemd/system/

# 3. Первый запуск и инициализация
sudo /home/akuma/Desktop/projects/kibers/st16/firewall/whitelist_admin.sh load

# 4. Включаем автозагрузку при перезагрузке (опционально)
sudo systemctl enable whitelist-firewall.service
sudo systemctl start whitelist-firewall.service
```

## Основные команды

### Просмотр whitelist
```bash
sudo ./whitelist_admin.sh show
```

### Добавление IP-адресов
```bash
# Добавить одиночный IP
sudo ./whitelist_admin.sh add 192.168.1.100

# Добавить подсеть
sudo ./whitelist_admin.sh add 10.0.0.0/24

# Добавить IP атакующей команды
sudo ./whitelist_admin.sh add 203.0.113.50
```

### Удаление IP-адресов
```bash
sudo ./whitelist_admin.sh remove 192.168.1.100
```

### Загрузка конфигурации в iptables
```bash
sudo ./whitelist_admin.sh load
```

### Просмотр статистики
```bash
sudo ./whitelist_admin.sh stats
```

## Интерактивный режим

Для удобного управления можно использовать интерактивное меню:

```bash
sudo ./whitelist_admin.sh interactive
```

## Резервное копирование

### Создание резервной копии
```bash
sudo ./whitelist_admin.sh backup
```

### Восстановление из резервной копии
```bash
sudo ./whitelist_admin.sh restore
```

## Сценарии использования для соревнований

### Подготовка к соревнованиям
```bash
# 1. Инициализация системы
sudo ./whitelist_admin.sh load

# 2. Добавление известных IP организаторов
sudo ./whitelist_admin.sh add 203.0.113.0/24

# 3. Создание резервной копии начальной конфигурации
sudo ./whitelist_admin.sh backup
```

### Во время соревнований
```bash
# Добавление IP участника Red Team для тестирования
sudo ./whitelist_admin.sh add 198.51.100.25

# Быстрый просмотр текущего статуса
sudo ./whitelist_admin.sh show

# Просмотр статистики и логов
sudo ./whitelist_admin.sh stats
```

### После инцидента
```bash
# Создание резервной копии текущего состояния
sudo ./whitelist_admin.sh backup

# Блокировка подозрительной подсети
sudo ./whitelist_admin.sh remove 198.51.100.0/24

# Перезагрузка правил
sudo ./whitelist_admin.sh load
```

## Файлы конфигурации

- **Конфигурация whitelist**: `/etc/firewall/whitelist.conf`
- **Логи**: `/var/log/whitelist_admin.log`
- **Резервные копии**: `/etc/firewall/whitelist_backup_YYYYMMDD_HHMMSS.conf`

## Структура iptables

Скрипт создает отдельную цепочку `WHITELIST_INPUT` в таблице filter, что позволяет:
- Изолированно управлять правилами whitelist
- Не конфликтовать с другими правилами iptables
- Легко очищать и перезагружать правила

## Постоянные IP-адреса

Следующие IP-адреса **всегда** имеют доступ и не могут быть удалены:
- `45.67.230.62`
- `109.225.41.64`

## Мониторинг и логи

Все действия логируются в файл `/var/log/whitelist_admin.log` с временными метками:

```bash
# Просмотр последних действий
sudo tail -f /var/log/whitelist_admin.log

# Просмотр логов за сегодня
sudo grep "$(date '+%Y-%m-%d')" /var/log/whitelist_admin.log
```

## Проверка работы

### Проверка активных правил iptables
```bash
sudo iptables -L WHITELIST_INPUT -n --line-numbers
```

### Тестирование подключения
```bash
# С разрешенного IP
ssh user@your_server

# Проверка логов подключений
sudo tail /var/log/auth.log
```

## Автоматизация

### Добавление нескольких IP из файла
```bash
# Создать файл со списком IP
cat > ips_to_add.txt << EOF
192.168.1.10
192.168.1.11
10.0.1.0/24
EOF

# Добавить все IP из файла
while read ip; do
    sudo ./whitelist_admin.sh add "$ip"
done < ips_to_add.txt

# Загрузить обновленную конфигурацию
sudo ./whitelist_admin.sh load
```

## Troubleshooting

### Проблемы с доступом
1. Проверьте, что постоянные IP добавлены:
   ```bash
   sudo ./whitelist_admin.sh show
   ```

2. Проверьте правила iptables:
   ```bash
   sudo iptables -L WHITELIST_INPUT -v -n
   ```

3. Проверьте логи:
   ```bash
   sudo tail -n 50 /var/log/whitelist_admin.log
   ```

### Восстановление доступа
Если потеряли доступ к серверу:
1. Получите физический/консольный доступ
2. Очистите правила: `sudo ./whitelist_admin.sh flush`
3. Или отключите службу: `sudo systemctl stop whitelist-firewall.service`

## Безопасность

- Скрипт требует права root для выполнения
- Все конфигурационные файлы имеют ограниченные права доступа (600)
- Постоянные IP-адреса защищены от случайного удаления
- Все действия логируются для аудита

## Системные требования

- Ubuntu/Debian Linux
- iptables
- bash 4.0+
- Права root (sudo)

Скрипт готов к использованию в соревнованиях Red Team vs Blue Team!