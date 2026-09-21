import pathlib
import re
import sys

root = pathlib.Path("android/app/src/main")
manifest = root / "AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")

perms = [
    "INTERNET",
    "ACCESS_NETWORK_STATE",
    "ACCESS_WIFI_STATE",
    "CHANGE_WIFI_MULTICAST_STATE",
    "CHANGE_NETWORK_STATE",
    "WAKE_LOCK",
]
add = ""
for p in perms:
    if ('android.permission.%s"' % p) not in text:
        add += '    <uses-permission android:name="android.permission.%s" />\n' % p
text = text.replace("<application", add + "    <application", 1)
text = re.sub(r'android:label="[^"]*"', 'android:label="Hotspot Racers"', text, count=1)
if "usesCleartextTraffic" not in text:
    text = text.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
manifest.write_text(text, encoding="utf-8")
print("manifest patched")

acts = list(root.rglob("MainActivity.kt")) + list(root.rglob("MainActivity.java"))
if not acts:
    print("MainActivity not found")
    sys.exit(1)
act = acts[0]
src = act.read_text(encoding="utf-8")
m = re.search(r"^\s*package\s+([\w.]+)", src, re.M)
if not m:
    print("package not found")
    sys.exit(1)
pkg = m.group(1)
tpl = pathlib.Path("tool/MainActivity.kt.tpl").read_text(encoding="utf-8")
out = act.with_name("MainActivity.kt")
if act.suffix == ".java":
    act.unlink()
out.write_text(tpl.replace("__PACKAGE__", pkg), encoding="utf-8")
print("MainActivity written for package", pkg)
