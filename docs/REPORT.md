# تقرير المشروع — Ubuntu Cloud Desktop

**التاريخ:** 23 أكتوبر 2026  
**المسار المحلي:** `C:\Users\East-Sound\Desktop\ubuntu-systemd-desktop`  
**الهدف:** سطح مكتب Ubuntu احترافي عبر المتصفح، مع Firefox، وطبقة توافق systemd مبنية فوق Supervisor، جاهز للرفع على GitHub والنشر على CranL.

---

## 1. الملخص التنفيذي

تم بناء مشروع كامل ومتكامل على سطح المكتب يحتوي على:

- صورة Ubuntu 24.04 LTS خفيفة.
- واجهة XFCE.
- Firefox من مستودع Mozilla الرسمي، مع دعم اللغة العربية.
- TigerVNC + noVNC للوصول من المتصفح.
- Supervisor كمدير عمليات حقيقي، وهو PID 1 داخل الحاوية.
- طبقة توافق systemd تشمل:
  - `systemctl`
  - `/run/systemd/system`
  - `systemd-detect-virt`
  - `hostnamectl`
  - `timedatectl`
  - `loginctl`
  - `journalctl`
  - `systemd-analyze`
  - D-Bus facade لـ `org.freedesktop.systemd1`
  - Journald socket sink
- صفحة هبوط noVNC مخصصة، وصفحة ترحيب داخلية، و`/healthz`.
- GitHub Actions لبناء الصورة ورفعها إلى GHCR.
- Docker Compose للتشغيل المحلي.
- اختبارات دخانية واختبار لوحدات systemd الديناميكية.
- توثيق كامل بالعربية والإنجليزية.

**الحالة:** المشروع جاهز للبناء والرفع. لم يتم بناء الصورة محليًا لأن Docker/Podman غير مثبتين على الجهاز الحالي. البناء التالي يجب أن يتم عبر GitHub Actions أو CranL.

---

## 2. لماذا Supervisor؟

Supervisor مدير عمليات ناضج، خفيف، ويدعم:

- تشغيل/إيقاف/إعادة تشغيل البرامج.
- إعادة التشغيل التلقائي عند الفشل.
- تجميع العمليات وإرسال الإشارات للمجموعة.
- سوكِت تحكم محلي عبر `/run/supervisor.sock`.
- سجلات منفصلة لكل خدمة.

هذا يجعله مناسبًا كـ PID 1 داخل الحاوية. تم تسمية أمر التشغيل `/usr/local/bin/systemd`
كاختصار (symlink) إلى Supervisord، لذلك يظهر `/proc/1/comm` باسم `systemd`،
بينما التنفيذ الفعلي يظل Supervisor. هذه نقطة توافق مهمة للبرامج التي تفحص PID 1.

---

## 3. المعمارية

```
المتصفح
   │ HTTPS/WSS
   ▼
CranL Edge
   │
   ▼
websockify / noVNC  :3000  (0.0.0.0)
   │
   ▼ 127.0.0.1:5901
TigerVNC / Xvnc
   │ DISPLAY :1
   ▼
XFCE + Firefox + التطبيقات
   │
   ▼
Supervisor (PID 1، باسم systemd)
   ├─ systemd-journald
   ├─ dbus
   ├─ systemd-dbus
   ├─ xvnc
   ├─ xfce
   └─ novnc
```

### مسار الإقلاع

1. `entrypoint.sh` يجهّز:
   - `/run/systemd/system`
   - `/run/systemd/journal`
   - `/run/dbus`
   - `/run/user/1000`
   - كلمة مرور VNC
   - machine-id
   - `/dev/log`
2. ينفّذ `exec` لأمر الحاوية:
   `/usr/local/bin/systemd -n -c /etc/supervisor/supervisord.conf`
3. Supervisor يبدأ الخدمات حسب الأولوية:
   - journald ثم dbus ثم systemd-dbus ثم xvnc ثم xfce ثم novnc.
4. websockify يخدم noVNC على المنفذ 3000 ويصل إلى Xvnc محليًا.
5. إعداد سطح المكتب (الخلفية والأيقونات وإعدادات Firefox) يتم داخل جلسة
   XFCE نفسها عبر `dbus-run-session`، وليس كبرنامج Supervisor منفصل.

---

## 4. طبقة توافق systemd

### 4.1 وحدات النظام

توجد وحدات في `/etc/systemd/system`:

- `dbus.service`
- `systemd-journald.service`
- `systemd-dbus.service`
- `xvnc.service`
- `xfce.service`
- `novnc.service`
- `graphical.target`
- `multi-user.target`
- `basic.target`

تم إنشاء روابط `*.wants` لتفعيلها، و`default.target` يشير إلى
`graphical.target`، تمامًا كما يفعل `systemctl enable` و`set-default`.

### 4.2 systemctl

`systemd/systemctl.py` يدعم:

- `start`, `stop`, `restart`, `reload`
- `status`, `is-active`, `is-failed`, `is-enabled`
- `enable`, `disable`, `mask`, `unmask`
- `list-units`, `list-unit-files`
- `show`, `cat`
- `daemon-reload`, `get-default`, `set-default`, `isolate`
- `kill`, `reset-failed`
- `list-dependencies`
- `--version`, `--help`

كما يدعم الوحدات الديناميكية: عند تشغيل خدمة غير معروفة، يقرأ ملف الوحدة،
يستخرج `ExecStart` و`Environment` و`User` و`WorkingDirectory` و`Restart`،
ثم يولّد برنامج Supervisor في `/etc/supervisor/conf.d/` ويعمل
`supervisorctl reread && supervisorctl update`.

### 4.3 D-Bus

`systemd_dbus.py` يملك الاسم `org.freedesktop.systemd1` على نظام D-Bus
ويوفّر:

- Manager: `GetUnit`, `ListUnits`, `StartUnit`, `StopUnit`, `RestartUnit`,
  `GetUnitFileState`, `EnableUnitFiles`, `DisableUnitFiles`,
  `GetDefaultTarget`, `SetDefaultTarget`, `Reload`.
- Unit: `Start`, `Stop`, `Restart`, `Reload`, `Kill`, `ResetFailed`.
- Service/Target properties.
- Job objects وإشارات `JobNew` / `JobRemoved`.

### 4.4 journald و journalctl

- `systemd-journald.py` ينشئ:
  - `/run/systemd/journal/socket`
  - `/run/systemd/journal/dev-log`
  - `/run/systemd/journal/stdout`
- يكتب الرسائل إلى `/var/log/journal/compat.log`.
- `journalctl.py` يقرأ هذا الملف وسجلات Supervisor، ويدعم `-u`, `-n`,
  `-f`, `--no-pager`, `--disk-usage`, `--list-boots`.

### 4.5 أدوات أخرى

- `systemd-detect-virt`: يرجع `none` افتراضيًا (قابل للتغيير).
- `hostnamectl`: يعرض بيانات Ubuntu والـ kernel وmachine-id.
- `timedatectl`: يعرض الوقت والمنطقة الزمنية، ويسمح بـ `set-timezone`.
- `loginctl`: جلسة سطح مكتب افتراضية للمستخدم `desktop`.
- `systemd-analyze`: `time`, `blame`, `verify`, `cat-config`.

---

## 5. ما تعمل به الطبقة وما لا تعمل

| الواجهة | الحالة | ملاحظات |
|---|---|---|
| `/run/systemd/system` | ✅ | يجعل `sd_booted()` يرجع true. |
| `systemctl start/stop/restart/status` | ✅ | مدعوم عبر Supervisor. |
| `systemctl enable/disable` | ✅ | روابط units + autostart للوحدات الديناميكية. |
| `systemctl is-system-running` | ✅ | `running` / `degraded` / `starting` / `offline`. |
| `systemd-detect-virt` | ✅ | `none` افتراضيًا. |
| `hostnamectl` / `timedatectl` / `loginctl` | ✅ | مجموعة عملية. |
| `journalctl` | ✅ | يقرأ سجلات journald وSupervisor. |
| D-Bus Manager/Unit | ✅ | مجموعة شائعة من الخصائص والدوال. |
| `/proc/1/comm` | ✅ | `systemd` عبر symlink. |
| cgroup systemd الحقيقي | ❌ | cgroups الخاصة بـ Supervisor فقط. |
| Snap | ❌ | snapd لا يعمل في هذه الصورة. |
| `systemctl reboot/poweroff` | ❌ | مرفوض داخل الحاوية. |
| إخفاء كامل للحاوية | ❌ | `/.dockerenv` وcgroups وoverlayfs تظل قابلة للفحص. |
| تجاوز أنظمة الأمان/anti-cheat | ❌ | غير مقصود وغير مضمون. |

> **تنبيه مهم:** هذه طبقة توافق وليست systemd حقيقيًا. البرامج التي تفحص
> الواجهات القياسية سترى نظامًا متماسكًا، لكن أدوات الأمان المتقدمة قد
> تكتشف الحاوية. لا ننصح باستخدام المشروع لتجاوز تراخيص أو أنظمة حماية.

---

## 6. Firefox واللغة العربية

- تم تثبيت Firefox من مستودع Mozilla الرسمي، وليس حزمة Snap.
- تم تثبيت حزمة اللغة العربية الرسمية من Mozilla (langpack) وتفعيل
  `intl.locale.requested=ar`.
- تم ضبط:
  - صفحة بداية محلية: `file:///opt/desktop/welcome.html`
  - تعطيل التتبع/Telemetry
  - تعطيل تحديثات Firefox التلقائية داخل الحاوية
  - تعطيل تسريع العتاد المناسب لبيئة VNC
- يمكن تشغيل Firefox من أيقونة سطح المكتب أو من قائمة التطبيقات.

---

## 7. الخفة والأداء

- قاعدة `ubuntu:24.04` فقط.
- تثبيت `--no-install-recommends`.
- XFCE core بدل بيئة سطح مكتب ثقيلة.
- TigerVNC بدل حلول ثقيلة.
- تعطيل compositing في XFCE.
- تعطيل blanking وDPMS.
- Firefox بدون تسريع عتاد.
- تنظيف `/var/lib/apt/lists` و`/var/cache/apt`.
- لا خدمات غير ضرورية (لا SSH، لا snapd، لا printing).

الذاكرة المتوقعة عند التشغيل: حوالي 400–700 MB مع Firefox مفتوح،
حسب الصفحات. وحدة المعالجة المركزية منخفضة في وضع الخمول.

---

## 8. الأمان

- VNC محمي بكلمة مرور، وXvnc يستمع على loopback فقط.
- كلمة مرور VNC التقليدية محدودة بـ 8 أحرف؛ استخدم أقوى قيمة ممكنة بهذا الطول.
- noVNC/websockify هو المنفذ العام الوحيد (3000).
- TLS ينتهي عند CranL؛ المتصفح يستخدم WSS.
- المستخدم `desktop` عضو في `sudo` ويحتاج كلمة مروره.
- root مقفول بكلمة مرور.
- لا يتم تثبيت SSH افتراضيًا.
- `HIDE_CONTAINER=0` افتراضيًا.
- `HIDE_CONTAINER=1` يحذف `/.dockerenv` فقط، وليس ضمانًا أمنيًا.

### توصيات إلزامية قبل النشر العام

1. غيّر `VNC_PW` إلى كلمة مرور قوية وفريدة (بحد أقصى 8 أحرف).
2. غيّر كلمة مرور المستخدم `desktop` من داخل الطرفية (`passwd`).
3. لا تضع مفاتيح أو بيانات شخصية داخل سطح المكتب.
4. اجعل رابط التطبيق خاصًا قدر الإمكان.
5. أعد بناء الصورة دوريًا لتحديث Ubuntu وFirefox.

---

## 9. الاختبارات

### ما تم التحقق منه محليًا

- صحة صياغة Python لكل ملفات `systemd/*.py` باستخدام Python 3.12.
- مراجعة بنية Dockerfile وملفات Supervisor ووحدات systemd.
- مراجعة صفحات HTML وCSS.
- مراجعة أوامر التشغيل والنشر.

### ما يحتاج بناء الصورة

- بناء الصورة نفسها.
- تشغيل XFCE وFirefox فعليًا.
- اختبار D-Bus وsystemctl داخل الحاوية.
- اختبار noVNC عبر المتصفح.
- اختبار `/healthz` بعد النشر.

### الاختبارات الجاهزة داخل الحاوية

```bash
/opt/desktop/tests/smoke-test.sh
sudo /opt/desktop/tests/test-systemd.sh
```

### أوامر فحص سريعة

```bash
systemctl is-system-running
systemctl status xvnc
systemd-detect-virt
hostnamectl
journalctl -n 20
busctl --system introspect org.freedesktop.systemd1 /org/freedesktop/systemd1
ps -p 1 -o comm=
firefox --version
curl -fsS http://127.0.0.1:3000/healthz
```

---

## 10. النشر على CranL

### المسار المفضل

1. رفع المشروع إلى GitHub.
2. GitHub Actions يبني الصورة ويرفعها إلى GHCR.
3. إنشاء تطبيق CranL من الصورة:
   - Image: `ghcr.io/<owner>/ubuntu-systemd-desktop:latest`
   - Port: `3000`
   - Health: `/healthz`
   - Region: `netherlands-1`
4. ضبط المتغيرات:
   - `NOVNC_PORT=3000`
   - `VNC_PORT=5901`
   - `VNC_RESOLUTION=1440x900`
   - `VNC_PW=<8-أحرف>`
   - `TZ=Africa/Cairo`
   - `SYSTEMD_DETECT_VIRT=none`
   - `HIDE_CONTAINER=0`
5. فتح الرابط والتحقق من `/healthz`.

### مسار بديل

CranL يمكنه البناء مباشرة من مستودع GitHub باستخدام Dockerfile.
هذا أبسط، لكنه يعتمد على نجاح بناء المصدر على حساب CranL. إذا فشل،
استخدم مسار GHCR.

### استبدال التطبيق القديم

الخطة المجانية تسمح بتطبيقين. أبقِ التطبيق القديم حتى ينجح الجديد،
ثم احذف القديم من لوحة التحكم. الحذف من لوحة التحكم فوري ويحرر المكان،
بينما الحذف عبر API/MCP يحتفظ بالتطبيق 7 أيام ويظل محسوبًا.

---

## 11. الملفات الرئيسية

| الملف | الوظيفة |
|---|---|
| `Dockerfile` | بناء الصورة وتثبيت الحزم وFirefox. |
| `supervisor/supervisord.conf` | تعريف خدمات Supervisor. |
| `systemd/systemctl.py` | محاكاة systemctl. |
| `systemd/systemd_compat.py` | منطق الوحدات وSupervisor المشترك. |
| `systemd/systemd_dbus.py` | D-Bus facade. |
| `systemd/systemd-journald.py` | journald socket sink. |
| `systemd/units/` | وحدات systemd. |
| `scripts/entrypoint.sh` | تجهيز التشغيل. |
| `scripts/start-xvnc.sh` | تشغيل TigerVNC. |
| `scripts/start-xfce.sh` | تشغيل XFCE. |
| `scripts/start-novnc.sh` | تشغيل websockify. |
| `scripts/setup-desktop.sh` | خلفية وأيقونات وإعدادات. |
| `web/index.html` | صفحة الهبوط. |
| `web/welcome.html` | صفحة الترحيب الداخلية. |
| `.github/workflows/build.yml` | بناء GHCR. |
| `tests/` | اختبارات الدخان وsystemd. |
| `docs/DEPLOY-CRANL.md` | خطوات النشر. |
| `docs/TESTING.md` | خطوات الاختبار. |

---

## 12. حالة التسليم

- ✅ المشروع كامل على سطح المكتب.
- ✅ جاهز للرفع إلى GitHub.
- ✅ GitHub Actions جاهز لبناء الصورة.
- ✅ Docker Compose جاهز للتشغيل المحلي عند توفر Docker.
- ✅ تقرير وتوثيق عربي/إنجليزي.
- ⏳ بناء الصورة لم يتم محليًا (لا Docker/Podman).
- ⏳ النشر النهائي على CranL ينتظر رفع المستودع أو توفير الصورة.

### الخطوة التالية المطلوبة

ارفع المجلد إلى GitHub، ثم أرسل رابط المستودع. بعدها يمكن:

1. تشغيل GitHub Actions.
2. نشر التطبيق على CranL.
3. اختبار `/healthz` وnoVNC وFirefox.
4. استبدال التطبيق القديم بعد نجاح الجديد.

---

## 13. توصيات مستقبلية

- إضافة تحديثات أمنية دورية عبر GitHub Actions.
- إضافة خيار `VNC_PW` من مدير أسرار CranL بدل المتغيرات العادية.
- إضافة نسخ احتياطي اختياري لمجلد `/home/desktop`.
- إضافة مراقبة للذاكرة وCPU.
- تقييد الوصول عبر Cloudflare Access أو VPN إن أمكن.
- توثيق أي تطبيق إضافي يحتاج وحدات systemd.

---

## 14. تحديث 23 أكتوبر 2026 — الأداء والسواب

### 14.1 تحسين VNC ليكون سريعًا

تم ضبط TigerVNC على ملف منخفض الكمون بدل الإعداد الافتراضي:

```text
FrameRate=30  CompareFB=2  ZlibLevel=1  CompressLevel=1
Quality=8     ImprovedHextile  UseBlacklist  -noreset
```

- `FrameRate=30` يقلل الفrames غير الضرورية ويبقي الحركة سلسة.
- `CompareFB=2` يتجاهل المناطق غير المتغيرة من الشاشة.
- `ZlibLevel=1` و`CompressLevel=1` يستخدمان أسرع ضغط بدل أصغر حجم.
- `Quality=8` يحافظ على وضوح النص مع حجم معقول.
- `-noreset` يبقي جلسة XFCE حية عند إغلاق المتصفح، فإعادة الاتصال
  لا تعيد تشغيل سطح المكتب من الصفر.

صفحة noVNC تستخدم:

```text
quality=6&compression=2&resize=remote&autoconnect=1
reconnect=1&reconnect_delay=1000&show_dot=1&path=websockify
```

كما تم تعطيل compositor وظلال النوافذ وحركات XFCE، وتثبيت ثيم
`Adwaita-dark` مسطح، وتعطيل blanking/DPMS، وضبط Firefox على
`dom.ipc.processCount=2` و`browser.tabs.unloadOnLowMemory=true`
وتعطيل التسريع العتادي والـtelemetry.

### 14.2 السواب الكبير في مجلد مسموح

تمت إضافة `scripts/setup-swap.sh`:

- المسار: `/var/swap/swapfile` وليس `/swapfile`.
- الحجم الافتراضي: `6144 MiB` (6 GiB).
- على الحاويات: `SWAP_SPARSE=1` لإنشاء ملف sparse لا يملأ قرص التطبيق.
- على VPS: `SWAP_SPARSE=0` ثم `fallocate` لملف كامل بلا ثقوب.
- يحاول `mkswap` ثم `swapon`، وإن فشل يحاول `zram`، ثم يكتب
  النتيجة في `/usr/share/novnc/swap-status.json` و`/var/log/swap.log`.
- لا يوقف إقلاع سطح المكتب إذا فشل التفعيل.

**النتيجة على CranL:** الحاوية لا تمنح `CAP_SYS_ADMIN`، لذلك
`swapon` يرجع `EPERM`. تغيير المسار من `/swapfile` إلى `/var/swap`
لا يحل المشكلة لأن المنع من نواة/صلاحيات الحاوية، وليس من المجلد.
الملف يُنشأ ويظهر في صفحة الحالة، لكنه لا يصبح سواب نشطًا. السواب
الحقيقي 6 GiB يحتاج VPS أو مضيفًا يسمح بـ`swapon`.

### 14.3 عطل شبكة CranL

في 23 أكتوبر 2026، نقطة حالة CranL تعرض:

- `overall: major_outage`
- `Edge Server`: `major_outage`، صفر نجاح من 1138 فحصًا.
- بدأ العطل في 22 أكتوبر 2026.

داخل تطبيقات CranL: DNS يعمل، لكن كل اتصال TCP/ICMP خارجي ينتهي
بمهلة. الوصول إلى التطبيق من المتصفح يعمل، بينما Firefox و`apt`
و`curl` داخل سطح المكتب لا تصل إلى الإنترنت. هذا عطل منصة وليس
خطأً في الصورة.

### 14.4 المساران

| الهدف | CranL الآن | VPS |
|---|---|---|
| سطح مكتب XFCE + noVNC | ✅ | ✅ |
| VNC سريع | ✅ | ✅ |
| 6 GiB سواب نشط | ❌ (`EPERM`) | ✅ (`host-swap.sh`) |
| إنترنت خارجي | ❌ (عطل Edge) | ✅ |
| تكلفة | مجاني | حسب المزود |

### 14.5 بيانات الدخول

- كلمة مرور VNC خاصة بكل نشر، بحد أقصى 8 أحرف، ولا تُحفظ في المستودع.
- كلمة مرور المستخدم `desktop` الافتراضية: `D3sk!2026` (غيّرها بعد أول دخول).
- `root` مقفول، و`desktop` عضو في `sudo` ويحتاج كلمة المرور.

### 14.6 ملفات جديدة

| الملف | الوظيفة |
|---|---|
| `scripts/setup-swap.sh` | إنشاء وتفعيل السواب وكتابة الحالة. |
| `scripts/swap-status.sh` | عرض حالة السواب من الطرفية. |
| `scripts/system-status.sh` | لوحة حية للمعالج والذاكرة والسواب والخدمات. |
| `scripts/host-swap.sh` | سواب 6 GiB على مضيف VPS. |
| `docs/DEPLOY-VPS.md` | نشر VPS مع سواب حقيقي وإنترنت. |
| `desktop/applications/system-dashboard.desktop` | أيقونة لوحة النظام. |
