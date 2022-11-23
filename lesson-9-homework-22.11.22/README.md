
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

- Работа с журналами

Утанавливаем в ```/etc/postgresql/14/main/postgresql.conf``` параметр ```checkpoints_timeout = 30s``` и перезагружаем кластер, чтобы перечитать конфигурацию.
Проверяем:
```SQL
postgres=# select name, setting from pg_settings where name like 'checkpoint_timeout%';
        name        | setting 
--------------------+---------
 checkpoint_timeout | 30
(1 row)
```

Инициализируем и запуаскаем pg_bench:
``bash
pgbench -i postgres

postgres@fhmoht46nbvfbgcm3i3c:/root$ du -sh /var/lib/postgresql/14/main/
90M	/var/lib/postgresql/14/main/

pgbench -c8 -P 60 -T 600 -U postgres postgres

postgres@fhmoht46nbvfbgcm3i3c:/root$ du -sh /var/lib/postgresql/14/main/
118M	/var/lib/postgresql/14/main/
```
Видим, что объем увеличился на 28M. У нас контрольная точка создаётся один раз в 30 секунд, то у нас получается было создано 20 контрольных точек. 28/20=1.4M Размер каждой контрольной точки.

```SQL
postgres=#  
-[ RECORD 1 ]---------+------------------------------
checkpoints_timed     | 183
checkpoints_req       | 1
checkpoint_write_time | 741585
checkpoint_sync_time  | 606
buffers_checkpoint    | 50718
buffers_clean         | 0
maxwritten_clean      | 0
buffers_backend       | 3608
buffers_backend_fsync | 0
buffers_alloc         | 4296
stats_reset           | 2022-11-22 11:02:23.768313+00

```
Из представления видим, что выполнено 183 запланированных контрольных точек, а 1 запрошена за все время работы сервера.



Режим синхронной запииси:
```bash
postgres@fhmoht46nbvfbgcm3i3c:~/14/main/pg_wal$ pgbench -P 1 -T 10 postgres
pgbench (14.6 (Debian 14.6-1.pgdg100+1))
starting vacuum...end.
progress: 1.0 s, 357.0 tps, lat 2.789 ms stddev 1.375
progress: 2.0 s, 376.0 tps, lat 2.654 ms stddev 1.135
progress: 3.0 s, 398.0 tps, lat 2.517 ms stddev 0.953
progress: 4.0 s, 402.0 tps, lat 2.484 ms stddev 1.051
progress: 5.0 s, 417.0 tps, lat 2.397 ms stddev 0.721
progress: 6.0 s, 400.0 tps, lat 2.503 ms stddev 1.235
progress: 7.0 s, 275.0 tps, lat 3.631 ms stddev 2.752
progress: 8.0 s, 393.0 tps, lat 2.547 ms stddev 1.069
progress: 9.0 s, 375.0 tps, lat 2.661 ms stddev 1.743
progress: 10.0 s, 289.0 tps, lat 3.449 ms stddev 3.329
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
duration: 10 s
number of transactions actually processed: 3683
latency average = 2.714 ms
latency stddev = 1.662 ms
initial connection time = 3.637 ms
tps = 368.395746 (without initial connection time)
```
Выключаем режим синхронной записи:

```bash
postgres@fhmoht46nbvfbgcm3i3c:~/14/main/pg_wal$ pgbench -P 1 -T 10 postgres
pgbench (14.6 (Debian 14.6-1.pgdg100+1))
starting vacuum...end.
progress: 1.0 s, 1142.0 tps, lat 0.871 ms stddev 0.113
progress: 2.0 s, 1163.9 tps, lat 0.859 ms stddev 0.074
progress: 3.0 s, 1176.0 tps, lat 0.850 ms stddev 0.061
progress: 4.0 s, 1186.0 tps, lat 0.842 ms stddev 0.103
progress: 5.0 s, 1176.0 tps, lat 0.850 ms stddev 0.056
progress: 6.0 s, 1192.1 tps, lat 0.838 ms stddev 0.060
progress: 7.0 s, 1162.0 tps, lat 0.861 ms stddev 0.049
progress: 8.0 s, 1196.0 tps, lat 0.836 ms stddev 0.053
progress: 9.0 s, 1194.0 tps, lat 0.837 ms stddev 0.051
progress: 10.0 s, 1188.0 tps, lat 0.841 ms stddev 0.070
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
duration: 10 s
number of transactions actually processed: 11776
latency average = 0.848 ms
latency stddev = 0.073 ms
initial connection time = 4.052 ms
tps = 1178.066632 (without initial connection time)
```
Видим большой прирост в ~300% в TPS из-за того, что режим синхронной записи не ждет commit_delay

Включаем контрольные суммы и проверяем:

```bash
root@fhmoht46nbvfbgcm3i3c:~# sudo pg_ctlcluster 14 main stop
root@fhmoht46nbvfbgcm3i3c:~# sudo su - postgres -c '/usr/lib/postgresql/14/bin/pg_checksums --enable -D "/var/lib/postgresql/14/main"'
Checksum operation completed
Files scanned:  947
Blocks scanned: 5381
pg_checksums: syncing data directory
pg_checksums: updating control file
Checksums enabled in cluster
root@fhmoht46nbvfbgcm3i3c:~# sudo pg_ctlcluster 14 main start
root@fhmoht46nbvfbgcm3i3c:~# sudo su - postgres -c 'psql -c "SHOW data_checksums;"'
 data_checksums 
----------------
 on
(1 row)
```

Создаём таблицу, вставляем значения:

```SQL
postgres=# create table t1(c1 integer);
CREATE TABLE
postgres=# insert into t1(c1) values('1'); 
INSERT 0 1
postgres=# select * from t1;
 c1 
----
  1
(1 row)
```
Смотрим где таблица лежит на диске, останавливаем кластер и идём ломать:
```
postgres=# SELECT pg_relation_filepath('t1');
 pg_relation_filepath 
----------------------
 base/13707/16414
(1 row)
root@fhmoht46nbvfbgcm3i3c:~# sudo pg_ctlcluster 14 main stop
root@fhmoht46nbvfbgcm3i3c:/var/lib/postgresql/14/main/base/13707# dd if=/dev/zero of=/var/lib/postgresql/14/main/base/13707/16404 oflag=dsync conv=notrunc bs=1 count=8
8+0 records in
8+0 records out
8 bytes copied, 0.00928391 s, 0.9 kB/s
root@fhmoht46nbvfbgcm3i3c:/var/lib/postgresql/14/main/base/13707# sudo pg_ctlcluster 14 main start
root@fhmoht46nbvfbgcm3i3c:/var/lib/postgresql/14/main/base/13707# su postgres
postgres@fhmoht46nbvfbgcm3i3c:~/14/main/base/13707$ psql
psql (14.6 (Debian 14.6-1.pgdg100+1))
Type "help" for help.

postgres=# select * from t1;
 c1 
----
  1
(1 row)

postgres=# 

```

Postgresql вернулся на контрольную точку и продолжил работу