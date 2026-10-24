<?php
// =====================================================
// api.php - Backend ng Passport Tracking System
// Ito ang tulay sa pagitan ng index.html at ng MySQL database.
// Ilagay sa: C:\xampp\htdocs\passport\api.php
// =====================================================
session_start();
header('Content-Type: application/json; charset=utf-8');

// ---------- 1. DATABASE SETTINGS (default ng XAMPP) ----------
$DB_HOST = 'localhost';
$DB_NAME = 'passport_tracking_db';
$DB_USER = 'root';
$DB_PASS = '';            // walang password ang root sa default XAMPP

// ---------- 2. HELPER FUNCTIONS ----------
function out($data) { echo json_encode($data, JSON_UNESCAPED_UNICODE); exit; }
function fail($msg) { out(['ok' => false, 'error' => $msg]); }

try {
    $pdo = new PDO("mysql:host=$DB_HOST;dbname=$DB_NAME;charset=utf8mb4", $DB_USER, $DB_PASS, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException $e) {
    fail('Cannot connect to the database. Check that MySQL is running and passport_tracking_db was imported.');
}

$in     = json_decode(file_get_contents('php://input'), true) ?: [];
$action = $_GET['action'] ?? '';

function s($key) { global $in; return trim((string)($in[$key] ?? '')); }
function need_login() { if (empty($_SESSION['user'])) fail('Please sign in first.'); return $_SESSION['user']; }
function need_admin() { $u = need_login(); if ($u['role'] !== 'admin') fail('Administrator access only.'); return $u; }
function fmt($v) { return $v ? date('M d, Y', strtotime($v)) : '—'; }
function valid_date($v) { $d = DateTime::createFromFormat('Y-m-d', $v); return $d && $d->format('Y-m-d') === $v; }

// Kinukuha ang applications at ginagawang kapareho ng format na ginagamit ng JavaScript sa index.html
function get_apps($pdo, $where = '', $params = []) {
    $st = $pdo->prepare("SELECT a.*, o.office_name FROM applications a
                         JOIN offices o ON o.office_id = a.office_id
                         $where ORDER BY a.submitted_date DESC, a.ref_no DESC");
    $st->execute($params);
    $list = [];
    foreach ($st->fetchAll() as $r) {
        $docs = [];
        $q = $pdo->prepare('SELECT doc_name, is_received FROM application_documents WHERE ref_no = ? ORDER BY doc_id');
        $q->execute([$r['ref_no']]);
        foreach ($q as $d) $docs[$d['doc_name']] = (bool)$d['is_received'];

        $log = [];
        $q = $pdo->prepare('SELECT log_date, activity FROM application_logs WHERE ref_no = ? ORDER BY log_id');
        $q->execute([$r['ref_no']]);
        foreach ($q as $l) $log[] = [fmt($l['log_date']), $l['activity']];

        $list[] = [
            'ref'       => $r['ref_no'],
            'track'     => $r['tracking_no'],
            'owner'     => $r['user_id'],
            'name'      => $r['first_name'] . ' ' . $r['last_name'],
            'dob'       => $r['date_of_birth'],
            'type'      => $r['app_type'],
            'speed'     => $r['speed'],
            'fee'       => (float)$r['fee'],
            'paid'      => (bool)$r['is_paid'],
            'receipt'   => $r['receipt_no'] ?? '',
            'site'      => $r['office_name'],
            'appt'      => $r['appointment_at'] ? date('M d, Y · H:i', strtotime($r['appointment_at'])) : '—',
            'submitted' => fmt($r['submitted_date']),
            'est'       => fmt($r['est_release']),
            'stage'     => (int)$r['current_stage'],
            'rejected'  => (bool)$r['is_rejected'],
            'reason'    => $r['reject_reason'] ?? '',
            'docs'      => $docs,
            'log'       => $log,
        ];
    }
    return $list;
}

// ---------- 3. ACTIONS ----------
try {
    switch ($action) {

    // ----- LOGIN / LOGOUT / REGISTER -----
    case 'login':
        $id = strtoupper(s('user_id'));
        $pw = (string)($in['password'] ?? '');
        $st = $pdo->prepare('SELECT * FROM users WHERE user_id = ?');
        $st->execute([$id]);
        $u = $st->fetch();
        $ok = false;
        if ($u) {
            $h  = $u['password_hash'];
            $ok = password_verify($pw, $h) || hash_equals($h, hash('sha256', $pw)); // sample users = SHA-256, bagong users = password_hash
        }
        if (!$ok) fail('Invalid Application ID or password.');
        session_regenerate_id(true);
        $_SESSION['user'] = ['id' => $u['user_id'], 'role' => $u['role'], 'name' => $u['full_name'], 'email' => $u['email']];
        out(['ok' => true, 'user' => $_SESSION['user']]);

    case 'me':   // para hindi ma-logout pag nag-refresh ng page
        if (empty($_SESSION['user'])) out(['ok' => false]);
        out(['ok' => true, 'user' => $_SESSION['user']]);

    case 'logout':
        $_SESSION = [];
        session_destroy();
        out(['ok' => true]);

    case 'register':
        $name = s('name'); $email = s('email'); $pw = (string)($in['password'] ?? '');
        if ($name === '' || !filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($pw) < 4)
            fail('Please complete all fields (valid email, password at least 4 characters).');
        $st = $pdo->prepare('SELECT 1 FROM users WHERE email = ?');
        $st->execute([$email]);
        if ($st->fetch()) fail('That email is already registered.');
        $id = '';
        for ($i = 0; $i < 30; $i++) {
            $try = 'MEM-' . random_int(100, 999);
            $st = $pdo->prepare('SELECT 1 FROM users WHERE user_id = ?');
            $st->execute([$try]);
            if (!$st->fetch()) { $id = $try; break; }
        }
        if ($id === '') fail('Could not create a Member ID. Please try again.');
        $pdo->prepare("INSERT INTO users (user_id, password_hash, role, full_name, email) VALUES (?,?, 'member', ?, ?)")
            ->execute([$id, password_hash($pw, PASSWORD_DEFAULT), $name, $email]);
        out(['ok' => true, 'id' => $id]);

    // ----- LOAD DATA (applications, renewals, enquiries, members) -----
    case 'data':
        $u = need_login();
        $isAdmin = $u['role'] === 'admin';

        $apps = $isAdmin ? get_apps($pdo) : get_apps($pdo, 'WHERE a.user_id = ?', [$u['id']]);

        $sql = 'SELECT r.*, u.full_name FROM renewals r JOIN users u ON u.user_id = r.user_id '
             . ($isAdmin ? '' : 'WHERE r.user_id = ? ') . 'ORDER BY r.requested_at DESC, r.ref_no DESC';
        $st = $pdo->prepare($sql); $st->execute($isAdmin ? [] : [$u['id']]);
        $renewals = [];
        foreach ($st as $r) $renewals[] = ['ref' => $r['ref_no'], 'owner' => $r['user_id'], 'name' => $r['full_name'],
            'passport' => $r['passport_no'], 'reason' => $r['reason'], 'speed' => $r['speed'], 'status' => $r['status']];

        $sql = 'SELECT e.*, u.full_name FROM enquiries e JOIN users u ON u.user_id = e.user_id '
             . ($isAdmin ? '' : 'WHERE e.user_id = ? ') . 'ORDER BY e.created_at DESC, e.ref_no DESC';
        $st = $pdo->prepare($sql); $st->execute($isAdmin ? [] : [$u['id']]);
        $enq = [];
        foreach ($st as $e) $enq[] = ['ref' => $e['ref_no'], 'owner' => $e['user_id'], 'name' => $e['full_name'],
            'subject' => $e['subject'], 'category' => $e['category'], 'message' => $e['message'], 'reply' => $e['reply'] ?? ''];

        $members = [];
        if ($isAdmin) {
            foreach ($pdo->query("SELECT user_id, full_name, email FROM users WHERE role = 'member' ORDER BY created_at, user_id") as $m)
                $members[] = ['id' => $m['user_id'], 'name' => $m['full_name'], 'email' => $m['email']];
        }
        out(['ok' => true, 'apps' => $apps, 'renewals' => $renewals, 'enquiries' => $enq, 'members' => $members]);

    // ----- PUBLIC TRACKING (walang login: Reference No. + last name) -----
    case 'public_track':
        $ref = strtoupper(s('ref')); $last = s('name');
        $found = get_apps($pdo, 'WHERE a.ref_no = ? AND LOWER(a.last_name) = LOWER(?)', [$ref, $last]);
        if (!$found) fail('Not found.');
        out(['ok' => true, 'app' => $found[0]]);

    // ----- NEW APPLICATION -----
    case 'apply':
        $u = need_login();
        $first = s('first'); $last = s('last'); $dob = s('dob'); $sex = s('sex'); $pob = s('pob');
        $civil = s('civil'); $email = s('email'); $mobile = s('mobile'); $addr = s('address');
        $office = s('office'); $appt = s('appt');
        $speed = in_array(s('speed'), ['Regular', 'Express'], true) ? s('speed') : 'Regular';
        $type  = strpos(s('type'), 'Replacement') === 0 ? 'Replacement' : 'New Passport';
        if (!in_array($sex, ['Female', 'Male', 'Other'], true)) fail('Please select your sex.');
        if (!in_array($civil, ['Single', 'Married', 'Widowed', 'Separated'], true)) $civil = 'Single';
        if ($first === '' || $last === '' || $pob === '' || $mobile === '' || $addr === '') fail('Please complete all required fields.');
        if (!valid_date($dob) || !valid_date($appt)) fail('Please enter a valid date of birth and appointment date.');
        $st = $pdo->prepare('SELECT office_id FROM offices WHERE office_name = ?');
        $st->execute([$office]);
        $office_id = $st->fetchColumn();
        if (!$office_id) fail('Selected office was not found.');

        $fee = ($speed === 'Express' ? 95 : 60) + ($type === 'Replacement' ? 40 : 0);
        $est = date('Y-m-d', strtotime('+' . ($speed === 'Express' ? 12 : 30) . ' days'));

        $pdo->beginTransaction();
        try {
            $n   = (int)$pdo->query("SELECT COALESCE(MAX(CAST(SUBSTRING(ref_no, 10) AS UNSIGNED)), 125) FROM applications")->fetchColumn() + 1;
            $ref = sprintf('PPT-2026-%06d', $n);
            $trk = 'TRK-' . strtoupper(substr(bin2hex(random_bytes(4)), 0, 6));
            $pdo->prepare('INSERT INTO applications
                (ref_no, tracking_no, user_id, first_name, last_name, date_of_birth, sex, place_of_birth, civil_status,
                 email, mobile_no, home_address, app_type, speed, fee, is_paid, office_id, appointment_at,
                 submitted_date, est_release, current_stage, is_rejected)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?,CURDATE(),?,0,0)')
                ->execute([$ref, $trk, $u['id'], $first, $last, $dob, $sex, $pob, $civil, $email, $mobile, $addr,
                           $type, $speed, $fee, $office_id, $appt . ' 09:00:00', $est]);
            $ins = $pdo->prepare('INSERT INTO application_documents (ref_no, doc_name, is_received) VALUES (?,?,?)');
            foreach ([['Birth certificate', 0], ['Government ID', 0], ['Application form', 1], ['Appointment confirmation', 1]] as $d)
                $ins->execute([$ref, $d[0], $d[1]]);
            $pdo->prepare('INSERT INTO application_logs (ref_no, log_date, activity) VALUES (?, CURDATE(), ?)')
                ->execute([$ref, 'Application submitted online']);
            $pdo->commit();
        } catch (Exception $e) { $pdo->rollBack(); throw $e; }
        out(['ok' => true, 'app' => get_apps($pdo, 'WHERE a.ref_no = ?', [$ref])[0]]);

    // ----- RENEWAL REQUEST -----
    case 'renew':
        $u = need_login();
        $passport = s('passport'); $expiry = s('expiry'); $notes = s('notes');
        $reason = in_array(s('reason'), ['Expiring soon', 'Pages full', 'Change of name'], true) ? s('reason') : 'Expiring soon';
        $speed  = in_array(s('speed'), ['Regular', 'Express'], true) ? s('speed') : 'Regular';
        if ($passport === '') fail('Please enter your current passport number.');
        $exp = valid_date($expiry) ? $expiry : null;
        $n   = (int)$pdo->query("SELECT COALESCE(MAX(CAST(SUBSTRING(ref_no, 10) AS UNSIGNED)), 7) FROM renewals")->fetchColumn() + 1;
        $ref = sprintf('REN-2026-%04d', $n);
        $pdo->prepare('INSERT INTO renewals (ref_no, user_id, passport_no, expiry_date, reason, speed, notes) VALUES (?,?,?,?,?,?,?)')
            ->execute([$ref, $u['id'], $passport, $exp, $reason, $speed, $notes]);
        out(['ok' => true, 'ref' => $ref]);

    // ----- ENQUIRY -----
    case 'enquiry':
        $u = need_login();
        $subject = s('subject'); $message = s('message');
        $cat = in_array(s('category'), ['Application', 'Renewal', 'Payment', 'Appointment', 'Other'], true) ? s('category') : 'Other';
        if ($subject === '' || $message === '') fail('Please enter a subject and a message.');
        $n   = (int)$pdo->query("SELECT COALESCE(MAX(CAST(SUBSTRING(ref_no, 5) AS UNSIGNED)), 0) FROM enquiries")->fetchColumn() + 1;
        $ref = sprintf('CMP-%03d', $n);
        $pdo->prepare('INSERT INTO enquiries (ref_no, user_id, subject, category, message) VALUES (?,?,?,?,?)')
            ->execute([$ref, $u['id'], $subject, $cat, $message]);
        out(['ok' => true, 'ref' => $ref]);

    // ----- ADMIN: ADVANCE STAGE -----
    case 'advance':
        need_admin();
        $ref = s('ref');
        $st = $pdo->prepare('SELECT current_stage, is_rejected FROM applications WHERE ref_no = ?');
        $st->execute([$ref]);
        $a = $st->fetch();
        if (!$a || $a['is_rejected'] || $a['current_stage'] >= 5) fail('This application cannot be advanced.');
        $new = (int)$a['current_stage'] + 1;
        $st = $pdo->prepare('SELECT stage_name FROM stages WHERE stage_no = ?');
        $st->execute([$new]);
        $name = $st->fetchColumn();
        $text = $new >= 5 ? 'Passport ready for release · Claim stub issued' : $name . ' stage started';
        $pdo->prepare('UPDATE applications SET current_stage = ? WHERE ref_no = ?')->execute([$new, $ref]);
        if ($new === 1) // payment is confirmed once documents are verified
            $pdo->prepare("UPDATE applications SET is_paid = 1, receipt_no = COALESCE(receipt_no, ?) WHERE ref_no = ?")
                ->execute(['R-' . random_int(10000, 99999), $ref]);
        $pdo->prepare('INSERT INTO application_logs (ref_no, log_date, activity) VALUES (?, CURDATE(), ?)')->execute([$ref, $text]);
        out(['ok' => true]);

    // ----- ADMIN: REJECT APPLICATION -----
    case 'reject':
        need_admin();
        $ref = s('ref');
        $reason = 'Submitted documents could not be verified. Please re-apply with clear copies of your original documents.';
        $st = $pdo->prepare('UPDATE applications SET is_rejected = 1, reject_reason = ? WHERE ref_no = ? AND is_rejected = 0 AND current_stage < 5');
        $st->execute([$reason, $ref]);
        if ($st->rowCount() === 0) fail('This application cannot be rejected.');
        $pdo->prepare('INSERT INTO application_logs (ref_no, log_date, activity) VALUES (?, CURDATE(), ?)')
            ->execute([$ref, 'Application rejected · documents could not be verified']);
        out(['ok' => true]);

    // ----- ADMIN: APPROVE / REJECT RENEWAL -----
    case 'decide_renewal':
        need_admin();
        $status = s('status');
        if (!in_array($status, ['Approved', 'Rejected'], true)) fail('Invalid decision.');
        $st = $pdo->prepare("UPDATE renewals SET status = ? WHERE ref_no = ? AND status = 'Pending'");
        $st->execute([$status, s('ref')]);
        if ($st->rowCount() === 0) fail('This renewal was already decided.');
        out(['ok' => true]);

    // ----- ADMIN: REPLY TO ENQUIRY -----
    case 'reply':
        need_admin();
        if (s('text') === '') fail('Please write a reply.');
        $pdo->prepare('UPDATE enquiries SET reply = ? WHERE ref_no = ?')->execute([s('text'), s('ref')]);
        out(['ok' => true]);

    default:
        fail('Unknown action.');
    }
} catch (PDOException $e) {
    fail('Database error: ' . $e->getMessage());
}
