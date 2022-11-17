
## Подготавливаем окружение
- Создал машинку в YC via TF. Через user-data прокинул публичный ключ.
```bash
sudo apt-get update
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y
```


- Устанавливаем PostgreSQL 14
```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - 
sudo apt-get update
sudo apt-get install \
  postgresql-14 -y
```

- Работа с базами данных, пользователями и правами
Создаём базу данных и схему:
```SQL
postgres=# create DATABASE testdb;
CREATE DATABASE

postgres=# \c testdb ;
You are now connected to database "testdb" as user "postgres".

testdb=# create schema testnm;
CREATE SCHEMA
```

Наполняем данными:

```SQL

testdb=# set search_path to 'testnm';
SET
testdb=# create table t1(c1 integer);
CREATE TABLE
testdb=# insert into t1(c1) values('1'); 
INSERT 0 1
testdb=# select * from t1;
 c1 
----
  1
(1 row)
```

Создаём роль и даём права:

```SQL
testdb=# create role readonly with password '12345';
CREATE ROLE
testdb=# grant CONNECT on database testdb to readonly;
GRANT
testdb=# grant USAGE on SCHEMA testnm to readonly;
GRANT
testdb=# grant SELECT on ALL TABLES IN SCHEMA testnm to readonly;
GRANT
```
Пробуем подключить и получаем ошибку:
```bash
postgres@fhm6k4estpg9t439hc2e:~$ psql -U readonly -W -d testdb -h 127.0.0.1
Password: 
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  role "readonly" is not permitted to log in
```
Проверяем атрибуты роли и видим, что login запрещён:
```SQL
postgres=# \du
                                   List of roles
 Role name |                         Attributes                         | Member of 
-----------+------------------------------------------------------------+-----------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
 readonly  | Cannot login                                               | {}
```
Исправляем это недоразумение:
```SQL
postgres=# alter role readonly with LOGIN;
ALTER ROLE
postgres=# \du
                                   List of roles
 Role name |                         Attributes                         | Member of 
-----------+------------------------------------------------------------+-----------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
 readonly  |                                                            | {}


postgres@fhm6k4estpg9t439hc2e:~$ psql -U readonly -W -d testdb -h 127.0.0.1
Password: 
psql (14.6 (Debian 14.6-1.pgdg100+1))
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.
```
Меняем search_path и делаем выборку:
```SQL
testdb=> set search_path to testnm;
SET
testdb=> select * from t1;
 c1 
----
  1
(1 row)
```

Возвращаемся в пользотеля postgres, удаляем таблицу:
```SQL
postgres=# \c testdb;
You are now connected to database "testdb" as user "postgres".
testdb=# drop table testnm.t1;
DROP TABLE
```
Создаём таблицу с явным указанием схемы:
```SQL
testdb=# create table testnm.t1(c1 integer);
CREATE TABLE

testdb=# insert into testnm.t1(c1) values('1'); 
INSERT 0 1

```

Из под пользователя readonly делаем выборку, получаем ошибку и проверяем свои права:
```SQL
testdb=> select * from testnm.t1;
ERROR:  permission denied for table t1
testdb=> SELECT table_catalog, table_schema, table_name, privilege_type
testdb-> FROM information_schema.table_privileges
testdb-> WHERE grantee = 'readonly';
 table_catalog | table_schema | table_name | privilege_type 
---------------+--------------+------------+----------------
(0 rows)
```
Видим, что прав нет, хотя мы давали на все таблицы в testdb. Это произошло потому что таблица пересоздавалась.
Даём права по умолчанию на схему для роли:
```SQL
postgres=# \c testdb;
You are now connected to database "testdb" as user "postgres".
testdb=# set search_path to testnm;
SET
testdb=# ALTER default privileges in SCHEMA testnm grant SELECT on TABLEs to readonly;
ALTER DEFAULT PRIVILEGES
```
```ALTER DEFAULT PRIVILEGES``` будет работать только на новые таблицы, поэтому нам нужно заново удалить и создать таблицу или GRANT SELECT.

Пробуем создать таблицу из под пользователя readonly:
```SQL
testdb=> set search_path to testnm;
SET
testdb=> select * from t1;
 c1 
----
  1
(1 row)

testdb=> create table t2(c1 integer); insert into t2 values (2);
ERROR:  permission denied for schema testnm
LINE 1: create table t2(c1 integer);
                     ^
ERROR:  relation "t2" does not exist
LINE 1: insert into t2 values (2);

```
Так как я указал ```set search_path to testnm;```, то создавать новые таблицы мне в ней нельзя т.к. мы давали этой роли права только на SELECT. Если бы я не указал SET search_path TO, то по умолчанию была бы схема public и в ней я бы мог создать таблицы.