-- ═══════════════════════════════════════════════════════════════════
--  Grand Prix Hub — Schema Update (MySQL 8.0 compatible)
--  Run in MySQL Workbench AFTER schema.sql
--  Select grand_prix_hub schema, then Execute All (Ctrl+Shift+Enter)
-- ═══════════════════════════════════════════════════════════════════

USE grand_prix_hub;

-- ── Disable safe update mode for this session ──────────────────────
SET SQL_SAFE_UPDATES = 0;

-- ── Helper procedure: safely adds a column only if it doesn't exist ─
DROP PROCEDURE IF EXISTS add_col;
DELIMITER //
CREATE PROCEDURE add_col(
    IN p_table  VARCHAR(64),
    IN p_col    VARCHAR(64),
    IN p_def    VARCHAR(200)
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = p_table
          AND COLUMN_NAME  = p_col
    ) THEN
        SET @sql = CONCAT('ALTER TABLE `', p_table, '` ADD COLUMN `', p_col, '` ', p_def);
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END //
DELIMITER ;

-- ── TEAM: add emoji and color columns ─────────────────────────────
CALL add_col('TEAM', 'emoji', "VARCHAR(8) DEFAULT '🏎️'");
CALL add_col('TEAM', 'color', "VARCHAR(16) DEFAULT '#666666'");

-- ── RACE_WEEKEND: add name, circuit, flag columns ─────────────────
CALL add_col('RACE_WEEKEND', 'name',    "VARCHAR(100) DEFAULT 'Grand Prix'");
CALL add_col('RACE_WEEKEND', 'circuit', "VARCHAR(200) DEFAULT 'TBC'");
CALL add_col('RACE_WEEKEND', 'flag',    "VARCHAR(8) DEFAULT '🏁'");

-- ── DRIVER: add flag column ────────────────────────────────────────
CALL add_col('DRIVER', 'flag', "VARCHAR(8) DEFAULT '🏁'");

DROP PROCEDURE IF EXISTS add_col;

-- ═══════════════════════════════════════════════════════════════════
--  Seed emoji / color for existing teams
-- ═══════════════════════════════════════════════════════════════════

UPDATE TEAM SET emoji = '🔴', color = '#E8002D' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE TeamName LIKE '%Ferrari%') t);
UPDATE TEAM SET emoji = '🔵', color = '#3671C6' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE TeamName LIKE '%Red Bull%') t);
UPDATE TEAM SET emoji = '🟠', color = '#FF8000' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE TeamName LIKE '%McLaren%') t);
UPDATE TEAM SET emoji = '🩵', color = '#27F4D2' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE TeamName LIKE '%Mercedes%') t);
UPDATE TEAM SET emoji = '🟢', color = '#00A19C' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE TeamName LIKE '%Aston%') t);
UPDATE TEAM SET emoji = '🩷', color = '#FF69B4' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE TeamName LIKE '%Alpine%') t);
UPDATE TEAM SET emoji = '⚪', color = '#64C4FF' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE TeamName LIKE '%Williams%') t);
UPDATE TEAM SET emoji = '⚪', color = '#B6BABD' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE TeamName LIKE '%Haas%') t);
UPDATE TEAM SET emoji = '🏎️', color = '#666666' WHERE TeamID IN (SELECT TeamID FROM (SELECT TeamID FROM TEAM WHERE emoji IS NULL OR emoji = '') t);

-- ═══════════════════════════════════════════════════════════════════
--  Seed flag emojis for drivers
-- ═══════════════════════════════════════════════════════════════════

UPDATE DRIVER SET flag = '🇳🇱' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Verstappen') d);
UPDATE DRIVER SET flag = '🇬🇧' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Hamilton') d);
UPDATE DRIVER SET flag = '🇬🇧' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Russell') d);
UPDATE DRIVER SET flag = '🇲🇨' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Leclerc') d);
UPDATE DRIVER SET flag = '🇪🇸' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Sainz') d);
UPDATE DRIVER SET flag = '🇬🇧' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Norris') d);
UPDATE DRIVER SET flag = '🇦🇺' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Piastri') d);
UPDATE DRIVER SET flag = '🇪🇸' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Alonso') d);
UPDATE DRIVER SET flag = '🇨🇦' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Stroll') d);
UPDATE DRIVER SET flag = '🇫🇷' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Ocon') d);
UPDATE DRIVER SET flag = '🇫🇷' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Gasly') d);
UPDATE DRIVER SET flag = '🇹🇭' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Albon') d);
UPDATE DRIVER SET flag = '🇩🇰' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Magnussen') d);
UPDATE DRIVER SET flag = '🇩🇪' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Hulkenberg') d);
UPDATE DRIVER SET flag = '🇯🇵' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Tsunoda') d);
UPDATE DRIVER SET flag = '🇫🇮' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Bottas') d);
UPDATE DRIVER SET flag = '🇨🇳' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Zhou') d);
UPDATE DRIVER SET flag = '🇲🇽' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE LastName = 'Perez') d);
-- Fallback: any driver still without a flag
UPDATE DRIVER SET flag = '🏁' WHERE DriverID IN (SELECT DriverID FROM (SELECT DriverID FROM DRIVER WHERE flag IS NULL OR flag = '') d);

-- ═══════════════════════════════════════════════════════════════════
--  Seed flag emojis for race weekends
-- ═══════════════════════════════════════════════════════════════════

UPDATE RACE_WEEKEND SET flag = '🇦🇺' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Australian%') w);
UPDATE RACE_WEEKEND SET flag = '🇯🇵' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Japanese%') w);
UPDATE RACE_WEEKEND SET flag = '🇧🇭' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Bahrain%') w);
UPDATE RACE_WEEKEND SET flag = '🇸🇦' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Saudi%') w);
UPDATE RACE_WEEKEND SET flag = '🇺🇸' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Miami%' OR name LIKE '%United States%' OR name LIKE '%Las Vegas%') w);
UPDATE RACE_WEEKEND SET flag = '🇮🇹' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Italian%' OR name LIKE '%Emilia%') w);
UPDATE RACE_WEEKEND SET flag = '🇲🇨' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Monaco%') w);
UPDATE RACE_WEEKEND SET flag = '🇨🇦' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Canadian%') w);
UPDATE RACE_WEEKEND SET flag = '🇪🇸' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Spanish%') w);
UPDATE RACE_WEEKEND SET flag = '🇦🇹' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Austrian%') w);
UPDATE RACE_WEEKEND SET flag = '🇬🇧' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%British%') w);
UPDATE RACE_WEEKEND SET flag = '🇭🇺' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Hungarian%') w);
UPDATE RACE_WEEKEND SET flag = '🇧🇪' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Belgian%') w);
UPDATE RACE_WEEKEND SET flag = '🇳🇱' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Dutch%') w);
UPDATE RACE_WEEKEND SET flag = '🇦🇿' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Azerbaijan%') w);
UPDATE RACE_WEEKEND SET flag = '🇸🇬' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Singapore%') w);
UPDATE RACE_WEEKEND SET flag = '🇲🇽' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Mexican%') w);
UPDATE RACE_WEEKEND SET flag = '🇧🇷' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Brazilian%') w);
UPDATE RACE_WEEKEND SET flag = '🇦🇪' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE name LIKE '%Abu Dhabi%') w);
-- Fallback
UPDATE RACE_WEEKEND SET flag = '🏁' WHERE WeekendID IN (SELECT WeekendID FROM (SELECT WeekendID FROM RACE_WEEKEND WHERE flag IS NULL OR flag = '') w);

-- ═══════════════════════════════════════════════════════════════════
--  TRANSACTION_LOG  (Task 6)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS TRANSACTION_LOG (
  LogID       INT          NOT NULL AUTO_INCREMENT,
  TxnType     VARCHAR(40)  NOT NULL,
  Status      ENUM('committed','rolled_back','error') NOT NULL,
  StepsJSON   JSON         DEFAULT NULL,
  ExecutedBy  VARCHAR(40)  DEFAULT 'admin',
  ExecutedAt  DATETIME     DEFAULT CURRENT_TIMESTAMP,
  Notes       TEXT         DEFAULT NULL,
  PRIMARY KEY (LogID),
  INDEX idx_type   (TxnType),
  INDEX idx_status (Status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════════════
--  USER_SESSION
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS USER_SESSION (
  SessionToken VARCHAR(64) NOT NULL,
  Role         VARCHAR(20) NOT NULL,
  Username     VARCHAR(40) NOT NULL,
  CreatedAt    DATETIME    DEFAULT CURRENT_TIMESTAMP,
  ExpiresAt    DATETIME    DEFAULT NULL,
  PRIMARY KEY (SessionToken),
  INDEX idx_role (Role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Drop triggers (Admin page re-creates them when toggled ON) ─────
DROP TRIGGER IF EXISTS trg_no_duplicate_driver_number;
DROP TRIGGER IF EXISTS trg_auto_contract_end_date;

-- ── Re-enable safe update mode ─────────────────────────────────────
SET SQL_SAFE_UPDATES = 1;

-- ═══════════════════════════════════════════════════════════════════
--  Verify — all tables + row counts
-- ═══════════════════════════════════════════════════════════════════

SELECT COUNT(*) AS teams         FROM `TEAM`;
SELECT COUNT(*) AS drivers       FROM `DRIVER`;
SELECT COUNT(*) AS contracts     FROM `DRIVER_CONTRACT`;
SELECT COUNT(*) AS cars          FROM `CAR`;
SELECT COUNT(*) AS race_weekends FROM `RACE_WEEKEND`;
SELECT COUNT(*) AS sessions      FROM `SESSION`;
SELECT COUNT(*) AS lap_times     FROM `LAP_TIME`;
SELECT COUNT(*) AS pit_stops     FROM `PIT_STOP`;
SELECT COUNT(*) AS incidents     FROM `INCIDENT`;
SELECT COUNT(*) AS penalties     FROM `PENALTY`;
SELECT COUNT(*) AS txn_log       FROM `TRANSACTION_LOG`;
SELECT COUNT(*) AS user_sessions FROM `USER_SESSION`;
