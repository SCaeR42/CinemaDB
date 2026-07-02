-- =====================================================================
-- CinemaDB — аналитические запросы
-- =====================================================================

USE cinemadb;

-- ---------------------------------------------------------------------
-- Самый прибыльный фильм: суммарная выручка по проданным/погашенным
-- билетам в разрезе фильма (учитываются билеты со статусом 'paid'
-- и 'used' — отменённые билеты в выручку не идут)
-- ---------------------------------------------------------------------
SELECT
    m.movie_id,
    m.title,
    SUM(t.price)       AS total_revenue,
    COUNT(t.ticket_id) AS tickets_sold
FROM tickets t
JOIN sessions s ON s.session_id = t.session_id
JOIN movies m   ON m.movie_id   = s.movie_id
WHERE t.status IN ('paid', 'used')
GROUP BY m.movie_id, m.title
ORDER BY total_revenue DESC
LIMIT 1;
