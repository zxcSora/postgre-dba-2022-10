

- Создал машинку в YC via TF. Через user-data прокинул публичный ключ.Добавил репозиторий и устанавливаем PostgreSQL 14
```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt-get -y install postgresql-14
```
Проверяем:
```bash
postgres@fhmvfd9tibpp1gg11ntl:/root$ pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
14  main    5432 online postgres /var/lib/postgresql/14/main /var/log/postgresql/postgresql-14-main.log
```
Выключаем autocommit, это означает, что транзакция не будет завершена, пока мы явно не укажем её окончание:
```SQL
postgres=# \set AUTOCOMMIT OFF
postgres=# \echo :AUTOCOMMIT
OFF
```
- Создаём таблицу, наполняем её данными и делаем фиксацию:
```SQL
create table persons(id serial, first_name text, second_name text);
insert into persons(first_name, second_name) values('ivan', 'ivanov');
insert into persons(first_name, second_name) values('petr', 'petrov');
commit;
```
- Проверяем текущий уровень изоляции:
```SQL
postgres=# show transaction isolation level;commit;
 transaction_isolation
-----------------------
 read committed
(1 row)

COMMIT

```
- Создаём ещё одну сессию и начинаем новую транзакцию в обоих сессиях:
```SQL
postgres=# begin;
BEGIN
```
- Добавляем новую запись в первой сессии:
```SQL
postgres=*# insert into persons(first_name, second_name) values('sergey', 'sergeev');
INSERT 0 1
```
- Делаем выборку во второй сессии:
```SQL
postgres=*# select * from persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 rows)

postgres=*# commit;
COMMIT
```
Новую запись не видим, т.к. в первой сессии мы не завершили транзакцию. Завершаем её:
```SQL
postgres=*# commit;
COMMIT
```
Делаем выборку во второй сесии ещё раз и завершаем транзакцию:
```SQL
postgres=# select * from persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 rows)

postgres=*# commit;
COMMIT
```
Видим новую строку, т.к. уровень изоляции read committed не удерживает блокировки каждой затронутой строки.

Меняем уровень изоляции на ```repeatable read```
в первой сессии добавляем новую запись и делаем выборку во второй:
```SQL
postgres=# BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN
postgres=*# insert into persons(first_name, second_name) values('sveta', 'svetova');
INSERT 0 1

postgres=# BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN
postgres=# select * from persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 rows)
```
Новый строки не видим.

Потому что не завершили транзакции.
Завершаем транзакцию в первой сессии и делаем выборку ещё раз во второй сессии:
```SQL
postgres=*# commit;
COMMIT

postgres=*# select * from persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 rows)
```
Новой строки не видим.
В отличие от просмотра с «read committed», просмотр с «repeatable read» удерживает блокировки каждой затронутой строки до окончания транзакции

Завершаем транзакцию во второй сессии и делаем выборку ещё раз во второй сессии и ещё раз завершаем транзакцию:
```SQL
postgres=*# commit;
COMMIT
postgres=# select * from persons;commit;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
  7 | sveta      | svetova
(4 rows)

COMMIT
```
Видим новую запись, потому что мы завершили предыдущую транзакцию и разблокировали строки для чтения, поэтому они попали в SELECT текущей транзакции.
