Ниже приводится решение по миграции приложения из базы данных Oracle в Postgres. Ограничение - базе данных нет хранимых процедур, все SQL запоросы приходят из приложения.

Основные действия:

- Выбрать все запросы из библиотечного кэша базы данных Oracle работающего приложения

- Создать таблицы в базе данных postgres с помощью утилиты ora2pg или иным способом

- Загрузить выбранные запросы в таблицу Postgres и прогнать их на пустых таблицах (можно и с данными), разработав для этого несложную процедуру в pgsql

- Провести анализ ошибок, создать аналоги функций Oracle в Postgres (либо установить расширение orafce), поправить запросы, возможно создать функции в oracle для обратной совместимости приложения. Исправить конструкции, неработающие в Postgres.

- Выборку запросов можно обогатить, прогнав php-код в нейрочатах с адекватным промптом. Так можно найти редкоиспользуемые sql.

Данные выгрузить из Oracle с помощью утилиты ora2pg и загрузить в Postgres с помощью psql.

Теперь рассмотрим каждый шаг подробнее.

1.       Выборка всех запросов приложения из библиотечного кэша базы данных Oracle.

Выводим в пул SQL для дальнейшей вставки в тестовую таблицу migration.test_sql_list. Условия в where запроса нужно скорректировать исходя из Вашей базы данных. Нам оказалось достаточно указания имени схемы.

DECLARE
  l_sql VARCHAR2(32000);
BEGIN
  dbms_output.enable(1000000);
  FOR r1 IN (
        SELECT a.SQL_FULLTEXT
          FROM v$sqlarea a
         WHERE a.PARSING_SCHEMA_NAME NOT IN ('SYS','DBSNMP','DBSNMP','INSTRUCTION_TEST','ASSESSMENT_USER','AUDSYS','ORACLE_OCM','DIADMIN') –исключаем ненужное
             AND upper(a.SQL_TEXT) LIKE '%XXX%' –условие для выбора только нужных запросов
        ORDER BY a.SQL_TEXT
        ) LOOP
     l_sql := 'INSERT INTO migration.test_sql_list(sql_text) VALUES ('''||replace(r1.sql_fulltext,'''','''''')||''');';
     dbms_output.put_line(l_sql);     
  END LOOP;  
END;
Объяснить код с
Выполнять скрипт желательно в часы наибольшей нагрузки. Еще лучше создать джоб для выборки уникальных SQL на разумное время с периодичностью 10 минут.

 

2.       Создаем таблицы в Postgres.

Можно установить утилиту ora2pg и использовать ее для выгрузки скриптов таблиц (мы использовали v25 утилиты):

>ora2pg -t TABLE -b /папка_для_миграции -c config/ora2pg.conf -o table.sql
>ora2pg -t SEQUENCE -b /папка_для_миграции -c config/ora2pg.conf -o sequence.sql
Объяснить код с
В ora2pg.conf предварительно нужно прописать параметры для соединения с базой данных Oracle. Созданные скрипты выполняются в базе данных Postgres через psql или иным способом.

 3.       Прогон запросов приложения в Postgres.

Для целей миграции создаем в базе Postgres схему migration, таблицу и 2 функции:

CREATE TABLE migration.test_sql_list (
	id serial4 NOT NULL,
	sql_text text NOT NULL,
	created_date timestamp NULL DEFAULT clock_timestamp(),
	processed_date timestamp NULL,
	errc varchar(1) NULL,
	errm text NULL,
	CONSTRAINT test_sql_list_pkey PRIMARY KEY (id));

CREATE OR REPLACE FUNCTION migration.test_query(p_sql text)
 RETURNS text
 LANGUAGE plpgsql;
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
      RETURN v_result;      
    WHEN OTHERS THEN
        -- Получаем код состояния SQL и сообщение об ошибке
      GET STACKED DIAGNOSTICS
         v_code = PG_EXCEPTION_CONTEXT;
END;
$function$
;

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
Объяснить код с
Первая функция принимает текст SQL запроса, заменяет переменные подстановки (bind variables) на NULL и выполняет сам запрос. Вторая – прогоняет все запросы из таблицы migration.test_sql_list  и сохраняет результат.

Теперь загружаем, полученные в п.1 запросы, в таблицу migration.test_sql_list и выполняем ф-цию

>select migration.process_sql_statements();
Объяснить код с
В таблице мы увидим результат 

Таблица migration.test_sql_list после работы функции migration.process_sql_statements();
Таблица migration.test_sql_list после работы функции migration.process_sql_statements();
В колонке errm отразится ошибка или успех работы каждого SQL в Postgres.

 4.       Анализ полученных результатов.

В таблицу собраны примеры конструкций, которые не будут работать в Postgres и способы решения.

Функции

Функция SYSDATE

аналог clock_timestamp(). Создать фунцию в Postgres c имененем SYSDATE(). Без скобок вариантов нет. Требуется переделка кода

NVL(p1,p2)

COALESCE(p1,p2). Создать фунцию в Postgres имененем NVL

NVL2(p1,p2,p3)

Исправить в коде на
CASE
WHEN p1 IS NULL THEN p2 
ELSE p3 
END
 Либо cоздать фунцию в Postgres c имененем NVL2. Указанным вариантом обойтись сложно из‑за перегрузки ф‑ций в Postgres. Нужно уходить в язык c, либо брать готовый вариатнт в orafce

to_number()

Создать фунцию в Postgres c имененем to_number()
(есть другие варианты CAST('123.45' AS NUMERIC), '123.45'::NUMERIC)

TO_DATE()

переделать на TO_TIMESTAMP() в приложении (TO_TIMESTAMP('2025-02-23 23:01.02','yyyy‑mm‑dd hh24:mi:ss')). Не хотелось бы подменять стандартную ф‑цию postgres to_date, которая возвращает тип DATE (без времени)

INSTR()

Создать фунцию в Postgres c имененем INSTR()

Последовательности

получение слеющено значения: имя_последовательности.nextval

Замена на функцию nextval('имя_последовательности')

Конструкции

ROWNUM (в where запросов)

аналог LIMIT n (ROWNUM=1 → LIMIT 1; ROWNUM<=10 → LIMIT 10) Нужно переделывать запросы

ROWNUM (в select запросов)

select ROW_NUMBER() OVER (ORDER BY 1) AS ROW_NUM from table — работает и в postgres, и в oracle. Переделка запросов в бэке

update table1 alias set alias.c1=

алиасы в полях не поддерживаются, нужно исправлять на update table1 alias set c1=, то есть писать без алиасов.

dual

создание view dual

псевдостолбец ROWID

псевдостолбец ctid, либо переделать на использование первичных ключей

 Полученные таким образом ошибки мы исправляем созданием функций аналогов Oracle в базе Postgres и переделками в коде. Несложно добиться работы кода в обеих базах. Можно установить расширение orafce, но в нашем случае это оказалось избыточным.

 Интересен вариант исправления работающего приложения в Oracle и итерационной выборки запросов. Так переход получится более плавным.

5.       Обогащаем SQL с помощью нейрочатов

Полученный в п.1 список sql может оказаться недостаточно полным в силу того, что какие-то отчеты могут запускаться раз в месяц, квартал. Здесь можно призвать на помощь нейрочаты, попросив сформировать запросы из программного кода.

Нам больше понравились результаты Gemini с моделями google/gemini-2.5-flash и google/gemini-2.5-pro. Использовали такой промпт + php-код:

“Сформируй все возможные sql запросы, который может создать приведенный ниже php код. Полученные sql запросы должны быть вставлены в таблицу test_sql_list (sql_text text NOT NULL) в поле sql_text. Вместо переменной SCHEMA подставь instruction. Запросы должны начинаться с select, update, delete, insert, alter. Переменные подстановки должны начинаться с “:”. Запросы должны быть готовы к исполнения в oracle.

<Ваш php код>

 В итоге получали готовый для вставки в таблицу SQL. Результат был отличный.

INSERT INTO test_sql_list (sql_text) VALUES
(
'SELECT filials.FILIAL, departs.FULL_OEBS_PATH, CASE WHEN INSTR(departs.FULL_OEBS_PATH, '' |'') > 0 THEN SUBSTR(departs.FULL_OEBS_PATH, 1, INSTR(departs.FULL_OEBS_PATH, '' |'') - 1) ELSE departs.FULL_OEBS_PATH END AS DEPARTS_OEBS FROM instruction.departs LEFT JOIN instruction.filials ON departs.FILIAL = filials.ID_ WHERE (departs.FULL_OEBS_PATH LIKE :path OR departs.FULL_OEBS_PATH LIKE ''%'' || REPLACE(REPLACE(:path, ''«'', '''' ), ''»'', '''' )) and ROWNUM = 1 '
),
......
Объяснить код с
6.       Загрузка данных таблиц.

Остался последний шаг – выгрузка данных из базы Oracle и загрузка в Postgres.

Данные выгружаем из Oracle утилитой ora2pg:

>ora2pg -t INSERT -o data.sql -b /mig/ora2pg -c config/ora2pg.conf --no_start_scn
Объяснить код с
Утилита создает скрипты (с командами insert) для загрузки. Для каждой таблицы создается отдельный файл. Загрузка выполняется из стандартной psql. Загрузку можно выполнить в несколько потоков., распределив файлы. Также стоит разбить на разные транзакции. Перед загрузкой лучше удалить внешние ключи и индексы.
