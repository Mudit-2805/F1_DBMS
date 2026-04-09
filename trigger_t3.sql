-- ═══════════════════════════════════════════════════════════════════
-- Grand Prix Hub — Trigger T3
-- Prevents a driver from being signed to a second team while
-- they already hold an active contract.
-- Run in MySQL Workbench after schema_update.sql
-- ═══════════════════════════════════════════════════════════════════

USE grand_prix_hub;

DROP TRIGGER IF EXISTS trg_no_duplicate_contract;

DELIMITER //

CREATE TRIGGER trg_no_duplicate_contract
BEFORE INSERT ON DRIVER_CONTRACT
FOR EACH ROW
BEGIN
  DECLARE v_count INT DEFAULT 0;
  SELECT COUNT(*) INTO v_count
    FROM DRIVER_CONTRACT
   WHERE DriverID = NEW.DriverID;

  IF v_count > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'T3 BLOCKED: Driver already has an active contract — release them first before reassigning.';
  END IF;
END //

DELIMITER ;

-- Verify it was created
SELECT TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_TIMING
  FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA = 'grand_prix_hub';
