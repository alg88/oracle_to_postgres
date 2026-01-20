-----------------------------------------------------------
---------Внешние ключи -----------------------------------------------
-----------------------------------------------------
1) ddl выгрузки внешних ключей схемы (add+drop)

WITH fk_constraints AS (
    SELECT
        tc.constraint_name,
        tc.table_schema,
        tc.table_name,
        kcu.ordinal_position,
        kcu.column_name,
        ccu.table_schema AS foreign_table_schema,
        ccu.table_name AS foreign_table_name,
        ccu.column_name AS foreign_column_name,
        rc.delete_rule
    FROM
        information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage AS ccu
            ON ccu.constraint_name = tc.constraint_name
            AND ccu.constraint_schema = tc.table_schema
        JOIN information_schema.referential_constraints AS rc
            ON rc.constraint_name = tc.constraint_name
            AND rc.constraint_schema = tc.table_schema
    WHERE
        tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema = 'instruction'  -- замените на вашу схему
),
grouped_fk AS (
    SELECT
        constraint_name,
        table_schema,
        table_name,
        foreign_table_schema,
        foreign_table_name,
        delete_rule,
        string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) AS columns,
        string_agg(quote_ident(foreign_column_name), ', ' ORDER BY ordinal_position) AS foreign_columns
    FROM
        fk_constraints
    GROUP BY
        constraint_name,
        table_schema,
        table_name,
        foreign_table_schema,
        foreign_table_name,
        delete_rule
)
SELECT
    'ALTER TABLE ' ||
    quote_ident(table_schema) || '.' || quote_ident(table_name) ||
    ' ADD CONSTRAINT ' || quote_ident(constraint_name) ||
    ' FOREIGN KEY (' || columns || ')' ||
    ' REFERENCES ' || quote_ident(foreign_table_schema) || '.' || quote_ident(foreign_table_name) ||
    ' (' || foreign_columns || ')' ||
    ' ON DELETE ' || delete_rule || ';' AS ddl_statement

   ,'ALTER TABLE ' ||
    quote_ident(table_schema) || '.' || quote_ident(table_name) ||
    ' DROP CONSTRAINT ' || quote_ident(constraint_name) || ';' AS drop_statement
FROM
    grouped_fk
   order by table_name, constraint_name;


2) ddl удаления внешних ключей схемы 

SELECT
    'ALTER TABLE ' ||
    quote_ident(tc.table_schema) || '.' || quote_ident(tc.table_name) ||
    ' DROP CONSTRAINT ' || quote_ident(tc.constraint_name) || ';' AS drop_statement
FROM
    information_schema.table_constraints AS tc
WHERE
    tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'instruction'; 


-----------------------------------------------------------
---------Индексы -----------------------------------------------
-----------------------------------------------------

3) ddl удаления всех индексов

SELECT
    'DROP INDEX IF EXISTS ' || quote_ident(n.nspname) || '.' || quote_ident(i.relname) || ';' AS drop_index_sql
FROM
    pg_class i
    JOIN pg_namespace n ON n.oid = i.relnamespace
WHERE
    i.relkind = 'i' -- индекс
    AND n.nspname = 'instruction'; -- замените на вашу схему  
    

3.1) ddl удаления м создания всех индексов, кроме PK

SELECT 
'DROP INDEX ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname) || ';' AS drop_statement,
pg_get_indexdef(i.indexrelid) || ';' AS ddl
FROM
    pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE
    n.nspname = 'instruction'
     AND i.indisprimary = false -- исключаем первичные ключи
  order by c.relname, indisunique;

4) DDL всех индексов, кроме PK
SELECT pg_get_indexdef(i.indexrelid) || ';' AS ddl
FROM
    pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE
    n.nspname = 'instruction'
     AND i.indisprimary = false -- исключаем первичные ключи
  order by c.relname, indisunique;

------------------------------------------------------------------------
----------Таблицы----------------------------------------------
---------------------------------------------------------------------
5)  TRUNCATE TABLE

SELECT 'TRUNCATE TABLE ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname)
       --||' RESTART IDENTITY CASCADE'
       ||';' 
       AS truncate_statement
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' -- обычные таблицы
  AND n.nspname = 'instruction' -- замените на вашу схему
  order by c.relname;

6) Последовательности
SELECT 'DROP SEQUENCE '||quote_ident(n.nspname) || '.' || quote_ident(c.relname)||';'
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
where 1=1
  and c.relkind = 'S' -- последовательности
  AND n.nspname = 'instruction' -- замените на вашу схему
  and c.relname like 'seq%'
  order by c.relname;