# CRM возврата покупателей

Этап 1: запускаемый Rails-каркас со стартовой страницей и PostgreSQL.
Аутентификация, покупатели, заказы, сегментация и рассылки пока не реализованы.

Стек: **Ruby 4.0.7**, **Rails 8.1.4**, **PostgreSQL 16**, Hotwire (Turbo,
Stimulus и Importmap). Версии зависимостей закреплены в `Gemfile.lock`.
Существующие `tasks.md`, `analysis.md`, `sources/` и Nix-окружение сохранены.

## Основной запуск: Docker Compose

Нужны Docker Engine и Docker Compose v2. Из корня проекта:

```bash
docker compose up --build -d
docker compose logs -f web
```

Откройте <http://localhost:3000/>. Проверка работоспособности:
<http://localhost:3000/up>. Первый запуск скачивает образы и устанавливает gems.
Compose ждёт healthcheck PostgreSQL; entrypoint выполняет `db:prepare`
перед запуском Rails. Это подготовка/миграция, **не сброс данных**.

Контейнер запускается в `development`, содержит тестовые зависимости и слушает
только `127.0.0.1` хоста. Это локальное демо, не production-deploy.
PostgreSQL не публикует порт на хосте. Копировать исходники в том не нужно;
после изменения кода повторите `docker compose up --build -d`.

В одном из проверенных окружений `docker` заменён на Podman/podman-compose.
Образ, HTTP, тесты и сохранность данных проверены через этот совместимый
runtime, но автоматический healthcheck Podman запускается вне хранилища
Podman и не видит контейнер. Для проверки его запускали вручную командой
`docker healthcheck run rshb_stipa_db_1`; системные настройки не менялись.
`docker compose restart` в podman-compose также дал гонку запуска зависимостей;
после повторного `up -d` данные сохранились. После `down` и нового `up`
сохранность данных тоже подтверждена.
Запуск без ручной помощи на настоящем Docker Compose v2 ещё нужно проверить.

`.env` необязателен. При необходимости скопируйте `.env.example` в `.env`
(не перезаписывайте существующий файл) и измените `PORT` или
`POSTGRES_PASSWORD`. Пароль должен состоять из URL-безопасных символов.
Настройки `.env` читает Compose, Rails сам этот файл не загружает.
Примерный пароль предназначен только для локального демо.
Изменение `POSTGRES_PASSWORD` не меняет пароль в уже созданном томе PostgreSQL.

### Проверки

```bash
docker compose config --quiet
curl --fail http://localhost:3000/up
curl --fail http://localhost:3000/
docker compose exec web bin/rails zeitwerk:check
docker compose exec -e RAILS_ENV=test web bin/rails db:prepare
docker compose exec -e RAILS_ENV=test web bin/rails test
```

При другом `PORT` используйте его в URL. В Compose приложение использует
`rshb_stipa_development`, тесты — отдельную `rshb_stipa_test` через
`TEST_DATABASE_URL`. Никогда не направляйте тесты на БД с нужными данными:
Rails может пересоздавать тестовую схему.

### Остановка и сохранность данных

```bash
docker compose restart
docker compose down
docker compose up -d
```

Данные PostgreSQL остаются в именованном томе `postgres_data` (Compose добавляет
префикс проекта). Не меняйте имя проекта/каталога при проверке сохранности.
**Не используйте `docker compose down -v`, `db:reset` или удаление тома**, если
данные нужно сохранить. Перезапуск web повторно вызывает безопасный `db:prepare`.

Проверка данных без добавления бизнес-моделей (временная служебная таблица):

```bash
docker compose exec db psql -U rshb_stipa -d rshb_stipa_development -c "CREATE TABLE foundation_persistence_probe (value text); INSERT INTO foundation_persistence_probe VALUES ('stage-1');"
docker compose down
docker compose up -d
docker compose exec db psql -U rshb_stipa -d rshb_stipa_development -c "SELECT value FROM foundation_persistence_probe;"
docker compose exec db psql -U rshb_stipa -d rshb_stipa_development -c "DROP TABLE foundation_persistence_probe;"
```

Ожидается `stage-1`. Выполняйте только в демобазе и если такого имени таблицы
ещё нет; после успешной проверки удаляется только созданная служебная таблица.

## Разработка с Nix

Существующий flake рассчитан на `x86_64-linux`. Нужны Nix с flakes и direnv:

```bash
direnv allow
# После загрузки окружения direnv (либо внутри nix develop):
db-up
bin/setup --skip-server
bin/rails server
```

`db-up` запускает только проектный PostgreSQL 16, не системный сервис.
`PGHOST` указывает на `tmp/pgsocket`, `PGDATA` — на `tmp/pgdata`.
Gems устанавливаются в `vendor/bundle`; эти каталоги исключены из Git и образа.
`bin/setup` устанавливает gems и выполняет `db:prepare`, не `db:reset`.
Остановка Rails — Ctrl+C, остановка локальной БД — `db-down`.
Не удаляйте `tmp/pgdata`, если нужны локальные данные.

```bash
RAILS_ENV=test bin/rails db:prepare
bin/rails test
bin/rails zeitwerk:check
```

Не запускайте Compose и локальный Rails на одном порту одновременно.

## Обычный локальный запуск без Nix

Установите Ruby 4.0.7, Bundler 4.0.20, PostgreSQL 16 и зависимости для сборки
gems: C/C++-компилятор, make, pkg-config, Git, заголовки libpq и libyaml.
PostgreSQL должен быть запущен; роль должна иметь право создавать БД.
Node.js не требуется для Importmap.

Пример для локальной роли `crm_dev` (заранее создайте её с правом CREATEDB):

```bash
export PGHOST=127.0.0.1
export PGPORT=5432
export PGUSER=crm_dev
# При парольной аутентификации задайте PGPASSWORD безопасным способом.
gem install bundler -v 4.0.20
bin/setup --skip-server
bin/rails server
```

Без `DATABASE_URL` используются `rshb_stipa_development` и `rshb_stipa_test`.
Для внешней БД можно задать `DATABASE_URL` с адресом БД приложения и
`TEST_DATABASE_URL` с адресом **другой** тестовой БД.
Если `TEST_DATABASE_URL` не задан, тесты используют
`postgresql:///rshb_stipa_test` и параметры libpq (`PGHOST`, `PGUSER` и другие),
а не `DATABASE_URL`. Проверки те же, что в разделе Nix, без `db-up`.

## Границы этапа

Реализован только этап 1 изначального плана разработки.
Бизнес-функции этапов 2–9 и production-развёртывание в этот каркас не входят.
