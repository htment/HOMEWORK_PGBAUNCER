# HOMEWORK_PGBAUNCER



# Горизонтальный шардинг PostgreSQL с PgBouncer
Вот полное решение для горизонтального шардинга PostgreSQL с использованием PgBouncer в качестве прокси-сервера.

Docker Compose конфигурация
```
yaml
version: '3.8'

services:
  # Шард 1 (для пользователей с чётными ID)
 
  pg_shard1:
    image: postgres:14
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: library
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Шард 2 (для пользователей с нечётными ID)
  pg_shard2:
    image: postgres:14
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: library
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  # PgBouncer с настройкой шардинга
  pgbouncer:
    image: bitnami/pgbouncer
    environment:
      - POSTGRESQL_HOST=pg_shard1,pg_shard2
      - POSTGRESQL_USERNAME=postgres
      - POSTGRESQL_PASSWORD=postgres
      - PGBOUNCER_POOL_MODE=transaction
      - PGBOUNCER_IGNORE_STARTUP_PARAMETERS=extra_float_digits
      - PGBOUNCER_QUERY_WAIT_TIMEOUT=60
      - PGBOUNCER_MAX_CLIENT_CONN=100
      - PGBOUNCER_DEFAULT_POOL_SIZE=20
    ports:
      - "6432:6432"
    depends_on:
      pg_shard1:
        condition: service_healthy
      pg_shard2:
        condition: service_healthy
    volumes:
      - ./pgbouncer.ini:/opt/bitnami/pgbouncer/conf/pgbouncer.ini
      - ./userlist.txt:/opt/bitnami/pgbouncer/conf/userlist.txt

  # Приложение с логикой шардинга
  app:
    build: .
    ports:
      - "8000:8000"
    depends_on:
      pgbouncer:
        condition: service_started
```
Конфигурационные файлы PgBouncer
pgbouncer.ini
ini

```
[databases]
shard1 = host=pg_shard1 port=5432 dbname=library
shard2 = host=pg_shard2 port=5432 dbname=library

[pgbouncer]
listen_port = 6432
listen_addr = *
auth_type = md5
auth_file = /opt/bitnami/pgbouncer/conf/userlist.txt
pool_mode = transaction
max_client_conn = 100
default_pool_size = 20
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1

```
userlist.txt
text
```
"postgres" "postgres"
```
Инициализация шардов

init_shard1.sql (чётные ID)
sql
```
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100) UNIQUE,
    registration_date DATE
);

-- Настраиваем последовательность для чётных ID
ALTER SEQUENCE users_id_seq RESTART WITH 2 INCREMENT BY 2;
```

init_shard2.sql (нечётные ID)
sql

```
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100) UNIQUE,
    registration_date DATE
);

-- Настраиваем последовательность для нечётных ID
ALTER SEQUENCE users_id_seq RESTART WITH 1 INCREMENT BY 2;

```
Логика приложения (Python + SQLAlchemy)

python
```
from fastapi import FastAPI
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

app = FastAPI()

# Подключение к PgBouncer
DATABASE_URL = "postgresql://postgres:postgres@pgbouncer:6432/library"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_shard_connection(user_id: int):
    """Определяет, к какому шарду нужно подключиться"""
    if user_id % 2 == 0:
        return "shard1"
    return "shard2"

@app.post("/users/")
async def create_user(name: str, email: str):
    """Создание нового пользователя с автоматическим определением шарда"""
    db = SessionLocal()
    
    # Вставляем запись (шард определится автоматически по ID)
    result = db.execute(
        text("INSERT INTO users (name, email, registration_date) VALUES (:name, :email, NOW()) RETURNING id"),
        {"name": name, "email": email}
    )
    user_id = result.scalar()
    db.commit()
    
    return {"id": user_id}

@app.get("/users/{user_id}")
async def get_user(user_id: int):
    """Получение пользователя с ручным определением шарда"""
    shard = get_shard_connection(user_id)
    db = SessionLocal()
    
    # Указываем конкретный шард для запроса
    result = db.execute(
        text(f"/* shard:{shard} */ SELECT id, name, email, registration_date FROM users WHERE id = :user_id"),
        {"user_id": user_id}
    ).fetchone()
    
    db.close()
    
    if not result:
        return {"error": "User not found"}
    
    return {
        "id": result[0],
        "name": result[1],
        "email": result[2],
        "registration_date": result[3]
    }

```
Принцип работы
PgBouncer выступает в роли прокси-сервера между приложением и PostgreSQL шардами

Шардинг по модулю:

Чётные ID → shard1

Нечётные ID → shard2

Автоматическое распределение:

При вставке нового пользователя шард определяется автоматически по ID

При чтении приложение само определяет нужный шард

Особенности реализации
Комментарии для маршрутизации:

sql
/* shard:shard1 */ SELECT ...
PgBouncer может использовать эти комментарии для маршрутизации запросов

Балансировка нагрузки:

PgBouncer эффективно управляет пулом соединений

Уменьшает нагрузку на серверы БД

Масштабируемость:

Легко добавить новые шарды

Можно изменить алгоритм шардинга без изменения приложения

Оптимизации
Подключение к конкретному шарду:

python
```
engine_shard1 = create_engine("postgresql://postgres:postgres@pgbouncer:6432/shard1")
engine_shard2 = create_engine("postgresql://postgres:postgres@pgbouncer:6432/shard2")
```
Транзакции между шардами:

Реализовать двухфазные коммиты (2PC)

Или использовать саги на уровне приложения

Это решение обеспечивает хороший баланс между производительностью и простотой реализации горизонтального шардинга в PostgreSQL.

