"""웹 관리 화면 공통 라이브러리(T1) — 표준 라이브러리만 쓴다.

무엇을: 회원 ID·이메일 검증, 예약 ID 목록, TOTP(RFC 6238) 생성·검증, 복구 코드, 비밀 파일 쓰기,
        로그 마스킹(@@PFX@@-mask-lib.sh 규칙 이식), 감사 로그(JSON Lines).
왜:     root 도우미(admin-helper)가 인증·세션·감사의 주인이므로(설계서 §A.1·§B) 그 부품을 한 곳에서 시험한다.
보안 가정: 이 파일은 root 소유 폴더(/usr/local/libexec/@@PFX@@-admin)에서만 불러온다. 경로는 모두 인자로 받고
        전역 경로를 하드코딩하지 않는다. 모든 정규식은 fullmatch 로만 쓴다(개행 우회 방지). 비밀·비밀번호·
        TOTP 코드·토큰은 감사 로그에 기록하지 않는다(허용 목록 방식). 파이썬은 메모리 소거를 보장하지 못한다(알려진 한계).
"""
import base64, hashlib, hmac, json, os, re, secrets, stat, struct, time, urllib.parse

# ── 1. 정규식·검증(모두 fullmatch) ──
WEB_ID_RE = re.compile(r"[a-z][a-z0-9]{1,31}")        # 웹 등록용(§H-9: 밑줄·하이픈 제외)
USER_ID_RE = re.compile(r"[a-z][a-z0-9_-]{1,31}")     # 기존 CLI 규칙
# onboard-deliver 의 EMAIL_RE 와 같은 규칙(괄호·주석·따옴표·비ASCII 불허)
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+")

def _ok(rx, s): return isinstance(s, str) and rx.fullmatch(s) is not None
def valid_web_id(s): return _ok(WEB_ID_RE, s)
def valid_user_id(s): return _ok(USER_ID_RE, s)
def valid_email(s): return _ok(EMAIL_RE, s)

def load_reserved(path):
    """한 줄에 하나·빈 줄과 '#' 주석 무시. 파일이 없거나 읽을 수 없으면 예외(조용히 «예약 없음» 이 되면 안 된다)."""
    out = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip().lower()
            if line: out.add(line)
    return frozenset(out)

def is_reserved(id_, reserved, portal_label):
    """목록에 있거나 포털 라벨(설치마다 다름)과 같으면 예약."""
    s = (id_ or "").lower()
    return s in reserved or s == (portal_label or "").lower()

# ── 2. TOTP (RFC 6238, HMAC-SHA1, 6자리, 30초) ──
STEP = 30
_CODE_RE = re.compile(r"[0-9]{6}")   # \d 를 쓰지 않는다(전각·다른 문자 체계 숫자 거부)

def new_secret(): return base64.b32encode(secrets.token_bytes(20)).decode("ascii")

def _key(secret_b32):
    s = secret_b32.replace(" ", "").replace("-", "").upper()
    return base64.b32decode(s + "=" * (-len(s) % 8), casefold=False)

def totp_code(secret_b32, t):
    """시각 t(초)의 6자리 코드. HOTP 동적 절단 후 10**6 으로 나눈 나머지."""
    h = hmac.new(_key(secret_b32), struct.pack(">Q", int(t // STEP)), hashlib.sha1).digest()
    o = h[-1] & 15
    return "%06d" % ((struct.unpack(">I", h[o:o + 4])[0] & 0x7FFFFFFF) % 10**6)

def totp_verify(secret_b32, code, now, last_used_step, window=1):
    """-> (ok, used_step). last_used_step 이하의 단계는 거부(재사용 방지). 실패하면 (False, last_used_step)."""
    if not isinstance(code, str) or not _CODE_RE.fullmatch(code): return False, last_used_step
    try: base = int(now // STEP); _key(secret_b32)
    except (ValueError, TypeError): return False, last_used_step
    hit = None
    for st in range(base - window, base + window + 1):   # 전부 비교한다(맞는 단계에서 일찍 끝내지 않음)
        if hmac.compare_digest(totp_code(secret_b32, st * STEP), code) and st > last_used_step: hit = st
    return (True, hit) if hit is not None else (False, last_used_step)

def otpauth_uri(secret, account, issuer):
    q = urllib.parse.quote
    return f"otpauth://totp/{q(issuer, safe='')}:{q(account, safe='')}?secret={q(secret, safe='')}&issuer={q(issuer, safe='')}&algorithm=SHA1&digits=6&period=30"

# ── 3. 복구 코드·비밀 파일 ──
_RC_ALPHA = "abcdefghjkmnpqrstuvwxyz23456789"   # 혼동 문자(i l o 0 1) 제외
SCRYPT = dict(n=2**14, r=8, p=1, dklen=32)      # 설계서 §B 에 파라미터 지정 없음(sha256 만 언급) — 임의 선택, 설계와 다른 점으로 보고

def new_recovery_codes(n=10):
    return ["-".join("".join(secrets.choice(_RC_ALPHA) for _ in range(4)) for _ in range(3)) for _ in range(n)]

def _norm_rc(code): return re.sub(r"[\s-]", "", code).lower() if isinstance(code, str) else ""

def hash_recovery(code, salt):
    """-> 'scrypt$<salt hex>$<hash hex>'. salt 는 bytes(보통 16바이트 무작위)."""
    return "scrypt$%s$%s" % (salt.hex(), hashlib.scrypt(_norm_rc(code).encode(), salt=salt, **SCRYPT).hex())

def verify_recovery(code, hashes):
    """맞는 항목의 인덱스(없으면 None). 호출 쪽이 그 항목을 폐기해 1회용으로 만든다. 모든 항목을 비교한다."""
    c = _norm_rc(code)
    if not re.fullmatch(r"[a-z0-9]{12}", c): return None
    hit = None
    for i, h in enumerate(hashes):
        try: _, s, want = h.split("$"); got = hashlib.scrypt(c.encode(), salt=bytes.fromhex(s), **SCRYPT).hex()
        except (ValueError, AttributeError): continue
        if hmac.compare_digest(got, want) and hit is None: hit = i
    return hit

def check_secret_file(path, uid=None):
    """심볼릭 링크 아님·일반 파일·소유자=uid(기본 현재 euid)·권한 0600 이하를 확인한다. 위반이면 예외."""
    st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode): raise PermissionError("비밀 파일이 일반 파일이 아닙니다")
    if st.st_uid != (os.geteuid() if uid is None else uid): raise PermissionError("비밀 파일 소유자가 올바르지 않습니다")
    if st.st_mode & 0o077: raise PermissionError("비밀 파일 권한이 넓습니다(0600 이어야 함)")

def write_secret_file(path, data, uid=None):
    """원자적 쓰기: 같은 폴더에 0600 임시 파일 → fsync → os.replace. 이미 있으면 먼저 권한·소유를 검사한다."""
    if os.path.lexists(path): check_secret_file(path, uid)
    b = data.encode("utf-8") if isinstance(data, str) else data
    tmp = "%s.tmp.%d.%s" % (path, os.getpid(), secrets.token_hex(4))
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb") as f: f.write(b); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise

def dump_totp_file(path, secret, recovery_hashes, last_step=0, uid=None):
    write_secret_file(path, json.dumps({"v": 1, "secret": secret, "recovery": list(recovery_hashes), "last_step": int(last_step)}, sort_keys=True) + "\n", uid)

def load_totp_file(path, uid=None):
    check_secret_file(path, uid)
    d = json.load(open(path, encoding="utf-8"))
    if d.get("v") != 1 or not isinstance(d.get("secret"), str) or not isinstance(d.get("recovery"), list): raise ValueError("TOTP 파일 형식이 올바르지 않습니다")
    return d

# ── 4. 마스킹(@@PFX@@-mask-lib.sh 의 mask() 규칙을 같은 순서·패턴으로 이식. 규칙을 고칠 때는 셸 쪽과 함께) ──
HIGH = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{24,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}|[0-9a-fA-F]{40,}|(offer|pairing)[=#][A-Za-z0-9_%.~+/=-]{16,}|[a-z]+://[^/\s:@]+:[^/\s@]+@", re.M)
_SP = r"[ \t\r\f\v]"   # sed 의 [[:space:]] (한 줄 안에서)
_MASK_RULES = [(re.compile(p, f), r) for p, r, f in [
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*", "[MASKED:private-key]", 0),
    (r"([a-z]+://)[^/\s:@]+:[^/\s@]+@", r"\g<1>[MASKED]@", 0),
    (r"gh[pousr]_[A-Za-z0-9]{30,}", "[MASKED:token]", 0), (r"github_pat_[A-Za-z0-9_]{30,}", "[MASKED:token]", 0),
    (r"(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{24,}", r"\g<1>[MASKED:token]", 0), (r"xox[baprs]-[A-Za-z0-9-]{10,}", "[MASKED:token]", 0),
    (r"AIza[0-9A-Za-z_-]{30,}", "[MASKED:token]", 0), (r"AKIA[0-9A-Z]{16}", "[MASKED:token]", 0),
    (r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}", "[MASKED:jwt]", 0),
    (r"(offer|pairing)([=#])[A-Za-z0-9_%.~+/=-]{16,}", r"\g<1>\g<2>[MASKED:link]", 0),
    (r"[0-9a-fA-F]{40,}", "[MASKED:hex]", 0),
    (r"([Bb]earer|[Bb]asic)" + _SP + r"+[A-Za-z0-9._~+/=-]{8,}", r"\g<1> [MASKED]", 0),
    (r"([A-Za-z0-9_.-]*(PASS|PASSWORD|PASSWD|SECRET|TOKEN|KEY|CREDENTIAL|AUTH)[A-Za-z0-9_.-]*" + _SP + r"*[=:]" + _SP + r"*)(\"[^\"]*\"|'[^']*'|[^ \t\r\n\f\v,;\"]+)", r"\g<1>[MASKED]", re.I),
    (r"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})", r"[MASKED:email]@\g<1>", 0),
]]

def mask(text):
    """sed 처럼 한 줄씩 규칙을 순서대로 적용한다(값만 지우고 구조는 남김)."""
    out = []
    for line in text.splitlines(keepends=True):
        for rx, rep in _MASK_RULES: line = rx.sub(rep, line)
        out.append(line)
    return "".join(out)

# ── 5. 감사 기록(JSON Lines, 허용 목록) ──
AUDIT_KEYS = ("ts", "event", "user", "sid8", "ip", "src_ip", "via", "op", "args", "job", "rc", "dur", "result", "reason")   # §B.5 + 요청 항목. 이 밖의 키는 버린다
AUDIT_MAX_LINE = 4096     # 한 번의 write 로 끝나는 크기(O_APPEND 동시 기록 안전)
AUDIT_MAX_STR = 200
_CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f  ]")

def _clean(v):
    if isinstance(v, bool) or isinstance(v, int): return v
    if isinstance(v, float): return round(v, 3)
    if v is None: return None
    return _CTRL.sub(" ", mask(str(v)))[:AUDIT_MAX_STR]

def audit_record(event):
    r = {k: _clean(event[k]) for k in AUDIT_KEYS if k in event and k != "args"}
    if not r.get("event"): raise ValueError("감사 기록에는 event 가 필요합니다")
    r.setdefault("ts", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    a = event.get("args")
    if isinstance(a, dict):   # 검증된 비밀 아닌 값만 넘기는 것은 호출 쪽 책임 — 여기서는 키 이름·길이·개수만 제한하고 값은 마스킹
        r["args"] = {str(k)[:32]: _clean(v) for k, v in list(a.items())[:16] if re.fullmatch(r"[a-z][a-z0-9_]{0,31}", str(k)) and not isinstance(v, (dict, list))}
    return r

def audit_write(path, event, mode=0o600):
    r = audit_record(event)
    line = json.dumps(r, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
    if len(line) > AUDIT_MAX_LINE - 1: r.pop("args", None); line = json.dumps(r, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
    if len(line) > AUDIT_MAX_LINE - 1: raise ValueError("감사 기록이 너무 깁니다")
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, mode)
    try: os.write(fd, (line + "\n").encode("ascii"))
    finally: os.close(fd)
