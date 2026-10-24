-- =====================================================
-- Passport Tracking System - Database v3 (XAMPP: MySQL/MariaDB)
-- FRESH INSTALL: phpMyAdmin > Import > choose this file > Go
-- WARNING: this DROPS and recreates passport_tracking_db.
-- Already imported v2 and want to KEEP your data? Use upgrade_to_v3.sql instead.
-- Still compatible with your existing api.php (no code change needed).
-- =====================================================
DROP DATABASE IF EXISTS passport_tracking_db;
CREATE DATABASE passport_tracking_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
USE passport_tracking_db;

-- -----------------------------------------------------
-- 1. USERS (members and admin accounts)
-- -----------------------------------------------------
CREATE TABLE users (
  user_id       VARCHAR(20)  NOT NULL,            -- MEMBER, ADMIN, MEM-002
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('member','admin') NOT NULL DEFAULT 'member',
  full_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(100) NOT NULL,
  is_active     TINYINT(1)   NOT NULL DEFAULT 1,  -- NEW: disable an account without deleting it
  last_login    DATETIME     DEFAULT NULL,        -- NEW
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_users_email (email),
  KEY idx_users_role (role),
  CONSTRAINT ck_users_email  CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT ck_users_active CHECK (is_active IN (0,1))
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 2. OFFICES
-- -----------------------------------------------------
CREATE TABLE offices (
  office_id   INT          NOT NULL AUTO_INCREMENT,
  office_name VARCHAR(100) NOT NULL,
  address     VARCHAR(200) DEFAULT NULL,          -- NEW
  is_active   TINYINT(1)   NOT NULL DEFAULT 1,    -- NEW: hide an office from the dropdown
  PRIMARY KEY (office_id),
  UNIQUE KEY uq_office_name (office_name),
  CONSTRAINT ck_office_active CHECK (is_active IN (0,1))
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 3. STAGES (the 6 tracking stages)
-- -----------------------------------------------------
CREATE TABLE stages (
  stage_no    TINYINT      NOT NULL,              -- 0 to 5
  stage_name  VARCHAR(50)  NOT NULL,
  description VARCHAR(255) NOT NULL,
  duration    VARCHAR(50)  NOT NULL,
  PRIMARY KEY (stage_no),
  UNIQUE KEY uq_stage_name (stage_name),
  CONSTRAINT ck_stage_range CHECK (stage_no BETWEEN 0 AND 5)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 4. APPLICATIONS (main table)
-- -----------------------------------------------------
CREATE TABLE applications (
  ref_no          VARCHAR(20)  NOT NULL,          -- PPT-2026-000125
  tracking_no     VARCHAR(20)  NOT NULL,          -- TRK-7F3K29
  user_id         VARCHAR(20)  NOT NULL,
  first_name      VARCHAR(50)  NOT NULL,
  last_name       VARCHAR(50)  NOT NULL,
  date_of_birth   DATE         NOT NULL,
  sex             ENUM('Female','Male','Other') DEFAULT NULL,
  place_of_birth  VARCHAR(100) DEFAULT NULL,
  civil_status    ENUM('Single','Married','Widowed','Separated') DEFAULT 'Single',
  email           VARCHAR(100) DEFAULT NULL,
  mobile_no       VARCHAR(20)  DEFAULT NULL,
  home_address    TEXT,
  app_type        ENUM('New Passport','Passport Renewal','Replacement') NOT NULL DEFAULT 'New Passport',
  speed           ENUM('Regular','Express') NOT NULL DEFAULT 'Regular',
  fee             DECIMAL(8,2) NOT NULL,
  is_paid         TINYINT(1)   NOT NULL DEFAULT 0,
  receipt_no      VARCHAR(20)  DEFAULT NULL,
  office_id       INT          NOT NULL,
  appointment_at  DATETIME     DEFAULT NULL,
  submitted_date  DATE         NOT NULL,
  est_release     DATE         DEFAULT NULL,
  current_stage   TINYINT      NOT NULL DEFAULT 0,
  is_rejected     TINYINT(1)   NOT NULL DEFAULT 0,
  reject_reason   VARCHAR(255) DEFAULT NULL,
  updated_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, -- NEW
  PRIMARY KEY (ref_no),
  UNIQUE KEY uq_tracking_no (tracking_no),
  UNIQUE KEY uq_receipt_no (receipt_no),                        -- NEW (NULLs are allowed many times)
  KEY idx_app_user      (user_id, submitted_date),              -- NEW: "my applications" list
  KEY idx_app_lastname  (last_name),                            -- NEW: public tracking search
  KEY idx_app_status    (current_stage, is_rejected),           -- NEW: admin filtering / counts
  KEY idx_app_submitted (submitted_date),                       -- NEW
  CONSTRAINT fk_app_user   FOREIGN KEY (user_id)       REFERENCES users(user_id)    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_app_office FOREIGN KEY (office_id)     REFERENCES offices(office_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_app_stage  FOREIGN KEY (current_stage) REFERENCES stages(stage_no)  ON UPDATE CASCADE ON DELETE RESTRICT,
  -- NEW data-integrity rules
  CONSTRAINT ck_app_ref      CHECK (ref_no REGEXP '^PPT-[0-9]{4}-[0-9]{6}$'),
  CONSTRAINT ck_app_track    CHECK (tracking_no REGEXP '^TRK-[A-Z0-9]{6}$'),
  CONSTRAINT ck_app_fee      CHECK (fee >= 0),
  CONSTRAINT ck_app_paid     CHECK (is_paid IN (0,1)),
  CONSTRAINT ck_app_rejected CHECK (is_rejected IN (0,1)),
  CONSTRAINT ck_app_reason   CHECK (is_rejected = 0 OR reject_reason IS NOT NULL),
  CONSTRAINT ck_app_release  CHECK (est_release IS NULL OR est_release >= submitted_date)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 5. APPLICATION_DOCUMENTS (document checklist)
-- -----------------------------------------------------
CREATE TABLE application_documents (
  doc_id      INT          NOT NULL AUTO_INCREMENT,
  ref_no      VARCHAR(20)  NOT NULL,
  doc_name    VARCHAR(60)  NOT NULL,
  is_received TINYINT(1)   NOT NULL DEFAULT 0,
  PRIMARY KEY (doc_id),
  UNIQUE KEY uq_doc_per_app (ref_no, doc_name),                 -- NEW: no duplicate checklist items
  CONSTRAINT fk_doc_app FOREIGN KEY (ref_no) REFERENCES applications(ref_no)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_doc_received CHECK (is_received IN (0,1))
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 6. APPLICATION_LOGS (activity history)
-- -----------------------------------------------------
CREATE TABLE application_logs (
  log_id     INT          NOT NULL AUTO_INCREMENT,
  ref_no     VARCHAR(20)  NOT NULL,
  log_date   DATE         NOT NULL,
  activity   VARCHAR(255) NOT NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- NEW: exact time of the event
  PRIMARY KEY (log_id),
  KEY idx_log_app (ref_no, log_id),                             -- NEW: fast history per application
  CONSTRAINT fk_log_app FOREIGN KEY (ref_no) REFERENCES applications(ref_no)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 7. RENEWALS
-- -----------------------------------------------------
CREATE TABLE renewals (
  ref_no          VARCHAR(20)  NOT NULL,          -- REN-2026-0007
  user_id         VARCHAR(20)  NOT NULL,
  passport_no     VARCHAR(20)  NOT NULL,
  expiry_date     DATE         DEFAULT NULL,
  reason          ENUM('Expiring soon','Pages full','Change of name') NOT NULL,
  speed           ENUM('Regular','Express') NOT NULL DEFAULT 'Regular',
  notes           TEXT,
  status          ENUM('Pending','Approved','Rejected') NOT NULL DEFAULT 'Pending',
  requested_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decided_at      DATETIME     DEFAULT NULL,      -- NEW: when the admin approved/rejected
  decided_by      VARCHAR(20)  DEFAULT NULL,      -- NEW: which admin
  PRIMARY KEY (ref_no),
  KEY idx_ren_status (status, requested_at),                    -- NEW
  KEY idx_ren_passport (passport_no),                           -- NEW
  CONSTRAINT fk_ren_user    FOREIGN KEY (user_id)    REFERENCES users(user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_ren_decider FOREIGN KEY (decided_by) REFERENCES users(user_id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT ck_ren_ref CHECK (ref_no REGEXP '^REN-[0-9]{4}-[0-9]{4}$')
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 8. ENQUIRIES (messages to the passport office)
-- -----------------------------------------------------
CREATE TABLE enquiries (
  ref_no     VARCHAR(20)  NOT NULL,               -- CMP-001
  user_id    VARCHAR(20)  NOT NULL,
  subject    VARCHAR(150) NOT NULL,
  category   ENUM('Application','Renewal','Payment','Appointment','Other') NOT NULL DEFAULT 'Other',
  message    TEXT         NOT NULL,
  reply      TEXT,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  replied_at DATETIME     DEFAULT NULL,           -- NEW
  replied_by VARCHAR(20)  DEFAULT NULL,           -- NEW
  PRIMARY KEY (ref_no),
  KEY idx_enq_category (category),                              -- NEW
  KEY idx_enq_created  (created_at),                            -- NEW
  CONSTRAINT fk_enq_user    FOREIGN KEY (user_id)    REFERENCES users(user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_enq_replier FOREIGN KEY (replied_by) REFERENCES users(user_id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT ck_enq_ref CHECK (ref_no REGEXP '^CMP-[0-9]{3,}$')
) ENGINE=InnoDB;


-- =====================================================
-- VIEWS (ready-made reports - great for your defense)
-- =====================================================

-- Public tracking page: one row per application with its stage details
CREATE VIEW v_application_tracking AS
SELECT a.ref_no, a.tracking_no, a.user_id,
       CONCAT(a.first_name, ' ', a.last_name) AS applicant,
       a.last_name, a.app_type, a.speed, a.fee, a.is_paid,
       o.office_name, a.appointment_at, a.submitted_date, a.est_release,
       a.current_stage, s.stage_name, s.duration AS stage_duration,
       a.is_rejected, a.reject_reason,
       CASE WHEN a.is_rejected = 1 THEN 'Rejected'
            WHEN a.current_stage = 5 THEN 'Ready for Release'
            ELSE 'In Progress' END AS overall_status
FROM applications a
JOIN offices o ON o.office_id = a.office_id
JOIN stages  s ON s.stage_no  = a.current_stage;

-- Admin dashboard: counts per stage (including stages with zero applications)
CREATE VIEW v_stage_summary AS
SELECT s.stage_no, s.stage_name,
       COUNT(a.ref_no) AS total_applications
FROM stages s
LEFT JOIN applications a ON a.current_stage = s.stage_no AND a.is_rejected = 0
GROUP BY s.stage_no, s.stage_name;

-- Admin dashboard: one row per member with their activity
CREATE VIEW v_member_summary AS
SELECT u.user_id, u.full_name, u.email, u.created_at,
       (SELECT COUNT(*) FROM applications a WHERE a.user_id = u.user_id) AS applications,
       (SELECT COUNT(*) FROM renewals     r WHERE r.user_id = u.user_id) AS renewals,
       (SELECT COUNT(*) FROM enquiries    e WHERE e.user_id = u.user_id) AS enquiries
FROM users u
WHERE u.role = 'member';

-- Applications that still miss at least one document
CREATE VIEW v_missing_documents AS
SELECT a.ref_no, CONCAT(a.first_name, ' ', a.last_name) AS applicant, d.doc_name
FROM applications a
JOIN application_documents d ON d.ref_no = a.ref_no
WHERE d.is_received = 0 AND a.is_rejected = 0;

-- Enquiries waiting for an admin reply
CREATE VIEW v_unanswered_enquiries AS
SELECT e.ref_no, e.user_id, u.full_name, e.category, e.subject, e.created_at
FROM enquiries e
JOIN users u ON u.user_id = e.user_id
WHERE e.reply IS NULL OR e.reply = '';


-- =====================================================
-- SAMPLE DATA
-- Login passwords: MEMBER = 1234 | ADMIN = admin123 | MEM-002 = 1234
-- (SHA-256 for the samples; api.php already accepts these AND password_hash())
-- =====================================================

INSERT INTO users (user_id, password_hash, role, full_name, email) VALUES
('MEMBER',  SHA2('1234',256),     'member', 'Alex Morgan',   'member@example.com'),
('ADMIN',   SHA2('admin123',256), 'admin',  'Administrator', 'admin@pts.example'),
('MEM-002', SHA2('1234',256),     'member', 'Jamie Rivera',  'jamie@example.com');

INSERT INTO offices (office_name, address) VALUES
('DFA NCR Central Passport Office', 'Sample address, Metro Manila'),
('DFA Aseana',                      'Sample address, Parañaque City'),
('Pasay City Office',               'Sample address, Pasay City');

INSERT INTO stages (stage_no, stage_name, description, duration) VALUES
(0, 'Application Submitted',   'Your online form and payment details are recorded.',                  'Same day'),
(1, 'Documents Verified',      'Officers check your documents against civil registry records.',       '2-3 working days'),
(2, 'Biometrics & Interview',  'You visit the office for photo, fingerprints and a short interview.', 'On appointment date'),
(3, 'Adjudication',            'Eligibility is reviewed and approved by an adjudication officer.',    '3-5 working days'),
(4, 'Printing & Quality Check','Your passport is printed, inspected and sealed.',                     '5-7 working days'),
(5, 'Ready for Release',       'Collect at the office or receive by courier.',                        'On completion');

INSERT INTO applications
(ref_no, tracking_no, user_id, first_name, last_name, date_of_birth, sex, place_of_birth, civil_status,
 email, mobile_no, home_address, app_type, speed, fee, is_paid, receipt_no,
 office_id, appointment_at, submitted_date, est_release, current_stage, is_rejected, reject_reason) VALUES
('PPT-2026-000125','TRK-7F3K29','MEMBER','Alex','Morgan','1994-03-18','Male','Quezon City','Single',
 'member@example.com','09171234567','123 Sample St., Quezon City','New Passport','Regular',60.00,1,'R-88213',
 1,'2026-10-14 09:30:00','2026-09-24','2026-11-04',2,0,NULL),
('PPT-2026-000091','TRK-2B9QX1','MEMBER','Alex','Morgan','1994-03-18','Male','Quezon City','Single',
 'member@example.com','09171234567','123 Sample St., Quezon City','Passport Renewal','Express',95.00,1,'R-87102',
 2,'2026-08-22 14:00:00','2026-08-15','2026-09-02',5,0,NULL),
('PPT-2026-000054','TRK-9M4DD7','MEMBER','Alex','Morgan','1994-03-18','Male','Quezon City','Single',
 'member@example.com','09171234567','123 Sample St., Quezon City','New Passport','Regular',60.00,1,'R-85540',
 1,NULL,'2026-05-20',NULL,1,1,
 'The uploaded birth certificate was unreadable. Please submit a new application with a clear PSA copy. Your fee is credited.');

INSERT INTO application_documents (ref_no, doc_name, is_received) VALUES
('PPT-2026-000125','Birth certificate',1),('PPT-2026-000125','Government ID',1),
('PPT-2026-000125','Application form',1),('PPT-2026-000125','Appointment confirmation',1),
('PPT-2026-000091','Current passport',1),('PPT-2026-000091','Government ID',1),('PPT-2026-000091','Application form',1),
('PPT-2026-000054','Birth certificate',0),('PPT-2026-000054','Government ID',1),('PPT-2026-000054','Application form',1);

INSERT INTO application_logs (ref_no, log_date, activity) VALUES
('PPT-2026-000125','2026-09-24','Application submitted online'),
('PPT-2026-000125','2026-09-24','Payment received - Receipt R-88213'),
('PPT-2026-000125','2026-09-28','Documents verified by Officer L. Tan'),
('PPT-2026-000125','2026-10-02','Biometrics appointment scheduled for Oct 14, 2026'),
('PPT-2026-000091','2026-08-15','Application submitted online'),
('PPT-2026-000091','2026-08-22','Biometrics captured'),
('PPT-2026-000091','2026-08-29','Passport printed and sealed'),
('PPT-2026-000091','2026-09-02','Ready for release - Claim stub issued'),
('PPT-2026-000054','2026-05-20','Application submitted online'),
('PPT-2026-000054','2026-05-24','Application rejected - document unreadable');

INSERT INTO renewals (ref_no, user_id, passport_no, expiry_date, reason, speed, status) VALUES
('REN-2026-0007','MEMBER','P1234567','2027-02-10','Expiring soon','Regular','Pending');

INSERT INTO enquiries (ref_no, user_id, subject, category, message) VALUES
('CMP-001','MEMBER','Application inquiry','Application','Can I move my biometrics appointment to the afternoon?');



USE passport_tracking_db;
-- =====================================================
-- V3 ADDITIONS - NEW TABLES
-- =====================================================

-- Office extra info (MariaDB syntax - XAMPP uses MariaDB)
ALTER TABLE offices ADD COLUMN IF NOT EXISTS office_hours VARCHAR(60) NOT NULL DEFAULT 'Mon-Fri, 8:00 AM - 5:00 PM';

-- -----------------------------------------------------
-- 9. FEE_SCHEDULE (fees and processing times, same as the Fees table on your website)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS fee_schedule (
  service_code    VARCHAR(20)  NOT NULL,            -- NEW-REG, NEW-EXP, REN-REG ...
  service_name    VARCHAR(60)  NOT NULL,
  fee             DECIMAL(8,2) NOT NULL,
  processing_time VARCHAR(30)  NOT NULL,
  PRIMARY KEY (service_code),
  CONSTRAINT ck_fee_amount CHECK (fee >= 0)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 10. DOCUMENT_REQUIREMENTS (what must be submitted per application type)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS document_requirements (
  req_id    INT         NOT NULL AUTO_INCREMENT,
  app_type  ENUM('New Passport','Passport Renewal','Replacement') NOT NULL,
  doc_name  VARCHAR(60) NOT NULL,
  notes     VARCHAR(100) DEFAULT NULL,
  PRIMARY KEY (req_id),
  UNIQUE KEY uq_req (app_type, doc_name)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 11. PAYMENTS (one row per payment received; filled automatically by a trigger)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
  payment_id INT          NOT NULL AUTO_INCREMENT,
  ref_no     VARCHAR(20)  NOT NULL,
  receipt_no VARCHAR(20)  NOT NULL,
  amount     DECIMAL(8,2) NOT NULL,
  method     ENUM('Cashier','Online','Other') NOT NULL DEFAULT 'Cashier',
  paid_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (payment_id),
  UNIQUE KEY uq_pay_receipt (receipt_no),
  KEY idx_pay_ref (ref_no),
  KEY idx_pay_paid_at (paid_at),
  CONSTRAINT fk_pay_app FOREIGN KEY (ref_no) REFERENCES applications(ref_no)
    ON UPDATE CASCADE ON DELETE RESTRICT,            -- payment records cannot be deleted by accident
  CONSTRAINT ck_pay_amount CHECK (amount >= 0)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 12. COURIER_REQUESTS (optional courier delivery of the passport)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS courier_requests (
  ref_no           VARCHAR(20)  NOT NULL,           -- one request per application
  delivery_address TEXT         NOT NULL,
  courier_fee      DECIMAL(8,2) NOT NULL DEFAULT 12.00,
  status           ENUM('Requested','Dispatched','Delivered','Cancelled') NOT NULL DEFAULT 'Requested',
  requested_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  dispatched_at    DATETIME     DEFAULT NULL,
  delivered_at     DATETIME     DEFAULT NULL,
  PRIMARY KEY (ref_no),
  KEY idx_courier_status (status),
  CONSTRAINT fk_courier_app FOREIGN KEY (ref_no) REFERENCES applications(ref_no)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_courier_fee CHECK (courier_fee >= 0)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 13. NOTIFICATIONS (messages to members; filled automatically by triggers)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
  notif_id   INT          NOT NULL AUTO_INCREMENT,
  user_id    VARCHAR(20)  NOT NULL,
  ref_no     VARCHAR(20)  DEFAULT NULL,
  title      VARCHAR(100) NOT NULL,
  message    VARCHAR(255) NOT NULL,
  is_read    TINYINT(1)   NOT NULL DEFAULT 0,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (notif_id),
  KEY idx_notif_user (user_id, is_read, created_at),
  CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_notif_read CHECK (is_read IN (0,1))
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 14. PASSWORD_RESETS (for the "Forgot password?" feature)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS password_resets (
  reset_id   INT          NOT NULL AUTO_INCREMENT,
  user_id    VARCHAR(20)  NOT NULL,
  token_hash CHAR(64)     NOT NULL,                 -- store a hash of the token, never the token itself
  expires_at DATETIME     NOT NULL,
  used_at    DATETIME     DEFAULT NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (reset_id),
  UNIQUE KEY uq_reset_token (token_hash),
  KEY idx_reset_user (user_id),
  CONSTRAINT fk_reset_user FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;


-- =====================================================
-- V3 ADDITIONS - NEW VIEWS
-- =====================================================

-- Admin overview cards: one row with all the totals
CREATE OR REPLACE VIEW v_admin_dashboard AS
SELECT
  (SELECT COUNT(*) FROM applications)                                          AS total_applications,
  (SELECT COUNT(*) FROM applications WHERE is_rejected = 0 AND current_stage < 5)  AS in_progress,
  (SELECT COUNT(*) FROM applications WHERE is_rejected = 0 AND current_stage = 5)  AS ready_for_release,
  (SELECT COUNT(*) FROM applications WHERE is_rejected = 1)                    AS rejected,
  (SELECT COUNT(*) FROM applications WHERE is_paid = 0 AND is_rejected = 0)    AS unpaid,
  (SELECT COUNT(*) FROM renewals  WHERE status = 'Pending')                    AS pending_renewals,
  (SELECT COUNT(*) FROM enquiries WHERE reply IS NULL OR reply = '')           AS open_enquiries,
  (SELECT COUNT(*) FROM users WHERE role = 'member')                           AS members,
  (SELECT COALESCE(SUM(amount), 0) FROM payments)                              AS total_revenue;

-- Applications already past their estimated release date but not yet released
CREATE OR REPLACE VIEW v_overdue_applications AS
SELECT a.ref_no, CONCAT(a.first_name, ' ', a.last_name) AS applicant,
       s.stage_name, a.est_release,
       DATEDIFF(CURDATE(), a.est_release) AS days_overdue
FROM applications a
JOIN stages s ON s.stage_no = a.current_stage
WHERE a.is_rejected = 0 AND a.current_stage < 5
  AND a.est_release IS NOT NULL AND a.est_release < CURDATE();

-- Appointments that have not happened yet
CREATE OR REPLACE VIEW v_upcoming_appointments AS
SELECT a.ref_no, CONCAT(a.first_name, ' ', a.last_name) AS applicant,
       o.office_name, a.appointment_at
FROM applications a
JOIN offices o ON o.office_id = a.office_id
WHERE a.is_rejected = 0 AND a.appointment_at IS NOT NULL AND a.appointment_at >= NOW();

-- Money collected per month
CREATE OR REPLACE VIEW v_revenue_by_month AS
SELECT DATE_FORMAT(paid_at, '%Y-%m') AS month,
       COUNT(*)    AS payments,
       SUM(amount) AS total_collected
FROM payments
GROUP BY DATE_FORMAT(paid_at, '%Y-%m');

-- Latest activity across all applications (use ORDER BY log_id DESC LIMIT 10)
CREATE OR REPLACE VIEW v_recent_activity AS
SELECT l.log_id, l.log_date, l.ref_no,
       CONCAT(a.first_name, ' ', a.last_name) AS applicant, l.activity
FROM application_logs l
JOIN applications a ON a.ref_no = l.ref_no;

-- Unread notification count per member
CREATE OR REPLACE VIEW v_notification_counts AS
SELECT user_id, COUNT(*) AS unread
FROM notifications
WHERE is_read = 0
GROUP BY user_id;


-- =====================================================
-- V3 ADDITIONS - TRIGGERS (they run by themselves, api.php needs NO change)
--   * new application      -> notification to the member
--   * stage changes        -> notification to the member
--   * application rejected -> notification to the member
--   * application paid     -> row added to payments
--   * renewal decided      -> decided_at filled + notification
--   * enquiry answered     -> replied_at filled + notification
-- =====================================================
DELIMITER $$

DROP TRIGGER IF EXISTS trg_app_after_insert$$
CREATE TRIGGER trg_app_after_insert AFTER INSERT ON applications
FOR EACH ROW
BEGIN
  INSERT INTO notifications (user_id, ref_no, title, message)
  VALUES (NEW.user_id, NEW.ref_no, 'Application received',
          CONCAT('Your application ', NEW.ref_no, ' was submitted successfully.'));
END$$

DROP TRIGGER IF EXISTS trg_app_after_update$$
CREATE TRIGGER trg_app_after_update AFTER UPDATE ON applications
FOR EACH ROW
BEGIN
  DECLARE v_stage VARCHAR(50);

  IF NEW.current_stage <> OLD.current_stage THEN
    SELECT stage_name INTO v_stage FROM stages WHERE stage_no = NEW.current_stage;
    INSERT INTO notifications (user_id, ref_no, title, message)
    VALUES (NEW.user_id, NEW.ref_no, 'Application update',
            CONCAT('Application ', NEW.ref_no, ' is now at: ', v_stage, '.'));
  END IF;

  IF NEW.is_rejected = 1 AND OLD.is_rejected = 0 THEN
    INSERT INTO notifications (user_id, ref_no, title, message)
    VALUES (NEW.user_id, NEW.ref_no, 'Application rejected',
            CONCAT('Application ', NEW.ref_no, ' was rejected. Open it to see the reason.'));
  END IF;

  IF NEW.is_paid = 1 AND OLD.is_paid = 0 AND NEW.receipt_no IS NOT NULL THEN
    INSERT IGNORE INTO payments (ref_no, receipt_no, amount, method, paid_at)
    VALUES (NEW.ref_no, NEW.receipt_no, NEW.fee, 'Cashier', NOW());
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_ren_before_update$$
CREATE TRIGGER trg_ren_before_update BEFORE UPDATE ON renewals
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status AND NEW.status IN ('Approved','Rejected') THEN
    SET NEW.decided_at = NOW();
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_ren_after_update$$
CREATE TRIGGER trg_ren_after_update AFTER UPDATE ON renewals
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status AND NEW.status IN ('Approved','Rejected') THEN
    INSERT INTO notifications (user_id, ref_no, title, message)
    VALUES (NEW.user_id, NEW.ref_no, 'Renewal request decided',
            CONCAT('Your renewal request ', NEW.ref_no, ' was ', LOWER(NEW.status), '.'));
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_enq_before_update$$
CREATE TRIGGER trg_enq_before_update BEFORE UPDATE ON enquiries
FOR EACH ROW
BEGIN
  IF NEW.reply IS NOT NULL AND NEW.reply <> '' AND NOT (NEW.reply <=> OLD.reply) THEN
    SET NEW.replied_at = NOW();
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_enq_after_update$$
CREATE TRIGGER trg_enq_after_update AFTER UPDATE ON enquiries
FOR EACH ROW
BEGIN
  IF NEW.reply IS NOT NULL AND NEW.reply <> '' AND NOT (NEW.reply <=> OLD.reply) THEN
    INSERT INTO notifications (user_id, ref_no, title, message)
    VALUES (NEW.user_id, NEW.ref_no, 'Reply to your enquiry',
            CONCAT('The office replied to your enquiry ', NEW.ref_no, '.'));
  END IF;
END$$

DELIMITER ;

-- =====================================================
-- V3 ADDITIONS - REFERENCE DATA (values copied from your index.html)
-- =====================================================
INSERT IGNORE INTO fee_schedule (service_code, service_name, fee, processing_time) VALUES
('NEW-REG',  'New passport - Regular',        60.00, '20 working days'),
('NEW-EXP',  'New passport - Express',        95.00, '7 working days'),
('REN-REG',  'Renewal - Regular',             55.00, '15 working days'),
('REN-EXP',  'Renewal - Express',             90.00, '5 working days'),
('LOST-SUR', 'Lost / damaged surcharge',      40.00, '+3 working days'),
('COURIER',  'Courier delivery (optional)',   12.00, '2-4 days');

INSERT IGNORE INTO document_requirements (app_type, doc_name, notes) VALUES
('New Passport',     'PSA birth certificate',      NULL),
('New Passport',     'Valid government ID',        NULL),
('New Passport',     'Accomplished form',          NULL),
('New Passport',     'Appointment confirmation',   NULL),
('Passport Renewal', 'Current passport',           NULL),
('Passport Renewal', 'Valid government ID',        NULL),
('Passport Renewal', 'Marriage certificate',       'Only if your name changed'),
('Replacement',      'Affidavit of loss',          NULL),
('Replacement',      'Police report',              NULL),
('Replacement',      'Birth certificate',          NULL),
('Replacement',      'Valid government ID',        NULL);

-- Office addresses (from the "Passport offices" list on your website)
UPDATE offices SET address = 'Robinsons Galleria, West Lane'   WHERE office_name = 'DFA NCR Central Passport Office';
UPDATE offices SET address = 'Double Dragon Plaza'             WHERE office_name = 'DFA Aseana';
UPDATE offices SET address = 'Near MOA, Newport Mall'          WHERE office_name = 'Pasay City Office';

-- Bring existing paid applications into the payments table (safe to run more than once)
INSERT IGNORE INTO payments (ref_no, receipt_no, amount, method, paid_at)
SELECT ref_no, receipt_no, fee, 'Cashier', CAST(submitted_date AS DATETIME)
FROM applications
WHERE is_paid = 1 AND receipt_no IS NOT NULL;

-- =====================================================
-- V3 SAMPLE DATA (only for a fresh import)
-- =====================================================
INSERT INTO courier_requests (ref_no, delivery_address, courier_fee, status) VALUES
('PPT-2026-000091', '123 Sample St., Quezon City', 12.00, 'Requested');

INSERT INTO notifications (user_id, ref_no, title, message, is_read, created_at) VALUES
('MEMBER', 'PPT-2026-000125', 'Application received',  'Your application PPT-2026-000125 was submitted successfully.',          1, '2026-09-24 09:00:00'),
('MEMBER', 'PPT-2026-000125', 'Application update',    'Application PPT-2026-000125 is now at: Documents Verified.',            1, '2026-09-28 10:00:00'),
('MEMBER', 'PPT-2026-000125', 'Appointment scheduled', 'Your biometrics appointment is on Oct 14, 2026 at 9:30 AM.',            0, '2026-10-02 10:00:00');


-- =====================================================
-- USEFUL QUERIES (for testing / for your defense)
-- =====================================================
--   SELECT * FROM v_admin_dashboard;                       -- all admin totals in one row
--   SELECT * FROM v_stage_summary;                         -- applications per stage
--   SELECT * FROM v_overdue_applications;                  -- late applications
--   SELECT * FROM v_upcoming_appointments;                 -- appointments not yet happened
--   SELECT * FROM v_revenue_by_month;                      -- money collected per month
--   SELECT * FROM v_recent_activity ORDER BY log_id DESC LIMIT 10;
--   SELECT * FROM notifications WHERE user_id = 'MEMBER' ORDER BY created_at DESC;
--   SELECT * FROM fee_schedule;
--   SELECT * FROM document_requirements WHERE app_type = 'New Passport';
