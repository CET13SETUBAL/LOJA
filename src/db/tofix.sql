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
    is_active BOOLEAN DEFAULT TRUE,
    inactive_reason TEXT,
    product_type ENUM('Livro', 'Eletronica') NOT NULL
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
    status ENUM('Activo', 'Inactivo', 'Bloqueado') DEFAULT 'Activo'
);

-- Tabela Encomendas
CREATE TABLE `Order` (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT,
    order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    shipping_method VARCHAR(50),
    status VARCHAR(50),
    card_number VARCHAR(20),
    cardholder_name VARCHAR(100),
    card_expiry DATE,
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
    INSERT INTO `Order` (customer_id, shipping_method, card_number, cardholder_name, card_expiry)
    VALUES (custId, shipMethod, cardNum, cardName, cardExpiry);
END //

-- Procedimento armazenado AddProductToOrder
CREATE PROCEDURE AddProductToOrder (
    IN orderId INT, IN prodId INT, IN prodQuantity INT)
BEGIN
    INSERT INTO Ordered_Item (order_id, product_id, quantity)
    VALUES (orderId, prodId, prodQuantity);
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
--2025!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

-- ProductByType: Returns product details filtered by type
CREATE PROCEDURE ProductByType(IN product_type VARCHAR(50))
BEGIN
    IF product_type IS NULL THEN
        SELECT p.product_id, p.price, p.popularity_rating, p.active, p.image_path,
               CASE
                   WHEN b.isbn IS NOT NULL THEN 'Book'
                   WHEN e.serial_number IS NOT NULL THEN 'Electronics'
               END AS product_type
        FROM Product p
        LEFT JOIN Book b ON p.product_id = b.product_id
        LEFT JOIN Electronics e ON p.product_id = e.product_id;
    ELSE
        SELECT p.product_id, p.price, p.popularity_rating, p.active, p.image_path,
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
CREATE PROCEDURE DailyOrders(IN order_date DATE)
BEGIN
    SELECT *
    FROM `Order` o
    WHERE DATE(o.order_datetime) = order_date;
END //

-- AnnualOrders: Returns all orders placed by a customer in a specific year
CREATE PROCEDURE AnnualOrders(IN customer_id INT, IN order_year INT)
BEGIN
    SELECT *
    FROM `Order` o
    WHERE o.customer_id = customer_id
    AND YEAR(o.order_datetime) = order_year;
END //

-- CreateOrder: Creates a new order
CREATE PROCEDURE CreateOrder(
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
        order_datetime,
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
CREATE PROCEDURE GetOrderTotal(IN p_order_id INT, OUT p_total DECIMAL(10,2))
BEGIN
    SELECT SUM(oi.quantity * p.price * (1 + p.vat_rate/100)) INTO p_total
    FROM Ordered_Item oi
    JOIN Product p ON oi.product_id = p.product_id
    WHERE oi.order_id = p_order_id;
END //

-- AddProductToOrder: Adds a product to an order
CREATE PROCEDURE AddProductToOrder(
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
CREATE PROCEDURE AddBook(
    IN p_quantity INT,
    IN p_price DECIMAL(10,2),
    IN p_vat_rate DECIMAL(5,2),
    IN p_popularity_rating INT,
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
        popularity_rating,
        image_path,
        active,
        inactive_reason
    ) VALUES (
        p_quantity,
        p_price,
        p_vat_rate,
        p_popularity_rating,
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
CREATE PROCEDURE AddElec(
    IN p_quantity INT,
    IN p_price DECIMAL(10,2),
    IN p_vat_rate DECIMAL(5,2),
    IN p_popularity_rating INT,
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
        popularity_rating,
        image_path,
        active,
        inactive_reason
    ) VALUES (
        p_quantity,
        p_price,
        p_vat_rate,
        p_popularity_rating,
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