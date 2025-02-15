USE PYSAZ;

CREATE EVENT IF NOT EXISTS CheckExpirationVip
ON SCHEDULE EVERY 1 DAY
DO
DELETE FROM VIP_CLIENTS
WHERE Subcription_expiration_time <= NOW();

DELIMITER $$

CREATE EVENT IF NOT EXISTS check3DaysForSubmmitingLockedShoppingCart
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    -- Create a temporary table to store the aggregated data
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_distinct_carts (
        Product_ID INT,
        Quantity INT
    );

    -- Populate the temporary table with the aggregated quantities
    INSERT INTO temp_distinct_carts (Product_ID, Quantity)
    SELECT Product_ID, SUM(Quantity) AS Quantity
    FROM (
        SELECT DISTINCT LSC.ID, LSC.Cart_number, LSC.Number, PRODUCT.ID AS Product_ID, ADDED_TO.Quantity
        FROM PRODUCT
        JOIN ADDED_TO ON ADDED_TO.Product_ID = PRODUCT.ID
        JOIN LOCKED_SHOPPING_CART LSC ON ADDED_TO.ID = LSC.ID AND ADDED_TO.Cart_number = LSC.Cart_number
             AND LSC.Number = ADDED_TO.Locked_number
        JOIN SHOPPING_CART SH ON LSC.ID = SH.ID AND LSC.Cart_number = SH.Number
        WHERE SH.Status != 'active' AND LSC.Timestamp < NOW() - INTERVAL 3 DAY
    ) AS distinct_carts
    GROUP BY Product_ID;

    -- Update the PRODUCT table using the temporary table
    UPDATE PRODUCT
    JOIN temp_distinct_carts ON PRODUCT.ID = temp_distinct_carts.Product_ID
    SET PRODUCT.Stock_count = PRODUCT.Stock_count + temp_distinct_carts.Quantity;

    UPDATE SHOPPING_CART SH JOIN LOCKED_SHOPPING_CART LSC ON SH.ID = LSC.ID and SH.Number = LSC.Cart_number
    SET Status = 'blocked'
    WHERE SH.Status != 'active' AND LSC.Timestamp < NOW() - INTERVAL 3 DAY;

    -- Drop the temporary table to clean up
    DROP TEMPORARY TABLE IF EXISTS temp_distinct_carts;
END$$

DELIMITER ;

DELIMITER //

CREATE EVENT IF NOT EXISTS everyMonthBacking15PercentOfShoppingToVipClientsWallet
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN 
     CREATE TEMPORARY TABLE IF NOT EXISTS vipClients (
          ID INT,
          Cart_number INT,
          Locked_number INT,
          Total_cart_price INT
     );

     INSERT INTO vipClients
     SELECT ID, Cart_number, Locked_number ,SUM(Quantity * Cart_price) Total_cart_price
     FROM ADDED_TO NATURAL JOIN VIP_CLIENTS
     GROUP BY ID, Cart_number, Locked_number;

     UPDATE CLIENT NATURAL JOIN vipClients v NATURAL JOIN ISSUED_FOR JOIN TRANSACTION T
     ON T.Tracking_code = ISSUED_FOR.Tracking_code
     JOIN LOCKED_SHOPPING_CART LSC ON v.ID = LSC.ID and v.Cart_number and v.Locked_number = LSC.Number   
     SET Wallet_balance = Wallet_balance + (0.15 * Total_cart_price)
     WHERE T.Status = TRUE and LSC.Timestamp > NOW() - INTERVAL 30 DAY;

     DROP table vipClients;
END;//
DELIMITER ;

-- after 7 days of blocking carts will active them
CREATE EVENT IF NOT EXISTS doActiveAfter7Days
ON SCHEDULE EVERY 1 DAY
DO 

     UPDATE SHOPPING_CART SH
     JOIN LOCKED_SHOPPING_CART LSC
     ON  SH.ID = LSC.ID and SH.Number = LSC.Cart_number
     SET Status = 'active'
     WHERE LSC.Timestamp < NOW() - 10 and Status = 'blocked' 
