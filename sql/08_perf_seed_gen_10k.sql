-- =====================================================================
-- CinemaDB — генератор данных, этап 1 (~10 000 строк)
-- Требует 01_ddl.sql, 04_eav_ddl.sql, 02_seed.sql уже выполненных.
-- Самодостаточен и переисполняем: очищает 5 транзакционных таблиц
-- (и movie_genres/payments, которые на них ссылаются) и заполняет заново.
-- Справочники (cinemas/halls/seat_types/seats/genres/formats) не трогает.
-- =====================================================================

USE cinemadb;

SET @movies_target    = 300;
SET @sessions_target  = 1200;
SET @customers_target = 2500;
SET @bookings_target  = 3000;
SET @tickets_target   = 3000;

-- ---------------------------------------------------------------------
-- Очистка транзакционных таблиц (FK-safe: движок не проверяет ссылки
-- во время TRUNCATE при выключенных FOREIGN_KEY_CHECKS)
-- ---------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE movie_genres;
TRUNCATE TABLE payments;
TRUNCATE TABLE tickets;
TRUNCATE TABLE bookings;
TRUNCATE TABLE sessions;
TRUNCATE TABLE customers;
TRUNCATE TABLE movies;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- Таблица чисел (0..9999) — набором, без построчных циклов/RECURSIVE CTE.
-- MySQL не позволяет self-join одной и той же TEMPORARY TABLE в одном
-- запросе ("Can't reopen table"), поэтому под каждый разряд — своя
-- отдельная временная таблица с одинаковым содержимым 0-9.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS digits1;
DROP TEMPORARY TABLE IF EXISTS digits2;
DROP TEMPORARY TABLE IF EXISTS digits3;
DROP TEMPORARY TABLE IF EXISTS digits4;
CREATE TEMPORARY TABLE digits1 (d TINYINT UNSIGNED PRIMARY KEY);
CREATE TEMPORARY TABLE digits2 (d TINYINT UNSIGNED PRIMARY KEY);
CREATE TEMPORARY TABLE digits3 (d TINYINT UNSIGNED PRIMARY KEY);
CREATE TEMPORARY TABLE digits4 (d TINYINT UNSIGNED PRIMARY KEY);
INSERT INTO digits1 VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);
INSERT INTO digits2 VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);
INSERT INTO digits3 VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);
INSERT INTO digits4 VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

DROP TEMPORARY TABLE IF EXISTS nums;
CREATE TEMPORARY TABLE nums (n INT UNSIGNED PRIMARY KEY);
INSERT INTO nums (n)
SELECT d1.d + d2.d*10 + d3.d*100 + d4.d*1000
FROM digits1 d1, digits2 d2, digits3 d3, digits4 d4;

-- ---------------------------------------------------------------------
-- movies
-- ---------------------------------------------------------------------
INSERT INTO movies (title, original_title, description, duration_minutes, release_date, age_rating, country, director)
SELECT
    CONCAT('Фильм №', n),
    NULL,
    CONCAT('Синтетическое описание фильма №', n, ' для нагрузочного тестирования.'),
    90 + (n % 91),
    DATE_ADD('2000-01-01', INTERVAL (n % 9125) DAY),
    ELT(1 + (n % 4), '0+', '12+', '16+', '18+'),
    ELT(1 + (n % 3), 'Россия', 'США', 'Великобритания'),
    CONCAT('Режиссёр №', n % 500)
FROM nums
WHERE n < @movies_target;

-- ---------------------------------------------------------------------
-- sessions — start_time центрирован на "сейчас" фиксированным шагом
-- 15 минут, чтобы "сегодня"/"эта неделя" всегда попадали в диапазон
-- ---------------------------------------------------------------------
SET @movie_min    = (SELECT MIN(movie_id) FROM movies);
SET @movie_count  = (SELECT COUNT(*) FROM movies);
SET @hall_min     = (SELECT MIN(hall_id) FROM halls);
SET @hall_count   = (SELECT COUNT(*) FROM halls);
SET @format_min   = (SELECT MIN(format_id) FROM formats);
SET @format_count = (SELECT COUNT(*) FROM formats);
SET @session_base_time = NOW() - INTERVAL ((@sessions_target * 15) DIV 2) MINUTE;

INSERT INTO sessions (movie_id, hall_id, format_id, start_time, end_time, base_price)
SELECT
    @movie_min + (n % @movie_count),
    @hall_min + (n % @hall_count),
    @format_min + (n % @format_count),
    TIMESTAMPADD(MINUTE, n * 15, @session_base_time),
    TIMESTAMPADD(MINUTE, n * 15 + 120, @session_base_time),
    150.00 + (n % 10) * 25.00
FROM nums
WHERE n < @sessions_target;

-- ---------------------------------------------------------------------
-- customers
-- ---------------------------------------------------------------------
INSERT INTO customers (first_name, last_name, email, phone)
SELECT
    CONCAT('Имя', n),
    CONCAT('Фамилия', n),
    CONCAT('customer', n, '@loadtest.example'),
    CONCAT('+7900', LPAD(n, 7, '0'))
FROM nums
WHERE n < @customers_target;

-- ---------------------------------------------------------------------
-- bookings — booking_date разбросан по последним ~4 годам от "сейчас",
-- чтобы "последняя неделя" тоже всегда содержала строки
-- ---------------------------------------------------------------------
SET @customer_min   = (SELECT MIN(customer_id) FROM customers);
SET @customer_count = (SELECT COUNT(*) FROM customers);

INSERT INTO bookings (customer_id, booking_date, status)
SELECT
    @customer_min + (n % @customer_count),
    NOW() - INTERVAL (n % 1460) DAY - INTERVAL (n % 1440) MINUTE,
    ELT(1 + (n % 3), 'pending', 'paid', 'cancelled')
FROM nums
WHERE n < @bookings_target;

-- ---------------------------------------------------------------------
-- tickets — уникальность (session_id, seat_id) гарантирована
-- построением: session_seat_pairs перечисляет каждую валидную пару
-- (сеанс в своём зале × место этого зала) ровно один раз; ordering по
-- seat_rank сначала распределяет билеты равномерно по ВСЕМ сеансам
-- (иначе первые N пар заполнили бы только самые ранние сеансы)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS session_seat_pairs;
CREATE TEMPORARY TABLE session_seat_pairs AS
SELECT session_id, seat_id, seat_rank,
       ROW_NUMBER() OVER (ORDER BY seat_rank, session_id) AS rn
FROM (
    SELECT
        s.session_id,
        se.seat_id,
        ROW_NUMBER() OVER (PARTITION BY s.session_id ORDER BY se.seat_id) AS seat_rank
    FROM sessions s
    JOIN seats se ON se.hall_id = s.hall_id
) ranked;

SET @booking_min   = (SELECT MIN(booking_id) FROM bookings);
SET @booking_count = (SELECT COUNT(*) FROM bookings);

INSERT INTO tickets (booking_id, session_id, seat_id, price, status)
SELECT
    @booking_min + ((rn - 1) % @booking_count),
    session_id,
    seat_id,
    100.00 + ((rn - 1) % 20) * 15.50,
    ELT(1 + ((rn - 1) % 4), 'booked', 'paid', 'used', 'cancelled')
FROM session_seat_pairs
WHERE rn <= @tickets_target;
