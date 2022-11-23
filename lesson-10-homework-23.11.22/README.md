
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
postgres=*# update accounts set amount = 2022.22;
UPDATE 3
```
2 сессия подвисла и ожидает завершения транзакции:
```SQL
postgres=*# update accounts set amount = 2001.11;
```
В логах видим:
```bash
2022-11-23 10:48:29.347 UTC [3975] postgres@postgres LOG:  process 3975 still waiting for ShareLock on transaction 743 after 200.142 ms
2022-11-23 10:48:29.347 UTC [3975] postgres@postgres DETAIL:  Process holding the lock: 3996. Wait queue: 3975.
2022-11-23 10:48:29.347 UTC [3975] postgres@postgres CONTEXT:  while updating tuple (0,2) in relation "accounts"
2022-11-23 10:48:29.347 UTC [3975] postgres@postgres STATEMENT:  update accounts set amount = 2001.11;
```