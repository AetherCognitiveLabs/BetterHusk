f = 'src/translation-layer-next/husk-tl-jni-more.c'
s = open(f, encoding='utf-8').read()

# 1) delete the duplicate PendingIntent block (comment through IS_sendIntent)
a = s.find('/* ---- PendingIntent: the deferred-Intent handle')
b = s.find('/* ---- Notification$Builder / NotificationManager ----')
assert a > 0 and b > a
s = s[:a] + s[b:]

# 2) delete the duplicate Notification block through NM_importance, keep the Settings block
c = s.find('/* ---- Notification$Builder / NotificationManager ----')
d = s.find('/* ---- Settings$System / Settings$Global ---- */')
assert c > 0 and d > c
s = s[:c] + s[d:]

open(f, 'w', encoding='utf-8').write(s)
print('merged')
