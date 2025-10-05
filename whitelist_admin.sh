#!/bin/bash

# Скрипт администрирования whitelist для доступа к серверу
# Автор: Администратор безопасности
# Дата: $(date)

# Настройки
WHITELIST_FILE="/etc/firewall/whitelist.conf"
IPTABLES_CHAIN="WHITELIST_INPUT"
LOG_FILE="/var/log/whitelist_admin.log"

# Постоянные IP-адреса (всегда должны иметь доступ)
PERMANENT_IPS=(
    "45.67.230.62"
    "109.225.41.64"
)

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция логирования
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Ошибка: Скрипт должен запускаться с правами root${NC}"
        echo "Используйте: sudo $0"
        exit 1
    fi
}

# Создание необходимых директорий и файлов
setup_environment() {
    # Создаем директорию для конфигурации
    mkdir -p "$(dirname "$WHITELIST_FILE")"
    
    # Создаем файл whitelist если его нет
    if [[ ! -f "$WHITELIST_FILE" ]]; then
        touch "$WHITELIST_FILE"
        chmod 600 "$WHITELIST_FILE"
    fi
    
    # Создаем директорию для логов
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

# Создание цепочки iptables
create_iptables_chain() {
    # Проверяем существует ли цепочка
    if ! iptables -L "$IPTABLES_CHAIN" >/dev/null 2>&1; then
        echo -e "${BLUE}Создание цепочки iptables: $IPTABLES_CHAIN${NC}"
        iptables -N "$IPTABLES_CHAIN"
        log_action "Создана цепочка iptables: $IPTABLES_CHAIN"
    fi
    
    # Добавляем правило для перехода к нашей цепочке если его нет
    if ! iptables -C INPUT -j "$IPTABLES_CHAIN" >/dev/null 2>&1; then
        iptables -I INPUT 1 -j "$IPTABLES_CHAIN"
        log_action "Добавлено правило перехода к цепочке $IPTABLES_CHAIN"
    fi
}

# Очистка цепочки iptables
flush_iptables_chain() {
    echo -e "${YELLOW}Очистка цепочки iptables: $IPTABLES_CHAIN${NC}"
    iptables -F "$IPTABLES_CHAIN" 2>/dev/null || true
    log_action "Очищена цепочка iptables: $IPTABLES_CHAIN"
}

# Добавление IP в whitelist
add_ip() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        echo -e "${RED}Ошибка: IP-адрес не указан${NC}"
        return 1
    fi
    
    # Проверка валидности IP или подсети
    if ! validate_ip "$ip"; then
        echo -e "${RED}Ошибка: Неверный формат IP-адреса или подсети: $ip${NC}"
        return 1
    fi
    
    # Проверяем, не добавлен ли уже IP
    if grep -qx "$ip" "$WHITELIST_FILE"; then
        echo -e "${YELLOW}IP-адрес $ip уже в whitelist${NC}"
        return 0
    fi
    
    # Добавляем IP в файл
    echo "$ip" >> "$WHITELIST_FILE"
    
    # Добавляем правило в iptables
    iptables -A "$IPTABLES_CHAIN" -s "$ip" -j ACCEPT
    
    echo -e "${GREEN}✓ Добавлен IP: $ip${NC}"
    log_action "Добавлен IP в whitelist: $ip"
}

# Удаление IP из whitelist
remove_ip() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        echo -e "${RED}Ошибка: IP-адрес не указан${NC}"
        return 1
    fi
    
    # Проверяем, является ли IP постоянным
    for permanent_ip in "${PERMANENT_IPS[@]}"; do
        if [[ "$ip" == "$permanent_ip" ]]; then
            echo -e "${RED}Ошибка: Нельзя удалить постоянный IP: $ip${NC}"
            return 1
        fi
    done
    
    # Удаляем из файла
    grep -v "^$ip$" "$WHITELIST_FILE" > "${WHITELIST_FILE}.tmp"
    mv "${WHITELIST_FILE}.tmp" "$WHITELIST_FILE"
    
    echo -e "${GREEN}✓ Удален IP: $ip${NC}"
    log_action "Удален IP из whitelist: $ip"
}

# Валидация IP-адреса или подсети
validate_ip() {
    local ip="$1"
    
    # Проверка IP-адреса
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    
    # Проверка подсети (CIDR)
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local net_ip="${ip%/*}"
        local mask="${ip#*/}"
        
        if [[ $mask -gt 32 ]] || [[ $mask -lt 1 ]]; then
            return 1
        fi
        
        IFS='.' read -ra ADDR <<< "$net_ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    
    return 1
}

# Загрузка whitelist в iptables
load_whitelist() {
    echo -e "${BLUE}Загрузка whitelist в iptables...${NC}"
    
    # Очищаем цепочку
    flush_iptables_chain
    
    # Добавляем локальный доступ
    iptables -A "$IPTABLES_CHAIN" -i lo -j ACCEPT
    iptables -A "$IPTABLES_CHAIN" -s 127.0.0.1 -j ACCEPT
    
    # Добавляем постоянные IP
    for ip in "${PERMANENT_IPS[@]}"; do
        iptables -A "$IPTABLES_CHAIN" -s "$ip" -j ACCEPT
        echo -e "${GREEN}✓ Постоянный IP: $ip${NC}"
    done
    
    # Добавляем IP из файла whitelist
    if [[ -f "$WHITELIST_FILE" ]]; then
        while IFS= read -r ip; do
            if [[ -n "$ip" ]] && [[ ! "$ip" =~ ^# ]]; then
                iptables -A "$IPTABLES_CHAIN" -s "$ip" -j ACCEPT
                echo -e "${GREEN}✓ Загружен IP: $ip${NC}"
            fi
        done < "$WHITELIST_FILE"
    fi
    
    # Добавляем правило для блокировки всех остальных
    iptables -A "$IPTABLES_CHAIN" -j DROP
    
    log_action "Whitelist загружен в iptables"
}

# Показать текущий whitelist
show_whitelist() {
    echo -e "${BLUE}=== ТЕКУЩИЙ WHITELIST ===${NC}"
    echo -e "${YELLOW}Постоянные IP-адреса:${NC}"
    for ip in "${PERMANENT_IPS[@]}"; do
        echo -e "${GREEN}  $ip (постоянный)${NC}"
    done
    
    echo -e "${YELLOW}Дополнительные IP-адреса:${NC}"
    if [[ -f "$WHITELIST_FILE" ]] && [[ -s "$WHITELIST_FILE" ]]; then
        while IFS= read -r ip; do
            if [[ -n "$ip" ]] && [[ ! "$ip" =~ ^# ]]; then
                echo -e "  $ip"
            fi
        done < "$WHITELIST_FILE"
    else
        echo "  (нет дополнительных IP)"
    fi
    
    echo
    echo -e "${BLUE}=== ТЕКУЩИЕ ПРАВИЛА IPTABLES ===${NC}"
    iptables -L "$IPTABLES_CHAIN" -n --line-numbers 2>/dev/null || echo "Цепочка не создана"
}

# Показать статистику
show_stats() {
    echo -e "${BLUE}=== СТАТИСТИКА ===${NC}"
    local permanent_count=${#PERMANENT_IPS[@]}
    local additional_count=0
    
    if [[ -f "$WHITELIST_FILE" ]]; then
        additional_count=$(grep -c "^[^#]" "$WHITELIST_FILE" 2>/dev/null || echo 0)
    fi
    
    local total_count=$((permanent_count + additional_count))
    
    echo "Постоянных IP: $permanent_count"
    echo "Дополнительных IP: $additional_count" 
    echo "Всего IP в whitelist: $total_count"
    
    echo
    echo -e "${BLUE}Последние действия:${NC}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 5 "$LOG_FILE"
    else
        echo "Логов нет"
    fi
}

# Создание резервной копии
backup_config() {
    local backup_file="/etc/firewall/whitelist_backup_$(date +%Y%m%d_%H%M%S).conf"
    
    if [[ -f "$WHITELIST_FILE" ]]; then
        cp "$WHITELIST_FILE" "$backup_file"
        echo -e "${GREEN}✓ Резервная копия создана: $backup_file${NC}"
        log_action "Создана резервная копия: $backup_file"
    else
        echo -e "${YELLOW}Нет файла для резервного копирования${NC}"
    fi
}

# Восстановление из резервной копии
restore_config() {
    echo -e "${BLUE}Доступные резервные копии:${NC}"
    local backups=($(ls /etc/firewall/whitelist_backup_*.conf 2>/dev/null))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Резервных копий не найдено${NC}"
        return 1
    fi
    
    for i in "${!backups[@]}"; do
        echo "$((i+1)). ${backups[$i]}"
    done
    
    echo -n "Выберите номер для восстановления (или 0 для отмены): "
    read -r choice
    
    if [[ "$choice" -gt 0 ]] && [[ "$choice" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((choice-1))]}"
        cp "$selected_backup" "$WHITELIST_FILE"
        echo -e "${GREEN}✓ Конфигурация восстановлена из: $selected_backup${NC}"
        log_action "Конфигурация восстановлена из: $selected_backup"
        
        echo "Перезагрузить whitelist в iptables? (y/n): "
        read -r reload_choice
        if [[ "$reload_choice" =~ ^[Yy]$ ]]; then
            load_whitelist
        fi
    fi
}

# Интерактивное добавление IP
interactive_add() {
    echo -e "${BLUE}=== ДОБАВЛЕНИЕ IP В WHITELIST ===${NC}"
    echo -n "Введите IP-адрес или подсеть (например: 192.168.1.100 или 192.168.1.0/24): "
    read -r ip
    
    if [[ -n "$ip" ]]; then
        add_ip "$ip"
        
        echo "Перезагрузить whitelist в iptables? (y/n): "
        read -r reload_choice
        if [[ "$reload_choice" =~ ^[Yy]$ ]]; then
            load_whitelist
        fi
    fi
}

# Интерактивное удаление IP
interactive_remove() {
    echo -e "${BLUE}=== УДАЛЕНИЕ IP ИЗ WHITELIST ===${NC}"
    
    if [[ ! -f "$WHITELIST_FILE" ]] || [[ ! -s "$WHITELIST_FILE" ]]; then
        echo -e "${YELLOW}Whitelist пуст${NC}"
        return 0
    fi
    
    echo "Текущие дополнительные IP:"
    local ips=()
    while IFS= read -r ip; do
        if [[ -n "$ip" ]] && [[ ! "$ip" =~ ^# ]]; then
            ips+=("$ip")
        fi
    done < "$WHITELIST_FILE"
    
    if [[ ${#ips[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Нет дополнительных IP для удаления${NC}"
        return 0
    fi
    
    for i in "${!ips[@]}"; do
        echo "$((i+1)). ${ips[$i]}"
    done
    
    echo -n "Выберите номер IP для удаления (или 0 для отмены): "
    read -r choice
    
    if [[ "$choice" -gt 0 ]] && [[ "$choice" -le ${#ips[@]} ]]; then
        remove_ip "${ips[$((choice-1))]}"
        
        echo "Перезагрузить whitelist в iptables? (y/n): "
        read -r reload_choice
        if [[ "$reload_choice" =~ ^[Yy]$ ]]; then
            load_whitelist
        fi
    fi
}

# Показать помощь
show_help() {
    echo -e "${BLUE}=== СКРИПТ АДМИНИСТРИРОВАНИЯ WHITELIST ===${NC}"
    echo
    echo "Использование: $0 [команда] [параметры]"
    echo
    echo "Команды:"
    echo "  add <IP>          - Добавить IP или подсеть в whitelist"
    echo "  remove <IP>       - Удалить IP из whitelist"
    echo "  load              - Загрузить whitelist в iptables"
    echo "  show              - Показать текущий whitelist"
    echo "  stats             - Показать статистику"
    echo "  backup            - Создать резервную копию"
    echo "  restore           - Восстановить из резервной копии"
    echo "  flush             - Очистить цепочку iptables"
    echo "  interactive       - Интерактивный режим"
    echo "  help              - Показать эту справку"
    echo
    echo "Примеры:"
    echo "  $0 add 192.168.1.100"
    echo "  $0 add 10.0.0.0/24"
    echo "  $0 remove 192.168.1.100"
    echo "  $0 load"
    echo
    echo -e "${YELLOW}Постоянные IP (нельзя удалить):${NC}"
    for ip in "${PERMANENT_IPS[@]}"; do
        echo "  $ip"
    done
}

# Интерактивное меню
interactive_menu() {
    while true; do
        echo
        echo -e "${BLUE}=== УПРАВЛЕНИЕ WHITELIST ===${NC}"
        echo "1. Показать текущий whitelist"
        echo "2. Добавить IP"
        echo "3. Удалить IP"
        echo "4. Загрузить whitelist в iptables"
        echo "5. Показать статистику"
        echo "6. Создать резервную копию"
        echo "7. Восстановить из резервной копии"
        echo "8. Очистить цепочку iptables"
        echo "9. Выход"
        echo
        echo -n "Выберите действие (1-9): "
        read -r choice
        
        case $choice in
            1) show_whitelist ;;
            2) interactive_add ;;
            3) interactive_remove ;;
            4) load_whitelist ;;
            5) show_stats ;;
            6) backup_config ;;
            7) restore_config ;;
            8) flush_iptables_chain ;;
            9) break ;;
            *) echo -e "${RED}Неверный выбор${NC}" ;;
        esac
    done
}

# Основная функция
main() {
    check_root
    setup_environment
    create_iptables_chain
    
    case "${1:-}" in
        "add")
            add_ip "$2"
            ;;
        "remove")
            remove_ip "$2"
            ;;
        "load")
            load_whitelist
            ;;
        "show")
            show_whitelist
            ;;
        "stats")
            show_stats
            ;;
        "backup")
            backup_config
            ;;
        "restore")
            restore_config
            ;;
        "flush")
            flush_iptables_chain
            ;;
        "interactive")
            interactive_menu
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            echo -e "${RED}Неизвестная команда: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Запуск основной функции
main "$@"