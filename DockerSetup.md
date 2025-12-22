# Инструкция по запуску через Docker Compose

## Быстрый старт

1. **Запуск всех сервисов:**
   ```bash
   docker-compose up -d
   ```

2. **Просмотр логов:**
   ```bash
   docker-compose logs -f web
   ```

3. **Остановка:**
   ```bash
   docker-compose down
   ```

## Доступ к приложению

- **Web приложение:** http://localhost:8000
- **База данных:** localhost:5432

## Переменные окружения

Можно создать файл `.env` для настройки:

```env
SECRET_KEY=your_secret_key_here
DB_HOST=postgres
DB_PORT=5432
DB_NAME=restaurant_management
DB_USER=restaurant_admin
DB_PASSWORD=secure_password_123
FLASK_DEBUG=False
```

## Изменения в проекте

### 1. Docker Compose
- Добавлен сервис `web` для запуска Flask приложения
- Настроен healthcheck для PostgreSQL
- Web приложение ждет готовности БД перед запуском

### 2. Удалена регистрация через GUI
- Удален эндпоинт `/signup`
- Удален файл `templates/signup.html`
- Удалена ссылка на регистрацию из `login.html`
- **Создание пользователей доступно только админу** через вкладку "Users" в dashboard

### 3. Безопасность
- Добавлена валидация username при создании пользователя админом
- Все SQL запросы защищены от injection

## Сборка образа

```bash
docker-compose build
```

## Пересборка после изменений

```bash
docker-compose up -d --build
```

