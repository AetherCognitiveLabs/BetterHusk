#!/usr/bin/env python3
# Merges the German translations in tools/i18n/parts/de-part*.json into
# src/app/Husk/Localizable.xcstrings, adds the keys harvest.py found missing,
# and validates placeholder parity between the English key and each value.
#
# Usage: python tools/i18n/merge_de.py          -> dry-run report
#        python tools/i18n/merge_de.py --write  -> writes the catalog
import glob, io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
XC = os.path.join(ROOT, 'src/app/Husk/Localizable.xcstrings')
PARTS = sorted(glob.glob(os.path.join(ROOT, 'tools/i18n/parts/de-part*.json')))

# Keys harvest.py reported used-but-missing; real text only (numbers/URLs are
# already correct untranslated).
EXTRA = {
    'Anonymous': {'de': 'Anonym', 'zh-Hans': '匿名'},
    'Diagnostics': {'de': 'Diagnose', 'zh-Hans': '诊断'},
    'Name': {'de': 'Name', 'zh-Hans': '名称'},
    'Save husk-jit.js to Files': {'de': 'husk-jit.js in Dateien sichern',
                                  'zh-Hans': '将 husk-jit.js 存储到“文件”'},
    'Sign Out': {'de': 'Abmelden', 'zh-Hans': '退出登录'},
    'Use Guest Account (Aurora)': {'de': 'Gastkonto verwenden (Aurora)',
                                   'zh-Hans': '使用游客账户（Aurora）'},
    'What worked, what didn\u2019t, how far you got': {
        'de': 'Was lief, was nicht, wie weit du gekommen bist',
        'zh-Hans': '哪些可用、哪些不可用、进展到哪一步'},
    ("For a game that runs in BetterHusk's own Java runtime: every touch writes the window it went to "
     "and the view that answered, and the view tree is printed every few seconds \u2014 all into the "
     "run log, which Technical Details can share. Leave it off while playing normally; the writes "
     "cost a little speed."): {
        'de': ("Bei einem Spiel in BetterHusks eigener Java-Laufzeit schreibt jede Ber\u00fchrung ins "
               "Laufprotokoll, welches Fenster sie erreicht hat und welche View geantwortet hat, und "
               "alle paar Sekunden wird der View-Baum ausgegeben \u2013 Technische Details k\u00f6nnen "
               "das Protokoll teilen. Beim normalen Spielen ausgeschaltet lassen; die Schreibvorg\u00e4nge "
               "kosten etwas Tempo."),
        'zh-Hans': ("对于在 BetterHusk 自带 Java 运行时中运行的游戏：每次触控都会将命中的窗口和响应的视图写入运行日志，"
                    "并每隔几秒输出视图树——技术详情可分享该日志。正常游玩时请保持关闭；这些写入会稍微影响速度。")},

    # Added by the onboarding/setup phase (JITSetupView, ItemPages, SettingsTab,
    # BootScreen, GuestImage). Present here so the merge writes catalog entries
    # the harvester has not seen yet.
    'If there is no "Pair with" row in Settings, Developer Mode is off: enable it first (Settings \u203a Privacy & Security) -- it restarts the %@ once.': {
        'de': 'Gibt es in den Einstellungen keine Zeile \u201ePair with\u201c, ist der Entwicklermodus aus: erst aktivieren (Einstellungen \u203a Datenschutz & Sicherheit) \u2013 dabei startet das %@ einmal neu.',
        'zh-Hans': '如果“设置”中没有“配对”行，说明开发者模式已关闭：请先开启（设置 › 隐私与安全性）——首次开启会重启 %@。'},
    'Cancel the download?': {
        'de': 'Download abbrechen?',
        'zh-Hans': '取消下载？'},
    'Keep Downloading': {
        'de': 'Weiter laden',
        'zh-Hans': '继续下载'},
    'The part already downloaded is discarded; starting again begins at the beginning.': {
        'de': 'Der bereits geladene Teil wird verworfen; ein neuer Versuch beginnt von vorn.',
        'zh-Hans': '已下载的部分将被丢弃，重新开始需要从头下载。'},
    'Remove Android?': {
        'de': 'Android entfernen?',
        'zh-Hans': '移除 Android？'},
    'Keep Android': {
        'de': 'Android behalten',
        'zh-Hans': '保留 Android'},
    'This deletes Android and the apps installed in it, then downloads it again.': {
        'de': 'Das l\u00f6scht Android und die darin installierten Apps und l\u00e4dt es danach erneut herunter.',
        'zh-Hans': '这会删除 Android 及其中安装的应用，然后重新下载。'},
    'Remove Android and Install Again': {
        'de': 'Android entfernen und neu installieren',
        'zh-Hans': '移除 Android 并重新安装'},
    'Run Setup Again': {
        'de': 'Setup erneut ausf\u00fchren',
        'zh-Hans': '再次运行设置向导'},
    'The welcome tour: language, region, JIT, look': {
        'de': 'Die Willkommens-Tour: Sprache, Region, JIT, Aussehen',
        'zh-Hans': '欢迎引导：语言、地区、JIT、外观'},
    "Based on Levi's Husk \u2014 carried further here": {
        'de': 'Basiert auf Levis Husk \u2013 hier weitergef\u00fchrt',
        'zh-Hans': '基于 Levi 的 Husk，在此继续开发'},
    'Star BetterHusk if you like this sort of thing': {
        'de': 'Gib BetterHusk einen Stern, wenn dir so etwas gef\u00e4llt',
        'zh-Hans': '如果你喜欢这类项目，请给 BetterHusk 点个星'},
    ("Android's data partition could not be repaired automatically. Remove Android and install it "
     "again \u2014 and if it fails the same way, please send guest-serial.log with the report."): {
        'de': ("Androids Datenpartition konnte nicht automatisch repariert werden. Entferne Android "
               "und installiere es erneut \u2013 sollte es gleich wieder fehlschlagen, sende bitte "
               "guest-serial.log mit dem Bericht."),
        'zh-Hans': ("Android 数据分区无法自动修复。请移除 Android 并重新安装——如果同样失败，"
                    "请在报告中附上 guest-serial.log。")},

    # Download rate/ETA tail on the Android page (ItemPages.downloadETA).
    'Downloading \u00b7 %@ of %@ \u00b7 %@': {
        'de': 'L\u00e4dt \u00b7 %@ von %@ \u00b7 %@',
        'zh-Hans': '下载中 \u00b7 %@ / %@ \u00b7 %@'},
    '>1 h': {
        'de': '>1 Std.',
        'zh-Hans': '>1 小时'},
    '~%@ min': {
        'de': '~%@ Min.',
        'zh-Hans': '约 %@ 分钟'},
    '~%@ s': {
        'de': '~%@ s',
        'zh-Hans': '约 %@ 秒'},
    '%@/s \u00b7 %@': {
        'de': '%@/s \u00b7 %@',
        'zh-Hans': '%@/秒 \u00b7 %@'},

    # Guest-download row on the Downloads tab.
    'Android system': {
        'de': 'Android-System',
        'zh-Hans': 'Android 系统'},
    'Installing Android\u2026': {
        'de': 'Android wird installiert\u2026',
        'zh-Hans': '正在安装 Android\u2026'},
}

PH = re.compile(r'%(?:\d+\$)?[-+#0-9.]*(?:ll|l|hh|h)?[dfuixX@csp]|\(%([0-9]+)\)')
def placeholders(s):
    return sorted(re.sub(r'\d+\$', '', m) for m in PH.findall(s) if m)

def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}

def main():
    cat = json.load(io.open(XC, encoding='utf-8-sig'))
    strings = cat['strings']

    de = {}
    for p in PARTS:
        part = json.load(io.open(p, encoding='utf-8'))
        dup = set(de) & set(part)
        if dup:
            print('DUPLICATE across parts:', sorted(dup)[:5])
            sys.exit(2)
        de.update(part)
    print(f'German entries loaded: {len(de)} (from {len(PARTS)} parts)')

    # Some catalog keys span several lines (\n inside the key). The parts were
    # split line-by-line, so a part may hold one German entry per line instead
    # of one for the joined key: rebuild the joined entry from its lines, then
    # drop fragments that are not catalog keys of their own.
    consumed, joined = set(), 0
    for k in strings:
        if '\n' in k and k not in de:
            lines = k.split('\n')
            if all(l in de for l in lines):
                de[k] = '\n'.join(de[l] for l in lines)
                consumed.update(lines)
                joined += 1
    needed = {l for k in strings if '\n' in k and k not in de for l in k.split('\n')}
    for l in consumed - needed:
        if l not in strings:
            del de[l]
    if joined:
        print(f'multi-line keys rebuilt from fragments: {joined}')

    # The interpolated-pattern translations (String(localized:) calls harvest
    # cannot see): key -> {de, zh-Hans}, folded into EXTRA below.
    interp_path = os.path.join(ROOT, 'tools/i18n/interp_translated.json')
    interp = {}
    if os.path.exists(interp_path):
        interp = json.load(io.open(interp_path, encoding='utf-8'))
        print(f'interpolated pattern translations loaded: {len(interp)}')

    missing_keys = [k for k in de if k not in strings]
    untranslated = [k for k in strings if k not in de]
    bad_ph = []
    for k, v in de.items():
        if k in strings and placeholders(k) != placeholders(v):
            bad_ph.append((k, placeholders(k), placeholders(v)))
    print(f'keys in catalog missing a German value: {len(untranslated)}')
    for k in untranslated[:10]: print('   no-de:', repr(k[:80]))
    print(f'German entries for keys NOT in catalog: {len(missing_keys)}')
    for k in missing_keys[:10]: print('   extra:', repr(k[:80]))
    print(f'placeholder mismatches: {len(bad_ph)}')
    for k, a, b in bad_ph[:15]: print(f'   {k[:60]!r}: key {a} vs de {b}')

    if '--write' not in sys.argv:
        print('dry run -- pass --write to apply')
        return

    for k, v in de.items():
        if k not in strings:
            print('NOTE: de part key not in catalog, skipping:', repr(k[:80]))
            continue
        strings[k].setdefault('localizations', {})['de'] = unit(v)

    merged_extra = dict(EXTRA)
    merged_extra.update(interp)
    for k, langs in merged_extra.items():
        entry = strings.setdefault(k, {'localizations': {}})
        for lang, v in langs.items():
            # Keep a hand-written translation if one is already there.
            entry['localizations'].setdefault(lang, unit(v))

    with io.open(XC, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(cat, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write('\n')
    de_total = sum(1 for s in strings.values() if 'de' in s.get('localizations', {}))
    print(f'wrote {XC}: {len(strings)} keys, {de_total} with German')

if __name__ == '__main__':
    main()
