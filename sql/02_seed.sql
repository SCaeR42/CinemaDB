-- =====================================================================
-- CinemaDB — демонстрационные данные для проверки схемы и запросов
-- =====================================================================

USE cinemadb;

INSERT INTO cinemas (name, address, phone) VALUES
    ('Кинопарк «Галактика»', 'г. Москва, ул. Кинематографистов, 1', '+7 495 000-00-00');

INSERT INTO halls (cinema_id, name, description) VALUES
    (1, 'Зал 1', 'Большой зал, 12 мест'),
    (1, 'Зал 2', 'Малый зал, 6 мест');

INSERT INTO seat_types (name, price_multiplier) VALUES
    ('Стандарт', 1.00),
    ('Комфорт', 1.30),
    ('VIP', 1.80);

-- Зал 1 (hall_id=1): ряд 1 — VIP (seat_id 1-4), ряды 2-3 — Стандарт (seat_id 5-12)
INSERT INTO seats (hall_id, row_num, seat_number, seat_type_id) VALUES
    (1, 1, 1, 3), (1, 1, 2, 3), (1, 1, 3, 3), (1, 1, 4, 3),
    (1, 2, 1, 1), (1, 2, 2, 1), (1, 2, 3, 1), (1, 2, 4, 1),
    (1, 3, 1, 1), (1, 3, 2, 1), (1, 3, 3, 1), (1, 3, 4, 1);

-- Зал 2 (hall_id=2): все места — Комфорт (seat_id 13-18)
INSERT INTO seats (hall_id, row_num, seat_number, seat_type_id) VALUES
    (2, 1, 1, 2), (2, 1, 2, 2), (2, 1, 3, 2),
    (2, 2, 1, 2), (2, 2, 2, 2), (2, 2, 3, 2);

INSERT INTO genres (name) VALUES
    ('Драма'), ('Фантастика'), ('Комедия');

INSERT INTO movies (title, original_title, description, duration_minutes, release_date, age_rating, country, director) VALUES
    ('Начало', 'Inception', 'Похититель снов получает задание совершить обратное — инсепцию.', 148, '2023-05-01', '16+', 'США', 'Кристофер Нолан'),
    ('Смешные истории', NULL, 'Комедийный альманах о буднях большого города.', 95, '2024-01-10', '12+', 'Россия', 'Иван Иванов'),
    ('Космический рубеж', NULL, 'Экипаж исследовательского корабля сталкивается с неизвестностью.', 130, '2024-03-15', '12+', 'США', 'Джон Смит');

INSERT INTO movie_genres (movie_id, genre_id) VALUES
    (1, 1), (1, 2),   -- Начало: Драма, Фантастика
    (2, 3),           -- Смешные истории: Комедия
    (3, 2);           -- Космический рубеж: Фантастика

INSERT INTO formats (name) VALUES
    ('2D'), ('3D');

INSERT INTO sessions (movie_id, hall_id, format_id, start_time, end_time, base_price) VALUES
    (1, 1, 2, '2024-06-01 18:00:00', '2024-06-01 20:30:00', 350.00), -- Начало, Зал 1, 3D
    (1, 1, 1, '2024-06-02 12:00:00', '2024-06-02 14:30:00', 250.00), -- Начало, Зал 1, 2D
    (2, 2, 1, '2024-06-01 16:00:00', '2024-06-01 17:40:00', 200.00), -- Смешные истории, Зал 2, 2D
    (3, 1, 2, '2024-06-03 20:00:00', '2024-06-03 22:15:00', 400.00); -- Космический рубеж, Зал 1, 3D

INSERT INTO customers (first_name, last_name, email, phone) VALUES
    ('Пётр', 'Петров', 'petrov@mail.example', '+79001112233'),
    ('Анна', 'Смирнова', 'smirnova@mail.example', '+79004445566'),
    ('Олег', 'Кузнецов', 'kuznetsov@mail.example', '+79007778899');

INSERT INTO bookings (customer_id, status) VALUES
    (1, 'paid'),  -- booking_id=1: Пётр -> сеанс 1 (Начало, 3D)
    (2, 'paid'),  -- booking_id=2: Анна -> сеанс 3 (Смешные истории)
    (3, 'paid'),  -- booking_id=3: Олег -> сеанс 4 (Космический рубеж)
    (1, 'paid');  -- booking_id=4: Пётр -> сеанс 2 (Начало, 2D)

-- Цена билета = base_price сеанса * price_multiplier типа места, фиксируется на момент продажи
INSERT INTO tickets (booking_id, session_id, seat_id, price, status) VALUES
    (1, 1, 1, 350.00 * 1.80, 'paid'),  -- VIP-место, сеанс "Начало" 3D
    (1, 1, 2, 350.00 * 1.80, 'paid'),  -- VIP-место, сеанс "Начало" 3D
    (2, 3, 13, 200.00 * 1.30, 'paid'), -- Комфорт, "Смешные истории"
    (3, 4, 5, 400.00 * 1.00, 'paid'),  -- Стандарт, "Космический рубеж"
    (3, 4, 6, 400.00 * 1.00, 'paid'),  -- Стандарт, "Космический рубеж"
    (4, 2, 9, 250.00 * 1.00, 'paid');  -- Стандарт, "Начало" 2D

INSERT INTO payments (booking_id, amount, payment_method, status) VALUES
    (1, 630.00 + 630.00, 'online', 'success'),
    (2, 260.00, 'card', 'success'),
    (3, 400.00 + 400.00, 'cash', 'success'),
    (4, 250.00, 'card', 'success');
