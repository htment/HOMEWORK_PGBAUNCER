CREATE TABLE IF NOT EXISTS users (
    user_id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL
);

-- Вставка тестовых данных
-- INSERT INTO users (username, email)
-- SELECT 
--     'user_' || i,
--     'user_' || i || '@example.com'
-- FROM generate_series(1, 1000) AS i
-- ON CONFLICT (email) DO NOTHING;