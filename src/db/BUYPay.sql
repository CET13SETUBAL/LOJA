-- Criar Base de Dados

drop database IF exists BuyPy; 
CREATE DATABASE BuyPy;
USE BuyPy;

-- Tabela Produtos
CREATE TABLE Product (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    quantity INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    vat_rate DECIMAL(4,2) NOT NULL,
    popularity INT CHECK (popularity BETWEEN 1 AND 5),
    image_path VARCHAR(255),
    active BOOLEAN DEFAULT TRUE,
    inactive_reason TEXT,
    product_type ENUM('Book', 'Electronics') NOT NULL
);

-- Tabela Livros
CREATE TABLE Book (
    product_id INT PRIMARY KEY,
    isbn VARCHAR(13) UNIQUE,
    title VARCHAR(255),
    genre VARCHAR(100),
    publisher VARCHAR(100),
    author VARCHAR(100),
    publication_date DATE,
    FOREIGN KEY (product_id) REFERENCES Product(product_id)
);

-- Tabela Eletrónicos
CREATE TABLE Electronics (
    product_id INT PRIMARY KEY,
    serial_number VARCHAR(50),
    brand VARCHAR(50),
    model VARCHAR(50),
    technical_specs TEXT,
    consumable_type VARCHAR(50),
    FOREIGN KEY (product_id) REFERENCES Product(product_id)
);

-- Tabela Clientes
CREATE TABLE Customer (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(255) UNIQUE,
    password VARCHAR(100),
    address VARCHAR(255),
    postal_code VARCHAR(20),
    city VARCHAR(50),
    country VARCHAR(50),
    phone_number VARCHAR(20),
    status ENUM('active', 'inactive', 'blocked') DEFAULT 'active'
);

-- Tabela Encomendas
CREATE TABLE `Order` (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT,
    order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    shipping_method VARCHAR(50),
    status VARCHAR(50),
    card_number VARCHAR(20),
    card_holder_name VARCHAR(100),
    card_expiry_date DATE,
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id)
);

-- Tabela Produtos Encomendados
CREATE TABLE Ordered_Item (
    order_id INT,
    product_id INT,
    quantity INT,
    PRIMARY KEY (order_id, product_id),
    FOREIGN KEY (order_id) REFERENCES `Order`(order_id),
    FOREIGN KEY (product_id) REFERENCES Product(product_id)
);

-- Tabela Recomendações
CREATE TABLE Recommendation (
    recommendation_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT,
    product_id INT,
    recommendation_date DATE,
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id),
    FOREIGN KEY (product_id) REFERENCES Product(product_id)
);

-- Tabela Operadores
CREATE TABLE Operator (
    operator_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(255) UNIQUE,
    password VARCHAR(100)
);







-- Procedimento armazenado GetOrderTotal
DELIMITER //
CREATE PROCEDURE GetOrderTotal (IN orderId INT)
BEGIN
    SELECT SUM(p.price * oi.quantity) AS total_amount
    FROM Ordered_Item oi
    INNER JOIN Product p ON oi.product_id = p.product_id
    WHERE oi.order_id = orderId;
END //

-- Procedimento armazenado CreateOrder
CREATE PROCEDURE CreateOrder (
    IN custId INT, IN shipMethod VARCHAR(50),
    IN cardNum VARCHAR(20), IN cardName VARCHAR(100), IN cardExpiry DATE)
BEGIN
    INSERT INTO `Order` (customer_id, shipping_method, card_number, card_holder_name, card_expiry_date)
    VALUES (custId, shipMethod, cardNum, cardName, cardExpiry);
END //

-- Procedimento armazenado AddProductToOrder
CREATE PROCEDURE AddProductToOrder (
    IN orderId INT, IN prodId INT, IN prodQuantity INT)
BEGIN
    INSERT INTO Ordered_Item (order_id, product_id, quantity)
    VALUES (orderId, prodId, prodQuantity);
END //

-- ProductByType: Returns product details filtered by type
CREATE PROCEDURE ProductByType_(IN product_type VARCHAR(50))
BEGIN
    IF product_type IS NULL THEN
        SELECT p.product_id, p.price, p.popularity, p.active, p.image_path,
               CASE
                   WHEN b.isbn IS NOT NULL THEN 'Book'
                   WHEN e.serial_number IS NOT NULL THEN 'Electronics'
               END AS product_type
        FROM Product p
        LEFT JOIN Book b ON p.product_id = b.product_id
        LEFT JOIN Electronics e ON p.product_id = e.product_id;
    ELSE
        SELECT p.product_id, p.price, p.popularity, p.active, p.image_path,
               product_type
        FROM Product p
        LEFT JOIN Book b ON p.product_id = b.product_id
        LEFT JOIN Electronics e ON p.product_id = e.product_id
        WHERE 
            CASE
                WHEN product_type = 'Book' THEN b.isbn IS NOT NULL
                WHEN product_type = 'Electronics' THEN e.serial_number IS NOT NULL
            END;
    END IF;
END //

-- DailyOrders: Returns all orders for a specific date
CREATE PROCEDURE DailyOrders_(IN order_date DATE)
BEGIN
    SELECT *
    FROM `Order` o
    WHERE DATE(o.order_date) = order_date;
END //

-- AnnualOrders: Returns all orders placed by a customer in a specific year
CREATE PROCEDURE AnnualOrders_(IN customer_id INT, IN order_year INT)
BEGIN
    SELECT *
    FROM `Order` o
    WHERE o.customer_id = customer_id
    AND YEAR(o.order_date) = order_year;
END //

-- CreateOrder: Creates a new order
CREATE PROCEDURE CreateOrder_(
    IN p_customer_id INT,
    IN p_shipping_method VARCHAR(100),
    IN p_card_number VARCHAR(20),
    IN p_card_holder_name VARCHAR(100),
    IN p_card_expiry_date DATE,
    OUT p_order_id INT
)
BEGIN
    INSERT INTO `Order` (
        customer_id,
        order_date,
        shipping_method,
        status,
        card_number,
        card_holder_name,
        card_expiry_date
    ) VALUES (
        p_customer_id,
        NOW(),
        p_shipping_method,
        'Pending', -- Initial status
        p_card_number,
        p_card_holder_name,
        p_card_expiry_date
    );
    
    SET p_order_id = LAST_INSERT_ID();
END //

-- GetOrderTotal: Calculates the total amount of an order
CREATE PROCEDURE GetOrderTotal_(IN p_order_id INT, OUT p_total DECIMAL(10,2))
BEGIN
    SELECT SUM(oi.quantity * p.price * (1 + p.vat_rate/100)) INTO p_total
    FROM Ordered_Item oi
    JOIN Product p ON oi.product_id = p.product_id
    WHERE oi.order_id = p_order_id;
END //

-- AddProductToOrder: Adds a product to an order
CREATE PROCEDURE AddProductToOrder_(
    IN p_order_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE current_stock INT;
    
    -- Check if product exists and has enough stock
    SELECT quantity INTO current_stock FROM Product WHERE product_id = p_product_id;
    
    IF current_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product not found';
    ELSEIF current_stock < p_quantity THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Not enough stock available';
    ELSE
        -- Add product to order
        INSERT INTO Ordered_Item (order_id, product_id, quantity)
        VALUES (p_order_id, p_product_id, p_quantity)
        ON DUPLICATE KEY UPDATE quantity = quantity + p_quantity;
        
        -- Update product stock
        UPDATE Product SET quantity = quantity - p_quantity WHERE product_id = p_product_id;
    END IF;
END //

-- AddBook: Adds a book product to the database
CREATE PROCEDURE AddBook_(
    IN p_quantity INT,
    IN p_price DECIMAL(10,2),
    IN p_vat_rate DECIMAL(5,2),
    IN p_popularity INT,
    IN p_image_path VARCHAR(255),
    IN p_isbn VARCHAR(20),
    IN p_title VARCHAR(255),
    IN p_genre VARCHAR(100),
    IN p_publisher VARCHAR(100),
    IN p_author VARCHAR(100),
    IN p_publication_date DATE
)
BEGIN
    DECLARE new_product_id INT;
    
    -- Insert into Product table first
    INSERT INTO Product (
        quantity,
        price,
        vat_rate,
        popularity,
        image_path,
        active,
        inactive_reason
    ) VALUES (
        p_quantity,
        p_price,
        p_vat_rate,
        p_popularity,
        p_image_path,
        TRUE,  -- Active by default
        NULL   -- No inactive reason since it's active
    );
    
    SET new_product_id = LAST_INSERT_ID();
    
    -- Insert into Book table
    INSERT INTO Book (
        product_id,
        isbn,
        title,
        genre,
        publisher,
        author,
        publication_date
    ) VALUES (
        new_product_id,
        p_isbn,
        p_title,
        p_genre,
        p_publisher,
        p_author,
        p_publication_date
    );
END //

-- AddElec: Adds an electronics product to the database
CREATE PROCEDURE AddElec_(
    IN p_quantity INT,
    IN p_price DECIMAL(10,2),
    IN p_vat_rate DECIMAL(5,2),
    IN p_popularity INT,
    IN p_image_path VARCHAR(255),
    IN p_serial_number VARCHAR(50),
    IN p_brand VARCHAR(100),
    IN p_model VARCHAR(100),
    IN p_tech_specs TEXT,
    IN p_type VARCHAR(100)
)
BEGIN
    DECLARE new_product_id INT;
    
    -- Insert into Product table first
    INSERT INTO Product (
        quantity,
        price,
        vat_rate,
        popularity,
        image_path,
        active,
        inactive_reason
    ) VALUES (
        p_quantity,
        p_price,
        p_vat_rate,
        p_popularity,
        p_image_path,
        TRUE,  -- Active by default
        NULL   -- No inactive reason since it's active
    );
    
    SET new_product_id = LAST_INSERT_ID();
    
    -- Insert into Electronics table
    INSERT INTO Electronics (
        product_id,
        serial_number,
        brand,
        model,
        tech_specs,
        type
    ) VALUES (
        new_product_id,
        p_serial_number,
        p_brand,
        p_model,
        p_tech_specs,
        p_type
    );
END //




DELIMITER ;

-- Utilizador WEB_CLIENT com privilégios específicos
CREATE USER IF NOT EXISTS 'WEB_CLIENT' IDENTIFIED BY 'Lmxy20#a';
GRANT SELECT ON BuyPy.* TO 'WEB_CLIENT';
GRANT INSERT, UPDATE ON BuyPy.Customer TO 'WEB_CLIENT';
GRANT INSERT, UPDATE, DELETE ON BuyPy.`Order` TO 'WEB_CLIENT';
GRANT DELETE ON BuyPy.Ordered_Item TO 'WEB_CLIENT';
GRANT UPDATE (quantity) ON BuyPy.Product TO 'WEB_CLIENT';
GRANT EXECUTE ON PROCEDURE BuyPy.CreateOrder TO 'WEB_CLIENT';
GRANT EXECUTE ON PROCEDURE BuyPy.GetOrderTotal TO 'WEB_CLIENT';
GRANT EXECUTE ON PROCEDURE BuyPy.AddProductToOrder TO 'WEB_CLIENT';

-- Utilizadores Operadores e Admin com privilégios totais
CREATE USER IF NOT EXISTS 'BUYDB_OPERATOR' IDENTIFIED BY 'Lmxy20#a';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON BuyPy.* TO 'BUYDB_OPERATOR';

CREATE USER IF NOT EXISTS 'BUYDB_ADMIN' IDENTIFIED BY 'Lmxy20#a';
GRANT ALL PRIVILEGES ON BuyPy.* TO 'BUYDB_ADMIN' WITH GRANT OPTION;


INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, product_type) 
VALUES (50, 19.99, 0.23, 4, '/images/prod1.jpg', TRUE, 'Livro');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, product_type) 
VALUES (25, 899.99, 0.23, 5, '/images/laptop1.jpg', TRUE, 'Eletronica');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, inactive_reason, product_type) 
VALUES (0, 14.99, 0.23, 2, '/images/prod2.jpg', FALSE, 'Esgotado', 'Livro');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, product_type) 
VALUES (10, 129.99, 0.23, 3, '/images/headphones.jpg', TRUE, 'Eletronica');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, product_type) 
VALUES (100, 9.99, 0.06, 4, '/images/book3.jpg', TRUE, 'Livro');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, product_type) 
VALUES (30, 599.99, 0.23, 5, '/images/tablet1.jpg', TRUE, 'Eletronica');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, product_type) 
VALUES (15, 24.99, 0.23, 3, '/images/book4.jpg', TRUE, 'Livro');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, inactive_reason, product_type) 
VALUES (0, 49.99, 0.23, 1, '/images/old_model.jpg', FALSE, 'Descontinuado', 'Eletronica');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, product_type) 
VALUES (40, 12.99, 0.06, 4, '/images/book5.jpg', TRUE, 'Livro');

INSERT INTO Product (quantity, price, vat_rate, popularity, image_path, active, product_type) 
VALUES (8, 1299.99, 0.23, 5, '/images/gaming_pc.jpg', TRUE, 'Eletronica');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (1, '9781234567890', 'Aventuras no Espaço', 'Ficção Científica', 'Editora Galáxia', 'Carlos Astronauta', '2020-05-15');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (5, '9789876543210', 'História da Arte Moderna', 'Arte', 'Editora Cultura', 'Maria Pintora', '2018-11-22');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (7, '9784567891230', 'O Mistério do Castelo', 'Mistério', 'Editora Suspense', 'João Detetive', '2021-03-10');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (9, '9783216549870', 'Receitas Saudáveis', 'Culinária', 'Editora Sabor', 'Ana Chef', '2019-07-30');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (3, '9781593572468', 'Poemas do Coração', 'Poesia', 'Editora Verso', 'Pedro Poeta', '2017-02-14');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (10, '9787539514682', 'Aprendendo SQL', 'Tecnologia', 'Editora Dados', 'Lucas Programador', '2022-01-05');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (11, '9788529631478', 'Viagens pelo Mundo', 'Viagem', 'Editora Aventura', 'Marta Viajante', '2016-09-18');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (12, '9783692581470', 'Negócios Digitais', 'Negócios', 'Editora Sucesso', 'Ricardo Empreendedor', '2021-08-25');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (13, '9781478529630', 'Jardins Urbanos', 'Jardinagem', 'Editora Verde', 'Cláudia Jardineira', '2020-04-12');

INSERT INTO Book (product_id, isbn, title, genre, publisher, author, publication_date) 
VALUES (14, '9782583691470', 'Filosofia Contemporânea', 'Filosofia', 'Editora Pensamento', 'Sofia Filósofa', '2019-10-08');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (2, 'LP12345678', 'TechMaster', 'UltraBook Pro', 'CPU: i7, RAM: 16GB, SSD: 512GB', 'Laptop');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (4, 'HP87654321', 'SoundPlus', 'Quantum 3000', 'Wireless, Noise Cancelling, 30h battery', 'Headphones');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (6, 'TB36925814', 'TabTech', 'Galaxy Tab X', '10.5" AMOLED, 128GB, 8GB RAM', 'Tablet');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (8, 'PC14785296', 'GameForce', 'Titan Z', 'RTX 3080, i9, 32GB RAM, 1TB SSD', 'Desktop');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (15, 'SP96385274', 'SmartPlus', 'Watch 5', 'AMOLED, GPS, Heart Rate Monitor', 'Smartwatch');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (16, 'KB74185296', 'KeyMaster', 'Mechanical Pro', 'RGB, Cherry MX Red, Anti-ghosting', 'Keyboard');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (17, 'MS85296314', 'PrecisionTech', 'Master 500', '16000 DPI, Wireless, 6 buttons', 'Mouse');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (18, 'MO36914785', 'ViewPlus', 'UltraHD 32"', '4K, HDR, 144Hz, IPS', 'Monitor');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (19, 'DR25814796', 'DataSafe', 'External 2TB', 'USB 3.2, 5400 RPM, Backup Software', 'External Drive');

INSERT INTO Electronics (product_id, serial_number, brand, model, technical_specs, consumable_type) 
VALUES (20, 'SP98765432', 'PowerUp', 'FastCharge 100W', '4 ports, GaN Technology, Compact', 'Charger');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('João', 'Silva', 'joao.silva@email.com', 'hashedpass123', 'Rua das Flores 123', '1000-001', 'Lisboa', 'Portugal', '+351912345678', 'active');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Maria', 'Santos', 'maria.santos@email.com', 'hashedpass456', 'Avenida Central 45', '2000-002', 'Porto', 'Portugal', '+351923456789', 'active');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Carlos', 'Pereira', 'carlos.pereira@email.com', 'hashedpass789', 'Travessa do Sol 67', '3000-003', 'Coimbra', 'Portugal', '+351934567890', 'inactive');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Ana', 'Oliveira', 'ana.oliveira@email.com', 'hashedpass012', 'Praça da Liberdade 8', '4000-004', 'Braga', 'Portugal', '+351945678901', 'blocked');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Pedro', 'Martins', 'pedro.martins@email.com', 'hashedpass345', 'Rua do Comércio 12', '5000-005', 'Faro', 'Portugal', '+351956789012', 'active');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Sofia', 'Ribeiro', 'sofia.ribeiro@email.com', 'hashedpass678', 'Avenida dos Descobrimentos 34', '6000-006', 'Setúbal', 'Portugal', '+351967890123', 'active');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Miguel', 'Fernandes', 'miguel.fernandes@email.com', 'hashedpass901', 'Rua da Escola 56', '7000-007', 'Évora', 'Portugal', '+351978901234', 'inactive');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Inês', 'Gomes', 'ines.gomes@email.com', 'hashedpass234', 'Travessa das Oliveiras 78', '8000-008', 'Aveiro', 'Portugal', '+351989012345', 'active');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Rui', 'Lopes', 'rui.lopes@email.com', 'hashedpass567', 'Avenida da República 90', '9000-009', 'Viseu', 'Portugal', '+351990123456', 'blocked');

INSERT INTO Customer (first_name, last_name, email, password, address, postal_code, city, country, phone_number, status) 
VALUES ('Beatriz', 'Marques', 'beatriz.marques@email.com', 'hashedpass890', 'Rua do Jardim 11', '1000-010', 'Lisboa', 'Portugal', '+351901234567', 'active');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (1, '2023-01-15 10:30:00', 'Standard', 'Entregue', '************1234', 'João Silva', '2025-12-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (2, '2023-02-20 14:45:00', 'Express', 'Em Processamento', '************5678', 'Maria Santos', '2024-10-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (5, '2023-03-05 09:15:00', 'Standard', 'Enviado', '************9012', 'Pedro Martins', '2026-05-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (6, '2023-04-10 16:20:00', 'Express', 'Entregue', '************3456', 'Sofia Ribeiro', '2025-08-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (8, '2023-05-12 11:10:00', 'Standard', 'Cancelado', '************7890', 'Inês Gomes', '2024-11-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (10, '2023-06-18 13:25:00', 'Express', 'Entregue', '************2345', 'Beatriz Marques', '2025-07-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (1, '2023-07-22 15:40:00', 'Standard', 'Enviado', '************6789', 'João Silva', '2025-12-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (2, '2023-08-30 12:05:00', 'Express', 'Em Processamento', '************0123', 'Maria Santos', '2024-10-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (5, '2023-09-14 10:50:00', 'Standard', 'Entregue', '************4567', 'Pedro Martins', '2026-05-01');

INSERT INTO `Order` (customer_id, order_date, shipping_method, status, card_number, card_holder_name, card_expiry_date) 
VALUES (6, '2023-10-25 17:15:00', 'Express', 'Enviado', '************8901', 'Sofia Ribeiro', '2025-08-01');

INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (1, 1, 2);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (1, 5, 1);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (2, 2, 1);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (3, 7, 3);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (4, 4, 2);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (5, 6, 1);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (6, 9, 1);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (7, 3, 2);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (8, 10, 1);
INSERT INTO Ordered_Item (order_id, product_id, quantity) VALUES (9, 15, 1);

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (1, 2, '2023-01-10');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (2, 5, '2023-02-15');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (5, 7, '2023-03-01');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (6, 4, '2023-04-05');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (8, 6, '2023-05-08');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (10, 9, '2023-06-12');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (1, 10, '2023-07-18');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (2, 15, '2023-08-22');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (5, 1, '2023-09-28');

INSERT INTO Recommendation (customer_id, product_id, recommendation_date) 
VALUES (6, 3, '2023-10-30');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Admin', 'Sistema', 'admin@loja.com', 'admin123');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Luís', 'Rodrigues', 'luis.rodrigues@loja.com', 'operator456');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Teresa', 'Almeida', 'teresa.almeida@loja.com', 'operator789');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Ricardo', 'Nunes', 'ricardo.nunes@loja.com', 'operator012');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Catarina', 'Machado', 'catarina.machado@loja.com', 'operator345');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Hugo', 'Pinto', 'hugo.pinto@loja.com', 'operator678');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Diana', 'Teixeira', 'diana.teixeira@loja.com', 'operator901');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('André', 'Ferreira', 'andre.ferreira@loja.com', 'operator234');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Sara', 'Cardoso', 'sara.cardoso@loja.com', 'operator567');

INSERT INTO Operator (first_name, last_name, email, password) 
VALUES ('Gonçalo', 'Mendes', 'goncalo.mendes@loja.com', 'operator890');