
## Подготавливаем окружение
- Создал машинку в YC via TF. Через user-data прокинул публичный ключ.
```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo
```
- Устанавливаем Docker Engine:
```bash
sudo apt-get update
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y #Устанавливает последнюю доступную версию.
```
- Проверяем:
```bash
sudo docker --version
```
## Разворачиваем PostgreSQL in Docker

- Создаём директорию. Она будет маунтится в контейнер. В ней будут храниться данные и конфиги
```mkdir /var/lib/postgres```
- Запускаем контейнер, монтируем созданную директорию, задаем пароль пользователя postgres:
```bash
docker run --rm -it -d --name pg-server \
    -v /var/lib/postgres:/postgresql/data \
    -e PGDATA=/postgresql/data \
    -e POSTGRES_PASSWORD=password123 \
    postgres:latest
```
Проверяем:
```bash
docker logs -f pg-server
```
Видим, что база готова принимать подключения:

https://i.imgur.com/9wLnwS8.png

- Запускаем контейнер с клиентом:
```bash
docker run --rm -it -d --name pg-client \
    -e POSTGRES_PASSWORD=password123 \
    postgres:latest
```
На хостовой машине выполняем ```docker inspect pg-server | grep IPAddress``` и получаем адрес с нашим сервером внутри сети докера:
```
root@fhm6a3bmvn7l602m3m5j:~# docker inspect pg-server | grep IPAddress
            "SecondaryIPAddresses": null,
            "IPAddress": "172.17.0.2",
                    "IPAddress": "172.17.0.2",
```

Подключаемся к контейнеру, меняем пользователя и подключаемся к нашему серверу с помощью psql:
```bash
docker exec -ti pg-client bash
su postgres
psql -h 172.17.0.2 -W -U postgres
```
Создаём базу, таблицу и наполняем её данными:
```SQL
postgres=# create database test_db;
CREATE DATABASE
test_db=# create schema test_db;
CREATE SCHEMA
test_db=# set search_path to 'test_db';
SET
test_db=# create table persons(id serial, first_name text, second_name text);
insert into persons(first_name, second_name) values('ivan', 'ivanov');
insert into persons(first_name, second_name) values('petr', 'petrov');
CREATE TABLE
INSERT 0 1
INSERT 0 1
test_db=# select * from persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 rows)
```

Для подключения извне к нашемому серверу, нужно сказать контейнеру, что его порт 5432 должен быть доступен на нашем внешнем интерфейсе или на 0.0.0.0 на каком-либо порту. Для этого удаляем и заново запускаем контейнер с сервером:
```bash
docker rm -f pg-server && docker run --rm -it -d --name pg-server \
    -p 0.0.0.0:5432:5432 \
    -v /var/lib/postgres:/postgresql/data \
    -e PGDATA=/postgresql/data \
    -e POSTGRES_PASSWORD=password123 \
    postgres:latest
```
Видим в выводе:
```bash
root@fhm6a3bmvn7l602m3m5j:/var/lib/postgres# docker ps -a
CONTAINER ID   IMAGE             COMMAND                  CREATED          STATUS          PORTS                    NAMES
b1f96fd13f8c   postgres:latest   "docker-entrypoint.s…"   4 seconds ago    Up 2 seconds    0.0.0.0:5432->5432/tcp   pg-server
```
Проверяем доступность порта из мира:
```bash
 sora@Sora-PC  ~/betboom/567/offline/main   master ±  telnet 178.154.240.153 5432
Trying 178.154.240.153...
Connected to 178.154.240.153.
Escape character is '^]'.
```
Сетевая связанность есть.

На локальной машине запускаем клиент psql и подключаем к нашей базе:
```bash
 sora@Sora-PC  ~/betboom/567/offline/main   master ±  docker exec -ti pg-client bash
root@014752cd990c:/# psql -h 178.154.240.153 -U postgres -W
Password:
psql (15.0 (Debian 15.0-1.pgdg110+1))
Type "help" for help.
```
```SQL
postgres=# \l
                                                List of databases
   Name    |  Owner   | Encoding |  Collate   |   Ctype    | ICU Locale | Locale Provider |   Access privileges
-----------+----------+----------+------------+------------+------------+-----------------+-----------------------
 postgres  | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            |
 template0 | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
           |          |          |            |            |            |                 | postgres=CTc/postgres
 template1 | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
           |          |          |            |            |            |                 | postgres=CTc/postgres
 test_db   | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            |
(4 rows)
```
Успех.

- Проверка сохранности данных

Удаляем контейнер с сервером и заново его запускаем:
```bash
docker rm -f pg-server && docker run --rm -it -d --name pg-server \
    -p 0.0.0.0:5432:5432 \
    -v /var/lib/postgres:/postgresql/data \
    -e PGDATA=/postgresql/data \
    -e POSTGRES_PASSWORD=password123 \
    postgres:latest
```
Подключаем из контейнера с клиентом к нашему серверу и проверяем сохранность данных:
```bash
postgres@96e6be07cc5a:/$ psql -h 172.17.0.2 -W -U postgres
Password:
psql (15.0 (Debian 15.0-1.pgdg110+1))
Type "help" for help.
```
```SQL
postgres=# \l
                                                List of databases
   Name    |  Owner   | Encoding |  Collate   |   Ctype    | ICU Locale | Locale Provider |   Access privileges
-----------+----------+----------+------------+------------+------------+-----------------+-----------------------
 postgres  | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            |
 template0 | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
           |          |          |            |            |            |                 | postgres=CTc/postgres
 template1 | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
           |          |          |            |            |            |                 | postgres=CTc/postgres
 test_db   | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            |
(4 rows)

postgres=# \c test_db;
Password:
You are now connected to database "test_db" as user "postgres".
test_db=# set search_path to 'test_db';
SET
test_db=# \dt
          List of relations
 Schema  |  Name   | Type  |  Owner
---------+---------+-------+----------
 test_db | persons | table | postgres
(1 row)

test_db=# select * from test_db.persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 rows)
```
Данные на месте

Удаляем созданные ресурсы:
```terraform destroy --auto-approve -var-file=../.secret.tfvars```
## Notes
Проблемы с которыми столкнулся: В первом скрипте не указал ключ -y для подтверждения установки пакетов :)
Остальное прошло гладко
