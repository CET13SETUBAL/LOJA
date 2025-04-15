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
CREATE TABLE Electronic (
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
