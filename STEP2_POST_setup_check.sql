spool STEP2_POST_setup_check.log

SET LINES 300
SET PAGES 1000
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WORD_WRAPPED

DECLARE
    v_spfile                  VARCHAR2(512);
    v_log_mode                VARCHAR2(20);
    v_flashback               VARCHAR2(20);
    v_force_logging           VARCHAR2(20);
    v_dg_broker               VARCHAR2(10);
    v_dg_cfg1                 VARCHAR2(512);
    v_dg_cfg2                 VARCHAR2(512);
    v_stby_file_mgmt          VARCHAR2(20);
    v_log_archive_config      VARCHAR2(2000);
    v_log_archive_dest1       VARCHAR2(4000);
    v_log_archive_dest2       VARCHAR2(4000);
    v_log_archive_dest_state2 VARCHAR2(50);
    v_remote_pwdfile          VARCHAR2(50);
    v_fal_server              VARCHAR2(512);
    v_fal_client              VARCHAR2(512);
    v_db_create_dest          VARCHAR2(512);
    v_recovery_dest           VARCHAR2(512);
    v_recovery_size           VARCHAR2(50);
    v_is_cdb                  VARCHAR2(3);
    v_db_name                 VARCHAR2(30);
    v_db_unique               VARCHAR2(30);
    v_db_role                 VARCHAR2(30);
    v_instance                VARCHAR2(30);
    v_host                    VARCHAR2(64);
    v_version_full            VARCHAR2(100);

    v_status                  VARCHAR2(10);
    v_fail_count              NUMBER := 0;

    ------------------------------------------------------------------
    PROCEDURE print_line(p_name   VARCHAR2,
                         p_value  VARCHAR2,
                         p_status VARCHAR2) IS
        v_label_width CONSTANT NUMBER := 35;
        v_status_col  CONSTANT NUMBER := 115;
        v_line        VARCHAR2(4000);
    BEGIN
        v_line := RPAD(p_name, v_label_width) || ' : ' || NVL(p_value,'NOT SET');

        IF LENGTH(v_line) < v_status_col THEN
            v_line := RPAD(v_line, v_status_col);
        ELSE
            v_line := v_line || '  ';
        END IF;

        v_line := v_line || 'Status: ' || p_status;

        DBMS_OUTPUT.PUT_LINE(v_line);

        IF p_status = 'FAIL' THEN
            v_fail_count := v_fail_count + 1;
        END IF;
    END;
    ------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('===== DATABASE CONFIGURATION POSTCHECK =====');
    DBMS_OUTPUT.PUT_LINE('');

    SELECT name, db_unique_name, cdb, database_role, force_logging
    INTO   v_db_name, v_db_unique, v_is_cdb, v_db_role, v_force_logging
    FROM   v$database;

    SELECT instance_name, host_name, version_full
    INTO   v_instance, v_host, v_version_full
    FROM   v$instance;

    print_line('Host Name', v_host, 'OK');
    print_line('Instance Name', v_instance, 'OK');
    print_line('Oracle Version (Full)', v_version_full, 'OK');
    print_line('Database Name', v_db_name, 'OK');
    print_line('DB Unique Name', v_db_unique, 'OK');

    -- Role must be PRIMARY or PHYSICAL STANDBY
    IF v_db_role IN ('PRIMARY','PHYSICAL STANDBY') THEN
        v_status := 'PASS';
    ELSE
        v_status := 'FAIL';
    END IF;
    print_line('Database Role', v_db_role, v_status);

    -- CDB required
    IF v_is_cdb = 'YES' THEN v_status := 'PASS'; ELSE v_status := 'FAIL'; END IF;
    print_line('Database Type (CDB Required)', v_is_cdb, v_status);

    -- Force logging
    IF v_force_logging = 'YES' THEN v_status := 'PASS'; ELSE v_status := 'FAIL'; END IF;
    print_line('FORCE LOGGING', v_force_logging, v_status);

    -- SPFILE
    SELECT value INTO v_spfile FROM v$parameter WHERE name='spfile';
    IF v_spfile IS NOT NULL THEN v_status := 'PASS'; ELSE v_status := 'FAIL'; END IF;
    print_line('SPFILE In Use', v_spfile, v_status);

    -- Archivelog
    SELECT log_mode INTO v_log_mode FROM v$database;
    IF v_log_mode = 'ARCHIVELOG' THEN v_status := 'PASS'; ELSE v_status := 'FAIL'; END IF;
    print_line('ARCHIVELOG Mode', v_log_mode, v_status);

    -- Flashback
    SELECT flashback_on INTO v_flashback FROM v$database;
    IF v_flashback = 'YES' THEN v_status := 'PASS'; ELSE v_status := 'FAIL'; END IF;
    print_line('FLASHBACK', v_flashback, v_status);

    -- Archive config
    SELECT value INTO v_log_archive_config FROM v$parameter WHERE name='log_archive_config';
    print_line('LOG_ARCHIVE_CONFIG', v_log_archive_config, 'OK');

    SELECT value INTO v_log_archive_dest1 FROM v$parameter WHERE name='log_archive_dest_1';
    print_line('LOG_ARCHIVE_DEST_1', v_log_archive_dest1, 'OK');

    SELECT value INTO v_log_archive_dest2 FROM v$parameter WHERE name='log_archive_dest_2';
    IF v_db_role = 'PRIMARY' AND v_log_archive_dest2 IS NULL THEN
        v_status := 'FAIL';
    ELSE
        v_status := 'OK';
    END IF;
    print_line('LOG_ARCHIVE_DEST_2', v_log_archive_dest2, v_status);

    SELECT value INTO v_log_archive_dest_state2 FROM v$parameter WHERE name='log_archive_dest_state_2';
    IF v_db_role = 'PRIMARY' AND v_log_archive_dest_state2 <> 'ENABLE' THEN
        v_status := 'FAIL';
    ELSE
        v_status := 'OK';
    END IF;
    print_line('LOG_ARCHIVE_DEST_STATE_2', v_log_archive_dest_state2, v_status);

    -- DG Broker
    SELECT value INTO v_dg_broker FROM v$parameter WHERE name='dg_broker_start';
    IF v_dg_broker = 'TRUE' THEN v_status := 'PASS'; ELSE v_status := 'FAIL'; END IF;
    print_line('DG_BROKER_START', v_dg_broker, v_status);

    SELECT value INTO v_dg_cfg1 FROM v$parameter WHERE name='dg_broker_config_file1';
    SELECT value INTO v_dg_cfg2 FROM v$parameter WHERE name='dg_broker_config_file2';
    print_line('DG_BROKER_CONFIG_FILE1', v_dg_cfg1, 'OK');
    print_line('DG_BROKER_CONFIG_FILE2', v_dg_cfg2, 'OK');

    -- Standby file mgmt
    SELECT value INTO v_stby_file_mgmt FROM v$parameter WHERE name='standby_file_management';
    IF v_stby_file_mgmt = 'AUTO' THEN v_status := 'PASS'; ELSE v_status := 'FAIL'; END IF;
    print_line('STANDBY_FILE_MANAGEMENT', v_stby_file_mgmt, v_status);

    -- FAL (required on standby)
    SELECT value INTO v_fal_server FROM v$parameter WHERE name='fal_server';
    IF v_db_role='PHYSICAL STANDBY' AND v_fal_server IS NULL THEN
        v_status := 'FAIL';
    ELSE
        v_status := 'OK';
    END IF;
    print_line('FAL_SERVER', v_fal_server, v_status);

    SELECT value INTO v_fal_client FROM v$parameter WHERE name='fal_client';
    print_line('FAL_CLIENT', v_fal_client, 'OK');

    -- Password file
    SELECT value INTO v_remote_pwdfile FROM v$parameter WHERE name='remote_login_passwordfile';
    IF v_remote_pwdfile='EXCLUSIVE' THEN v_status:='PASS'; ELSE v_status:='FAIL'; END IF;
    print_line('REMOTE_LOGIN_PASSWORDFILE', v_remote_pwdfile, v_status);

    -- FRA / OMF
    SELECT value INTO v_recovery_dest FROM v$parameter WHERE name='db_recovery_file_dest';
    SELECT value INTO v_recovery_size FROM v$parameter WHERE name='db_recovery_file_dest_size';
    SELECT value INTO v_db_create_dest FROM v$parameter WHERE name='db_create_file_dest';

    print_line('DB_RECOVERY_FILE_DEST', v_recovery_dest, 'OK');
    print_line('DB_RECOVERY_FILE_DEST_SIZE', v_recovery_size, 'OK');
    print_line('DB_CREATE_FILE_DEST', v_db_create_dest, 'OK');

    -- PDB Info
    IF v_is_cdb='YES' THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('----- PDBs -----');
        FOR r IN (SELECT name, open_mode FROM v$pdbs WHERE name<>'PDB$SEED') LOOP
            print_line('PDB '||r.name, r.open_mode, 'OK');
        END LOOP;
    END IF;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('==============================================');

    IF v_fail_count=0 THEN
        DBMS_OUTPUT.PUT_LINE('OVERALL RESULT : PASS');
    ELSE
        DBMS_OUTPUT.PUT_LINE('OVERALL RESULT : FAIL ('||v_fail_count||' checks failed)');
    END IF;

END;
/

SET SERVEROUTPUT OFF
spool off
exit
