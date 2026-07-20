-- =====================================================================
-- CinemaDB — 6 основных запросов для анализа производительности
-- (домашнее задание №3). Классификация: 2 простых (1 таблица),
-- 4 сложных (JOIN и/или агрегаты) — обоснование отклонения от
-- предложенных в задании 3+3 см. docs/performance-report.md, раздел 1,
-- и docs/superpowers/specs/2026-07-20-perf-tuning-design.md, решение №2.
-- Запросы 5 и 6 параметризованы (?) — конкретный session_id подставляется
-- при тестировании (см. sql/07_perf_queries.sql использование в плане).
-- =====================================================================

USE cinemadb;

-- ---------------------------------------------------------------------
-- Запрос 1 (простой, 1 таблица): фильмы, показываемые сегодня
-- (упрощённая версия — только sessions, без названий; полная версия
-- с названиями — запрос 3 ниже)
-- ---------------------------------------------------------------------
SELECT movie_id, hall_id, start_time, end_time
FROM sessions
WHERE DATE(start_time) = CURDATE();

-- ---------------------------------------------------------------------
-- Запрос 2 (простой, 1 таблица): оплаченные заказы за последнюю неделю
-- (приближённая метрика к «проданным билетам» — считает заказы, а не
-- билеты, чтобы обойтись одной таблицей; один заказ может включать
-- несколько билетов)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS paid_bookings_last_week
FROM bookings
WHERE status = 'paid'
  AND booking_date >= CURDATE() - INTERVAL 7 DAY;

-- ---------------------------------------------------------------------
-- Запрос 3 (сложный, JOIN): полная афиша на сегодня
-- ---------------------------------------------------------------------
SELECT
    m.title, m.age_rating, f.name AS format, h.name AS hall,
    s.start_time, s.end_time, s.base_price
FROM sessions s
JOIN movies  m ON m.movie_id  = s.movie_id
JOIN halls   h ON h.hall_id   = s.hall_id
JOIN formats f ON f.format_id = s.format_id
WHERE DATE(s.start_time) = CURDATE()
ORDER BY h.name, s.start_time;

-- ---------------------------------------------------------------------
-- Запрос 4 (сложный, JOIN + агрегат): топ-3 самых прибыльных фильма
-- за последнюю неделю
-- ---------------------------------------------------------------------
SELECT
    m.movie_id, m.title,
    SUM(t.price)       AS total_revenue,
    COUNT(t.ticket_id) AS tickets_sold
FROM tickets t
JOIN sessions s ON s.session_id = t.session_id
JOIN movies m   ON m.movie_id   = s.movie_id
WHERE t.status IN ('paid', 'used')
  AND s.start_time >= CURDATE() - INTERVAL 7 DAY
GROUP BY m.movie_id, m.title
ORDER BY total_revenue DESC
LIMIT 3;

-- ---------------------------------------------------------------------
-- Запрос 5 (сложный, JOIN): схема зала — свободные/занятые места
-- на конкретный сеанс. ? — session_id, подставляется дважды.
-- ---------------------------------------------------------------------
SELECT
    se.row_num, se.seat_number, st.name AS seat_type,
    CASE WHEN t.ticket_id IS NULL THEN 'свободно' ELSE 'занято' END AS status
FROM seats se
JOIN seat_types st ON st.seat_type_id = se.seat_type_id
LEFT JOIN tickets t
    ON t.seat_id = se.seat_id
   AND t.session_id = ?
   AND t.status IN ('booked', 'paid', 'used')
WHERE se.hall_id = (SELECT hall_id FROM sessions WHERE session_id = ?)
ORDER BY se.row_num, se.seat_number;

-- ---------------------------------------------------------------------
-- Запрос 6 (сложный, JOIN + агрегат): теоретический диапазон цены
-- билета на конкретный сеанс (работает даже без единой продажи).
-- ? — session_id.
-- ---------------------------------------------------------------------
SELECT
    s.session_id,
    MIN(s.base_price * st.price_multiplier) AS min_price,
    MAX(s.base_price * st.price_multiplier) AS max_price
FROM sessions s
JOIN seats se      ON se.hall_id = s.hall_id
JOIN seat_types st ON st.seat_type_id = se.seat_type_id
WHERE s.session_id = ?
GROUP BY s.session_id;
