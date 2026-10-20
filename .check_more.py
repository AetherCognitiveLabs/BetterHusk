import re, sys

src = open('src/translation-layer-next/husk-tl-jni-more.c', encoding='utf-8').read()

# 1. brace/paren balance with real C lexing (strings, chars, comments)
def strip_c(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        ch = s[i]
        if ch == '/' and i + 1 < n and s[i+1] == '/':
            while i < n and s[i] != '\n': i += 1
            continue
        if ch == '/' and i + 1 < n and s[i+1] == '*':
            i += 2
            while i + 1 < n and not (s[i] == '*' and s[i+1] == '/'): i += 1
            i += 2
            continue
        if ch == '"':
            i += 1
            while i < n and s[i] != '"':
                if s[i] == '\\': i += 1
                i += 1
            i += 1
            continue
        if ch == "'":
            i += 1
            while i < n and s[i] != "'":
                if s[i] == '\\': i += 1
                i += 1
            i += 1
            continue
        out.append(ch)
        i += 1
    return ''.join(out)

code = strip_c(src)
depth = 0
for ch in code:
    if ch == '{': depth += 1
    elif ch == '}': depth -= 1
print('brace depth:', depth)
print('paren balance:', code.count('(') - code.count(')'))

# 2. duplicate function definitions
defs = re.findall(r'^static\s+(?:void|jvalue|int|bool|jobj \*|char \*|const char \*|jclass \*|size_t|long|uint\w+_t|int64_t|float|double)\s+(\w+)\s*\(', src, re.M)
from collections import Counter
dups = [k for k, v in Counter(defs).items() if v > 1]
print('duplicate defs:', dups[:20] if dups else 'none')

# 3. undefined helper refs: collect called names vs defined
calls = set(re.findall(r'\b(\w+)\s*\(', code))
defined = set(defs)
defined |= set(re.findall(r'^\w[\w\s\*]*\b(\w+)\s*\([^)]*\)\s*\{', src, re.M))
defined |= set(re.findall(r'#define\s+(\w+)', src))
defined |= set(re.findall(r'\b(\w+)\s*\(', open('src/translation-layer-next/husk-tl-jni.h', encoding='utf-8').read()))
libc = {'if','for','while','switch','return','sizeof','snprintf','strcpy','strncpy','strcmp','strncmp','strstr','strchr','strrchr','strlen','strtol','strtoll','strtod','strtof','strtoul','atoi','atol','atof','malloc','calloc','realloc','free','memcpy','memset','memmove','memcmp','fopen','fclose','fread','fwrite','fgets','fputs','fprintf','printf','sprintf','sscanf','fseek','ftell','rewind','fflush','open','close','read','write','lseek','mkdir','stat','fstat','access','unlink','rename','opendir','readdir','closedir','dlopen','dlsym','dlclose','dlerror','exit','abort','assert','toupper','tolower','isspace','isdigit','isalpha','isalnum','isxdigit','va_start','va_end','va_arg','va_copy','time','clock','localtime','gmtime','strftime','mktime','sleep','usleep','getpid','gettid','pthread_create','pthread_join','pthread_mutex_lock','pthread_mutex_unlock','pthread_mutex_init','pthread_cond_wait','pthread_cond_signal','pthread_cond_broadcast','pthread_self','qsort','abs','labs','rand','srand','getenv','setenv','unsetenv','putenv','fileno','fdopen','getcwd','chdir','realpath','basename','dirname','strdup','strndup','strcat','strncat','strcasecmp','strncasecmp','strspn','strcspn','strpbrk','strtok','strtok_r','strerror','strlcpy','strlcat','ftruncate','truncate','fsync','fdatasync','mktemp','mkstemp','tmpnam','remove','feof','ferror','clearerr','fgetc','fgets','ungetc','fputc','putchar','getchar','puts','setvbuf','setbuf','remove','perror','errno','isfinite','isnan','isinf','islower','isupper','ispunct','isprint','iscntrl','isgraph','fmod','floor','ceil','round','sqrt','pow','exp','log','log2','log10','sin','cos','tan','asin','acos','atan','atan2','fabs','hypot','fmax','fmin','copysign','nextafter','remainder','rint','trunc','nearbyint','lrint','llrint','lround','llround','ldexp','frexp','modf','scalbn','nan','INFINITY','isascii','toascii','memchr','memrchr','wcschr','wcslen','wcscmp','btowc','wctob','iswalpha','iswdigit','iswspace','towupper','towlower','aligned_alloc','posix_memalign','mmap','munmap','mprotect','madvise','msync','sysconf','getpagesize','sched_yield','nanosleep','clock_gettime','gettimeofday','settimeofday','difftime','asctime','ctime','tzset','signal','sigaction','kill','raise','alarm','pause','waitpid','wait','fork','execve','execvp','execl','execlp','system','popen','pclose','pipe','dup','dup2','fcntl','ioctl','select','poll','socket','bind','connect','listen','accept','send','recv','sendto','recvfrom','shutdown','setsockopt','getsockopt','getsockname','getpeername','getaddrinfo','freeaddrinfo','gai_strerror','inet_pton','inet_ntop','inet_addr','inet_ntoa','htons','htonl','ntohs','ntohl','if_nametoindex','gethostbyname','gethostname','uname','sysctl','sysctlbyname','proc_pidinfo','pthread_kill','pthread_sigmask','sigprocmask','sigsuspend','sigwait','sigemptyset','sigfillset','sigaddset','sigismember','sigpending','pthread_mutex_destroy','pthread_cond_init','pthread_cond_destroy','pthread_cond_timedwait','pthread_rwlock_init','pthread_rwlock_rdlock','pthread_rwlock_wrlock','pthread_rwlock_unlock','pthread_rwlock_destroy','pthread_once','pthread_key_create','pthread_key_delete','pthread_getspecific','pthread_setspecific','pthread_detach','pthread_cancel','pthread_testcancel','pthread_setname_np','pthread_getname_np','tl_jhle','M','S','C','STR','H','jobject'}
missing = sorted(c for c in calls - defined - libc if c and c[0].islower() and not c.startswith('__'))
# filter obvious non-functions (field accesses etc are already excluded by word char + paren)
print('possibly undefined calls (first 40):')
for m in missing[:40]: print('  ', m)
print('total missing:', len(missing))
