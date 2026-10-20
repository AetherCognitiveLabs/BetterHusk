import sys
for f in sys.argv[1:]:
    src = open(f, encoding='utf-8', errors='replace').read()
    out = []; i = 0; n = len(src); state = 0
    while i < n:
        ch = src[i]
        if state == 0:
            if ch == '"': state = 1
            elif ch == "'": state = 2
            elif ch == '/' and i + 1 < n and src[i+1] == '/': state = 3
            elif ch == '/' and i + 1 < n and src[i+1] == '*': state = 4
            else: out.append(ch)
        elif state == 1:
            if ch == '\\': i += 1
            elif ch == '"': state = 0
        elif state == 2:
            if ch == '\\': i += 1
            elif ch == "'": state = 0
        elif state == 3:
            if ch == '\n': state = 0; out.append(ch)
        elif state == 4:
            if ch == '*' and i + 1 < n and src[i+1] == '/': state = 0; i += 1
        i += 1
    s = ''.join(out)
    print(f, 'braces', s.count('{') - s.count('}'), 'parens', s.count('(') - s.count(')'))
