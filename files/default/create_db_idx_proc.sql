-- Procedure to create an index on a table IF
-- an index on that column does not already exist
-- NOTE: Index name is not checked, only if the
--       index exists
DELIMITER $$

# This 'owners' column is too big for RonDB, reduce from 5000 to 1000 in length
ALTER TABLE `airflow`.`dag` MODIFY owners VARCHAR(1000);

DROP PROCEDURE IF EXISTS `airflow`.`create_idx` $$
CREATE PROCEDURE `airflow`.`create_idx`(
    target_schema VARCHAR(100),
    target_table  VARCHAR(100),
    target_column VARCHAR(100),
    idx_name      VARCHAR(100)
)
BEGIN
    DECLARE index_exists INTEGER;
    
    SELECT COUNT(1) INTO index_exists
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE table_schema = target_schema
    AND   table_name   = target_table
    AND	  column_name  = target_column;

    IF index_exists = 0 THEN
       SET @sqlstmt = CONCAT('CREATE INDEX ', idx_name, ' ON ',
           target_schema, '.', target_table, ' (', target_column, ')');
       PREPARE stmt FROM @sqlstmt;
       EXECUTE stmt;
       DEALLOCATE PREPARE stmt;
    ELSE
       SELECT CONCAT('Index already exist on column ', target_schema,
       '.', target_table, '.', target_column) index_exists_error;
    END	IF;	
END $$

DELIMITER ;
