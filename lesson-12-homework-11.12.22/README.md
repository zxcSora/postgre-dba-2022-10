
## Подготавливаем окружение
В этом примере я решил развернуть Postgres в контейнерах. Для удобства использовал Docker-compose.
```yaml
version: '3.8'
services:
  db0:
    image: postgres:14.1-alpine
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    ports:
      - '5432:5432'
    volumes:
      - ./db0:/var/lib/postgresql/data
  db1:
    image: postgres:14.1-alpine
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    ports:
      - '5433:5432'
    volumes:
      - ./db1:/var/lib/postgresql/data
  db2:
    image: postgres:14.1-alpine
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    ports:
      - '5434:5432'
    volumes:
      - ./db2:/var/lib/postgresql/data
  db3:
    image: postgres:14.1-alpine
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    ports:
      - '5435:5432'
    volumes:
      - ./db3:/var/lib/postgresql/data
volumes:
  db0:
    driver: local
  db1:
    driver: local
  db2:
    driver: local
  db3:
    driver: local

```
Как видим, после выполнения `docker compose up -d` в . будут созданы 4 директории, которые будут смонтированы в `/var/lib/postgresql/data`. Это означает, что наши данные будут persistent.
Базы данныз будут доступны локально на 0.0.0.0 на портах: `5432, 5433, 5434, 5435`

- Настройка репликации PostgreSQL

PG0 - создаём таблицы подписку и публикацию:
```SQL
postgres=# CREATE TABLE test1(write text);
CREATE TABLE
postgres=# CREATE TABLE test2(read text);
CREATE TABLE
postgres=# CREATE PUBLICATION pg0_test1_publication FOR TABLE test1;
CREATE PUBLICATION
postgres=# CREATE SUBSCRIPTION pg1_test2_subscription
CONNECTION 'host=172.19.0.5 port=5432 user=postgres password=postgres dbname=postgres'
PUBLICATION pg1_test2_publication WITH (copy_data = true);
NOTICE:  created replication slot "pg1_test2_subscription" on publisher
CREATE SUBSCRIPTION


postgres=# \dRp+
                     Publication pg0_test1_publication
  Owner   | All tables | Inserts | Updates | Deletes | Truncates | Via root
----------+------------+---------+---------+---------+-----------+----------
 postgres | f          | t       | t       | t       | t         | f
Tables:
    "public.test1"


postgres=# \dRs
                         List of subscriptions
          Name          |  Owner   | Enabled |       Publication
------------------------+----------+---------+-------------------------
 pg1_test2_subscription | postgres | t       | {pg1_test2_publication}
(1 row)

CREATE PUBLICATION pg0_test2_publication FOR TABLE test2;


```

PG1 - создаём таблицы, подписку и публикацию:

```sql
postgres=# CREATE TABLE test1(read text);
CREATE TABLE
postgres=# CREATE TABLE test2(write text);
CREATE TABLE
postgres=#CREATE PUBLICATION pg1_test2_publication FOR TABLE test2;
CREATE PUBLICATION
postgres=# CREATE SUBSCRIPTION pg0_test1_subscription
CONNECTION 'host=172.19.0.4 port=5432 user=postgres password=postgres dbname=postgres'
PUBLICATION pg0_test1_publication WITH (copy_data = true);
NOTICE:  created replication slot "pg0_test1_subscription" on publisher
CREATE SUBSCRIPTION


postgres=# \dRp+
                     Publication pg1_test2_publication
  Owner   | All tables | Inserts | Updates | Deletes | Truncates | Via root
----------+------------+---------+---------+---------+-----------+----------
 postgres | f          | t       | t       | t       | t         | f
Tables:
    "public.test2"


postgres=# \dRs
                         List of subscriptions
          Name          |  Owner   | Enabled |       Publication
------------------------+----------+---------+-------------------------
 pg0_test1_subscription | postgres | t       | {pg0_test1_publication}
(1 row)


CREATE PUBLICATION pg1_test1_publication FOR TABLE test1;

```

PG3 - Подписываемся на публикации

```
CREATE SUBSCRIPTION pg0_test2_subscription
CONNECTION 'host=172.19.0.4 port=5432 user=postgres password=postgres dbname=postgres'
PUBLICATION pg0_test2_publication WITH (copy_data = true);

CREATE SUBSCRIPTION pg1_test1_subscription
CONNECTION 'host=172.19.0.5 port=5432 user=postgres password=postgres dbname=postgres'
PUBLICATION pg1_test1_publication WITH (copy_data = true);
```

В PG0 и PG1 Делаем INSERT и проверяем на PG2:
```
insert into test2 values ('yes');

postgres=# select * from public.test1;
 read
------
 yes
(1 row)

postgres=# select * from public.test2
;
 read
------
 yes
(1 row)

```
****
- Создание полной реплики от PG2
В случае с официальными образами от postgres, физическую репликацию реализовать довольно проблематично(во время выполнения pg_basebackup умирает контейнер). Я взял образ от bitnami там уже реализовано это под капотом.

Описание того, что нужно было бы сделать, если бы это был какой-либо боевой стенд
1) С помощью утилиты pg_basebackup сделать копию нашей базы, залить эту копию в $PGDATA (Обычно это /var/lib/postgresql/"$VERSION"/main/)
2) На слейве создать файлик recovery.conf:
```bash
standby_mode = 'on'
primary_conninfo = 'host="MASTER_IP" port="MASTER_PORT" user="USER_FOR_REPLICATION" password="PASS_OF_USER_FOR_REPLICATION" sslmode=verify-full'
```
3) Сделать рестарт базы
4) Проверить через представление select * from pg_stat_wal_receiver\gx
```SQL
pid                   | 3291077
status                | streaming
receive_start_lsn     | EC98/D0000000
receive_start_tli     | 1
received_lsn          | ECA9/C7B63908
received_tli          | 1
last_msg_send_time    | 2022-12-13 10:37:36.027635+00
last_msg_receipt_time | 2022-12-13 10:37:36.065559+00
latest_end_lsn        | ECA9/C7B63908
latest_end_time       | 2022-12-13 10:37:36.027635+00
slot_name             |
sender_host           | master-host
sender_port           | 5432
conninfo              | user=replicator password=********
```
