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