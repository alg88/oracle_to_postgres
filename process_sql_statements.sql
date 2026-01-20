CREATE OR REPLACE FUNCTION migration.process_sql_statements()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_rec    RECORD;
    v_result TEXT;
BEGIN
    -- Перебор всех SQL выражений из таблицы
    FOR v_rec IN SELECT l.sql_text, l.id FROM migration.test_sql_list l LOOP
        -- Вызов функции и получение результата
        v_result := migration.test_query(v_rec.sql_text);
        
        -- Вывод результата
--        RAISE NOTICE 'SQL: %, Result: %', v_result, v_rec.sql_text;
       update migration.test_sql_list l
         set processed_date  = clock_timestamp()
             ,errc = case when upper(v_result) = 'OK' then 'S' else 'E' end
             ,errm = v_result
       where l.id = v_rec.id;
    END LOOP;
END;
$function$
;
