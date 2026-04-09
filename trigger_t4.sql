-- ═══════════════════════════════════════════════════════════════════
-- Grand Prix Hub — Trigger T4
-- Protects active contracts from being modified.
-- EndDate >= CURDATE() = active = locked from updates.
-- Run in MySQL Workbench after trigger_t3.sql
-- ═══════════════════════════════════════════════════════════════════

USE grand_prix_hub;

DROP TRIGGER IF EXISTS trg_protect_active_contract;

DELIMITER //

CREATE TRIGGER trg_protect_active_contract
BEFORE UPDATE ON DRIVER_CONTRACT
FOR EACH ROW
BEGIN
  IF OLD.EndDate >= CURDATE() THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'T4 BLOCKED: Contract is currently active and cannot be modified. Wait until the contract expires or remove it first.';
  END IF;
END //

DELIMITER ;

-- ── Useful queries to verify contract status ──────────────────────

-- See all contracts with active/expired status
SELECT dc.ContractID,
       d.FirstName, d.LastName, d.DriverNumber,
       t.TeamName,
       dc.StartDate, dc.EndDate,
       CASE
         WHEN dc.EndDate >= CURDATE() THEN CONCAT('🟢 ACTIVE (', DATEDIFF(dc.EndDate, CURDATE()), ' days remaining)')
         ELSE CONCAT('🔴 EXPIRED (', ABS(DATEDIFF(dc.EndDate, CURDATE())), ' days ago)')
       END AS contract_status
FROM DRIVER_CONTRACT dc
JOIN DRIVER d ON d.DriverID = dc.DriverID
JOIN TEAM   t ON t.TeamID   = dc.TeamID
ORDER BY dc.DriverID;

-- Verify T4 exists
SELECT TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_TIMING
  FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA = 'grand_prix_hub'
 ORDER BY TRIGGER_NAME;
