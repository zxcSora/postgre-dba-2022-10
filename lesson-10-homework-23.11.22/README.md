
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

- Работа с блокировками

Включаем логирование блокировок с помощью параметра ```log_lock_waits = on``` и записываем те сообщения, где длительность блокировки больше 200 МС ```deadlock_timeout = 200``` в файле ```/etc/postgresql/14/main/postgresql.conf``` перезагружаем сервер и проверяемЖ
```SQL
postgres=# show log_lock_waits;
 log_lock_waits 
----------------
 on
(1 row)

postgres=# show deadlock_timeout;
 deadlock_timeout 
------------------
 200ms
(1 row)
```

Воспроизводим ситуацию. Создаём таблицу, наполняем данными, начинаем транзакцию:
```SQL
postgres=# BEGIN;
BEGIN
postgres=*# UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;
UPDATE 1
postgres=*# 
```
Во второй сессии попытаемся создать индекс:
```SQL
postgres=# CREATE INDEX ON accounts(acc_no);

```
Видим в логах, что транзакция на создания индекса висит и ожидает завершения первой
```bash
2022-11-23 10:25:12.356 UTC [3975] postgres@postgres LOG:  process 3975 still waiting for ShareLock on relation 16387 of database 13707 after 200.150 ms
2022-11-23 10:25:12.356 UTC [3975] postgres@postgres DETAIL:  Process holding the lock: 3996. Wait queue: 3975.
2022-11-23 10:25:12.356 UTC [3975] postgres@postgres STATEMENT:  CREATE INDEX ON accounts(acc_no);
```

Воспроизводим ситуацию обновления одной и той же строки тремя командами UPDATE в разных сеансах:
1 сессия:
```SQL
postgres=# BEGIN;
BEGIN
postgres=*# update accounts set amount = 2022.22;
UPDATE 3

```
2 сессия:
```SQL
postgres=*# update accounts set amount = 2033.33;

```

3 сессия:
```SQL
postgres=*# update accounts set amount = 2044.44;
```
Видим, что во второй и третьей сессии получаем блокировку т.к. в первой сессии транзакция не завершилась. В логах видим подтверждение:
```bash
2022-11-23 10:52:44.905 UTC [3975] postgres@postgres LOG:  process 3975 still waiting for ShareLock on transaction 745 after 200.113 ms
2022-11-23 10:52:44.905 UTC [3975] postgres@postgres DETAIL:  Process holding the lock: 3996. Wait queue: 3975.
2022-11-23 10:52:44.905 UTC [3975] postgres@postgres CONTEXT:  while updating tuple (0,2) in relation "accounts"
2022-11-23 10:52:44.905 UTC [3975] postgres@postgres STATEMENT:  update accounts set amount = 2033.33;
2022-11-23 10:52:58.673 UTC [4266] postgres@postgres LOG:  process 4266 still waiting for ExclusiveLock on tuple (0,2) of relation 16387 of database 13707 after 200.170 ms
2022-11-23 10:52:58.673 UTC [4266] postgres@postgres DETAIL:  Process holding the lock: 3975. Wait queue: 4266.
2022-11-23 10:52:58.673 UTC [4266] postgres@postgres STATEMENT:  update accounts set amount = 2044.44;
```
Видим, что первая транзакция имеет режим ShareLock, что означает, что таблица будет защищена от конкурентных записей. 
Вторая транзакция получила режим ExclusiveLock, этот режим позволяет только читать, но не писать в конкурентном режиме.


*
Взаимная блокировка при UPDATE одной и той же таблицы:
1 сессия
```SQL
postgres=# BEGIN;
BEGIN
postgres=*# UPDATE test2 SET name=id RETURNING *,pg_sleep(5),pg_advisory_lock(id);
```
2 сессия
```SQL
postgres=# BEGIN;
BEGIN
postgres=*# VALUES(pg_advisory_lock(5));
 column1 
---------
  
(1 row)

postgres=*# UPDATE test2 SET name=id RETURNING *,pg_sleep(5),pg_advisory_lock(5+id);
ERROR:  deadlock detected
DETAIL:  Process 3975 waits for ShareLock on transaction 751; blocked by process 3996.
Process 3996 waits for ExclusiveLock on advisory lock [13707,0,5,1]; blocked by process 3975.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,1) in relation "test2"
postgres=!# 

```
В логах видим:
```bash
2022-11-23 11:16:28.647 UTC [3975] postgres@postgres LOG:  process 3975 detected deadlock while waiting for ShareLock on transaction 751 after 200.160 ms
2022-11-23 11:16:28.647 UTC [3975] postgres@postgres DETAIL:  Process holding the lock: 3996. Wait queue: .
2022-11-23 11:16:28.647 UTC [3975] postgres@postgres CONTEXT:  while updating tuple (0,1) in relation "test2"
2022-11-23 11:16:28.647 UTC [3975] postgres@postgres STATEMENT:  UPDATE test2 SET name=id RETURNING *,pg_sleep(5),pg_advisory_lock(5+id);
2022-11-23 11:16:28.648 UTC [3975] postgres@postgres ERROR:  deadlock detected
2022-11-23 11:16:28.648 UTC [3975] postgres@postgres DETAIL:  Process 3975 waits for ShareLock on transaction 751; blocked by process 3996.
	Process 3996 waits for ExclusiveLock on advisory lock [13707,0,5,1]; blocked by process 3975.
	Process 3975: UPDATE test2 SET name=id RETURNING *,pg_sleep(5),pg_advisory_lock(5+id);
	Process 3996: UPDATE test2 SET name=id RETURNING *,pg_sleep(5),pg_advisory_lock(id);
2022-11-23 11:16:28.648 UTC [3975] postgres@postgres HINT:  See server log for query details.
2022-11-23 11:16:28.648 UTC [3975] postgres@postgres CONTEXT:  while updating tuple (0,1) in relation "test2"
2022-11-23 11:16:28.648 UTC [3975] postgres@postgres STATEMENT:  UPDATE test2 SET name=id RETURNING *,pg_sleep(5),pg_advisory_lock(5+id);
2022-11-23 11:18:07.337 UTC [3996] postgres@postgres LOG:  process 3996 acquired ExclusiveLock on advisory lock [13707,0,5,1] after 105625.137 ms
2022-11-23 11:18:07.337 UTC [3996] postgres@postgres STATEMENT:  UPDATE test2 SET name=id RETURNING *,pg_sleep(5),pg_advisory_lock(id);

```