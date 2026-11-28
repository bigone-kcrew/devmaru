"""웹 관리 화면 PAM 비밀번호 검증(T2) — ctypes + libpam, 표준 라이브러리만.

무엇을: authenticate(user, password, service) -> bool.  pam_start → pam_authenticate → pam_acct_mgmt → pam_end.
왜:     /etc/shadow 를 직접 읽지 않고 PAM 이 해시 방식·계정 만료·잠금을 판단하게 한다(설계서 §B.1).
보안 가정: root 도우미 안에서만 부른다. 사용자 이름·서비스 이름은 fullmatch 검증 뒤에만 쓴다. 비밀번호는 로그·예외
        메시지·repr 어디에도 넣지 않는다(오류는 고정 문구뿐). 파이썬은 비밀번호 메모리 소거를 보장하지 못한다(알려진 한계).
        실제 libpam 검사는 VM 시험(T18) 몫이다 — 단위 시험은 가짜 libpam(_lib 주입)으로 콜백·메모리 경로만 본다.

ctypes 메모리·수명 규칙(PAM 대화 콜백의 표준 패턴):
 - PAM 은 conv 콜백이 돌려주는 응답 배열(struct pam_response[num_msg])과 그 안의 resp 문자열을 «free()» 로 해제한다.
   그러므로 파이썬 ctypes 버퍼가 아니라 libc 의 calloc/strdup 으로 할당해야 한다(그래야 PAM 의 free 와 짝이 맞는다).
 - 콜백 함수 객체(CFUNCTYPE 결과)와 pam_conv 구조체, 비밀번호 bytes 는 pam_authenticate 가 끝날 때까지 지역 변수로
   붙잡아 둔다. 참조가 사라지면 GC 가 회수해 PAM 이 해제된 함수 포인터를 부르게 된다(크래시).
 - 콜백이 실패(-1, PAM_CONV_ERR)를 돌려줄 때는 이미 할당한 응답을 직접 free 하고 *resp 를 NULL 로 둔다.
"""
import ctypes, ctypes.util, re

USER_RE = re.compile(r"[a-z_][a-z0-9_-]{0,31}")
SERVICE_RE = re.compile(r"[a-z0-9-]{1,40}")
PAM_SUCCESS, PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON, PAM_ERROR_MSG, PAM_TEXT_INFO, PAM_CONV_ERR = 0, 1, 2, 3, 4, 19
PAM_DISALLOW_NULL_AUTHTOK = 1

class _Msg(ctypes.Structure): _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]
class _Resp(ctypes.Structure): _fields_ = [("resp", ctypes.c_void_p), ("resp_retcode", ctypes.c_int)]
_CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(_Msg)), ctypes.POINTER(ctypes.POINTER(_Resp)), ctypes.c_void_p)
class _PamConv(ctypes.Structure): _fields_ = [("conv", _CONV), ("appdata_ptr", ctypes.c_void_p)]

class PamError(Exception):
    """고정 문구만 담는다(비밀번호·사용자 입력을 넣지 않는다)."""

_libs = None
def _load():
    """실제 libpam·libc 를 한 번만 불러온다. 없으면 PamError."""
    global _libs
    if _libs is None:
        pam, libc = ctypes.util.find_library("pam"), ctypes.util.find_library("c")
        if not pam or not libc: raise PamError("libpam 을 찾을 수 없습니다")
        pam, libc = ctypes.CDLL(pam, use_errno=True), ctypes.CDLL(libc, use_errno=True)
        libc.calloc.restype = ctypes.c_void_p; libc.calloc.argtypes = [ctypes.c_size_t, ctypes.c_size_t]
        libc.strdup.restype = ctypes.c_void_p; libc.strdup.argtypes = [ctypes.c_char_p]
        libc.free.restype = None; libc.free.argtypes = [ctypes.c_void_p]
        pam.pam_start.restype = ctypes.c_int; pam.pam_start.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(_PamConv), ctypes.POINTER(ctypes.c_void_p)]
        pam.pam_authenticate.restype = ctypes.c_int; pam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
        pam.pam_acct_mgmt.restype = ctypes.c_int; pam.pam_acct_mgmt.argtypes = [ctypes.c_void_p, ctypes.c_int]
        pam.pam_end.restype = ctypes.c_int; pam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
        _libs = (pam, libc)
    return _libs

def authenticate(user, password, service, *, _lib=None):
    """비밀번호가 맞고 계정이 유효하면 True. 어떤 실패(검증 거부·PAM 오류·예외)도 False — 사유는 구분하지 않는다.
    _lib: 시험용 (pam, libc) 쌍. 실제 libpam 이 없는 환경에서 가짜를 주입한다."""
    if not (isinstance(user, str) and USER_RE.fullmatch(user) and isinstance(service, str) and SERVICE_RE.fullmatch(service)): return False
    if not isinstance(password, str) or not password or "\x00" in password or len(password) > 1024: return False   # 빈 비밀번호는 PAM 에 보내지 않는다
    try: pam, libc = _lib if _lib is not None else _load()
    except PamError: return False
    pw = password.encode("utf-8")   # 아래 콜백이 끝날 때까지 붙잡는다

    def conv(num_msg, msgs, resp_out, _appdata):
        try:
            arr = libc.calloc(num_msg, ctypes.sizeof(_Resp))     # PAM 이 free() 한다 → libc 로 할당
            if not arr: return PAM_CONV_ERR
            resps = ctypes.cast(arr, ctypes.POINTER(_Resp))
            for i in range(num_msg):
                if msgs[i].contents.msg_style == PAM_PROMPT_ECHO_OFF:   # 비밀번호는 여기에만. 그 밖(ECHO_ON·INFO·ERROR)은 resp=NULL(빈 응답)
                    p = libc.strdup(pw)
                    if not p:
                        for j in range(i): libc.free(resps[j].resp)
                        libc.free(arr); return PAM_CONV_ERR
                    resps[i].resp = p
            resp_out[0] = resps
            return PAM_SUCCESS
        except Exception:
            return PAM_CONV_ERR   # 예외를 ctypes 가 stderr 에 찍지 않게 삼킨다(비밀번호 노출 방지)

    cb = _CONV(conv); pc = _PamConv(cb, None); handle = ctypes.c_void_p()   # cb·pc 는 pam_end 뒤까지 지역 변수로 유지
    started = False
    try:
        if pam.pam_start(service.encode("ascii"), user.encode("ascii"), ctypes.byref(pc), ctypes.byref(handle)) != PAM_SUCCESS: return False
        started = True
        if pam.pam_authenticate(handle, PAM_DISALLOW_NULL_AUTHTOK) != PAM_SUCCESS: return False
        return pam.pam_acct_mgmt(handle, PAM_DISALLOW_NULL_AUTHTOK) == PAM_SUCCESS   # 만료·잠금 계정은 여기서 거부
    except Exception:
        return False   # 예외 내용에 비밀번호가 섞일 수 있으므로 버린다
    finally:
        if started: pam.pam_end(handle, PAM_SUCCESS)
        del cb, pc   # (명시적으로 수명 끝을 표시 — 위 호출이 모두 끝난 뒤)
