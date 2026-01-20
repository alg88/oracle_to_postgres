CREATE OR REPLACE FUNCTION migration.test_query(p_sql text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  -- matches TEXT[];  -- Массив для хранения найденных параметров
    v_param TEXT;
    v_sql text;
    v_result TEXT;
    v_cnt  integer;
    v_code text;
   v_dummy integer;
BEGIN
	v_sql := p_sql;
    -- Извлечение всех параметров из строки запроса, перебор их и замена нв null
    FOR v_param IN 
         SELECT par
           FROM (
              SELECT unnest(regexp_matches(p_sql, ':\w+', 'g')) as par
              ) a
          ORDER BY length(par) desc
    LOOP
	   v_sql := REPLACE(v_sql, v_param, 'NULL');
	   v_sql := REPLACE(v_sql, v_param, 'NULL'); --делаем еще 1 про

    END LOOP;

    if upper(substr(trim(v_sql),1,6)) = 'SELECT' then
    
	    v_sql = 'select count(*) from ('||v_sql||') b';
	    
	    EXECUTE v_sql
	    into v_cnt;
	else
	
	    EXECUTE v_sql;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        v_result := 'ok';
        v_dummy := 1/0 ; --откатим изменение и перехватим исключение
    end if;
   
    v_result := 'ok';
    
    RETURN v_result;
         
EXCEPTION
    when division_by_zero   then
      --RAISE WARNING 'rollback';
      RETURN v_result;
      
    WHEN OTHERS THEN
        -- Получаем код состояния SQL и сообщение об ошибке
      GET STACKED DIAGNOSTICS
         v_code = PG_EXCEPTION_CONTEXT;
--        GET DIAGNOSTICS v_code = RETURNED_SQLSTATE;
--        RETURN format('Error: %s (SQLSTATE: %s)', SQLERRM, v_code);
         RETURN format('Error: %s', SQLERRM);
END;
$function$
;
