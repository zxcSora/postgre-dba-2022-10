
## Подготавливаем окружение
В этом примере я решил развернуть Postgres в контейнерах. Для удобства использовал Docker-compose и демонстрационную базу данных medium от PostgresPro
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

- Секционирование таблицы

В начале попробуем сделать таблицу flights секционированной по дате отправления

CREATE TABLE flights_range (
      flight_id    integer,
      flight_no    character(6),
      scheduled_departure timestamptz,
      scheduled_arrival   timestamptz,
      departure_airport   character(3),
      arrival_airport     character(3),
      status              character(20),
      aircraft_code       character(3),
      actual_departure    timestamptz,
      actual_arrival      timestamptz
   ) PARTITION BY RANGE(scheduled_departure);

```SQL
CREATE TABLE flights_range_201705 PARTITION OF flights_range
       FOR VALUES FROM ('2017-05-01'::timestamptz) TO ('2017-06-01'::timestamptz);
CREATE TABLE flights_range_201706 PARTITION OF flights_range
       FOR VALUES FROM ('2017-06-01'::timestamptz) TO ('2017-07-01'::timestamptz);
CREATE TABLE flights_range_201707 PARTITION OF flights_range
       FOR VALUES FROM ('2017-07-01'::timestamptz) TO ('2017-08-01'::timestamptz);
CREATE TABLE flights_range_201708 PARTITION OF flights_range
       FOR VALUES FROM ('2017-08-01'::timestamptz) TO ('2017-09-01'::timestamptz);
CREATE TABLE flights_range_201709 PARTITION OF flights_range
       FOR VALUES FROM ('2017-09-01'::timestamptz) TO ('2017-10-01'::timestamptz);
```

Видим, что наши таблицы созданы
```SQL
demo=# \dt
                       List of relations
  Schema  |         Name         |       Type        |  Owner
----------+----------------------+-------------------+----------
 bookings | aircrafts_data       | table             | postgres
 bookings | airports_data        | table             | postgres
 bookings | boarding_passes      | table             | postgres
 bookings | bookings             | table             | postgres
 bookings | flights              | table             | postgres
 bookings | flights_range        | partitioned table | postgres
 bookings | flights_range_201705 | table             | postgres
 bookings | flights_range_201706 | table             | postgres
 bookings | flights_range_201707 | table             | postgres
 bookings | flights_range_201708 | table             | postgres
 bookings | flights_range_201709 | table             | postgres
 bookings | seats                | table             | postgres
 bookings | ticket_flights       | table             | postgres
 bookings | tickets              | table             | postgres
(14 rows)
```

```
                                              Partitioned table "bookings.flights_range"
       Column        |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description
---------------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 flight_id           | integer                  |           |          |         | plain    |             |              |
 flight_no           | character(6)             |           |          |         | extended |             |              |
 scheduled_departure | timestamp with time zone |           |          |         | plain    |             |              |
 scheduled_arrival   | timestamp with time zone |           |          |         | plain    |             |              |
 departure_airport   | character(3)             |           |          |         | extended |             |              |
 arrival_airport     | character(3)             |           |          |         | extended |             |              |
 status              | character(20)            |           |          |         | extended |             |              |
 aircraft_code       | character(3)             |           |          |         | extended |             |              |
 actual_departure    | timestamp with time zone |           |          |         | plain    |             |              |
 actual_arrival      | timestamp with time zone |           |          |         | plain    |             |              |
Partition key: RANGE (scheduled_departure)
Partitions: flights_range_201705 FOR VALUES FROM ('2017-05-01 00:00:00+00') TO ('2017-06-01 00:00:00+00'),
            flights_range_201706 FOR VALUES FROM ('2017-06-01 00:00:00+00') TO ('2017-07-01 00:00:00+00'),
            flights_range_201707 FOR VALUES FROM ('2017-07-01 00:00:00+00') TO ('2017-08-01 00:00:00+00'),
            flights_range_201708 FOR VALUES FROM ('2017-08-01 00:00:00+00') TO ('2017-09-01 00:00:00+00'),
            flights_range_201709 FOR VALUES FROM ('2017-09-01 00:00:00+00') TO ('2017-10-01 00:00:00+00')
```

Заполняем данными:
```SQL
INSERT INTO flights_range SELECT * FROM flights;
INSERT 0 65664
```

Проверяем:
```SQL
demo=# SELECT tableoid::regclass, count(*) FROM flights_range GROUP BY tableoid;
       tableoid       | count
----------------------+-------
 flights_range_201706 | 16235
 flights_range_201707 | 16854
 flights_range_201708 | 16835
 flights_range_201709 |  7595
 flights_range_201705 |  8145
(5 rows)

demo=# select * from flights_range_201706 LIMIT 5;
 flight_id | flight_no |  scheduled_departure   |   scheduled_arrival    | departure_airport | arrival_airport |        status        | aircraft_code |    actual_departure    |     actual_arrival
-----------+-----------+------------------------+------------------------+-------------------+-----------------+----------------------+---------------+------------------------+------------------------
         1 | PG0405    | 2017-06-12 06:35:00+00 | 2017-06-12 07:30:00+00 | DME               | LED             | Arrived              | 321           | 2017-06-12 06:39:00+00 | 2017-06-12 07:35:00+00
         7 | PG0402    | 2017-06-05 09:25:00+00 | 2017-06-05 10:20:00+00 | DME               | LED             | Arrived              | 321           | 2017-06-05 09:27:00+00 | 2017-06-05 10:21:00+00
         8 | PG0403    | 2017-06-05 08:25:00+00 | 2017-06-05 09:20:00+00 | DME               | LED             | Arrived              | 321           | 2017-06-05 08:28:00+00 | 2017-06-05 09:22:00+00
         9 | PG0404    | 2017-06-05 16:05:00+00 | 2017-06-05 17:00:00+00 | DME               | LED             | Arrived              | 321           | 2017-06-05 16:09:00+00 | 2017-06-05 17:04:00+00
        10 | PG0405    | 2017-06-05 06:35:00+00 | 2017-06-05 07:30:00+00 | DME               | LED             | Arrived              | 321           | 2017-06-05 06:38:00+00 | 2017-06-05 07:33:00+00
(5 rows)
```
