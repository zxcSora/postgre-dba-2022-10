
## Подготавливаем окружение
В этом примере я решил развернуть Postgres в контейнерах. Для удобства использовал Docker-compose
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
volumes:
  db0:
    driver: local

```

- Работа с индексами

В начале попробуем сделать таблицу flights секционированной по дате отправления
```sql
postgres=# create table accounts(number integer, comment text, active boolean);
CREATE TABLE
postgres=# insert into accounts(number, comment, active)
  select s.id, chr((32+random()*94)::integer), random() < 0.01
  from generate_series(1,100000) as s(id)
  order by random();
INSERT 0 100000
```

Посмотрим explain:
```sql
postgres=# explain select * from accounts where number = 500;
                        QUERY PLAN
-----------------------------------------------------------
 Seq Scan on accounts  (cost=0.00..1693.00 rows=1 width=7)
   Filter: (number = 500)
(2 rows)
```

Добавим индекс:
```sql
postgres=# create index on accounts(number);
CREATE INDEX
postgres=# analyze accounts;
ANALYZE
```

Выполняем тот же запрос и видим уменьшение стоимости:
```SQL
postgres=# explain select * from accounts where number = 500;
                                     QUERY PLAN
------------------------------------------------------------------------------------
 Index Scan using accounts_number_idx on accounts  (cost=0.29..8.31 rows=1 width=7)
   Index Cond: (number = 500)
(2 rows)
```

- Индекс для полнотекстовго поиска:
```sql
postgres=# create index on accounts(comment);
CREATE INDEX
postgres=# analyze accounts;
ANALYZE
```
```sql
postgres=# explain select * from accounts where comment = 'abcd';
                                     QUERY PLAN
-------------------------------------------------------------------------------------
 Index Scan using accounts_comment_idx on accounts  (cost=0.29..4.31 rows=1 width=7)
   Index Cond: (comment = 'abcd'::text)
(2 rows)
```

- Частичный индекс
```sql
postgres=# create index on accounts(active) where active;
CREATE INDEX
postgres=# analyze accounts;
ANALYZE
```
```sql
postgres=# explain select * from accounts where not active;
                          QUERY PLAN
---------------------------------------------------------------
 Seq Scan on accounts  (cost=0.00..1443.02 rows=99005 width=7)
   Filter: (NOT active)
(2 rows)

postgres=# explain select * from accounts where active;
                                       QUERY PLAN
----------------------------------------------------------------------------------------
 Index Scan using accounts_active_idx on accounts  (cost=0.15..233.80 rows=997 width=7)
(1 row)
```
- Создадим индекс на несколько полей:
```sql
postgres=# create index on accounts(number,comment);
CREATE INDEX
postgres=# analyze accounts;
ANALYZE
```
Видим, что оптимизатор использует многоколочный индекс для поиска
```
postgres=# explain select * from accounts where number = 60433 and comment = 'abcd';
                                         QUERY PLAN
--------------------------------------------------------------------------------------------
 Index Scan using accounts_number_comment_idx on accounts  (cost=0.29..8.31 rows=1 width=7)
   Index Cond: ((number = 60433) AND (comment = 'abcd'::text))
(2 rows)
```
