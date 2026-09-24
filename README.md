# تسجيل المجموعات

موقع عربي لتسجيل الطلاب بالاسم ورقم الهاتف، ثم اختيار مجموعة واحدة من ٧ مجموعات مسائية (الأحد إلى السبت، الساعة ٨:٠٠ مساءً، ٣٠ مقعداً لكل مجموعة).

البيانات تُحفظ في Supabase. الموقع نفسه ملفات ثابتة ويمكن نشره على GitHub Pages ثم ربط نفس المستودع بـ Cloudflare Pages.

## قبل النشر

1. أنشئ مشروعاً مجانياً في [supabase.com](https://supabase.com).
2. من لوحة Supabase افتح **SQL Editor**.
3. انسخ محتوى [supabase/schema.sql](supabase/schema.sql).
4. داخل محرر SQL فقط، استبدل `CHANGE_ME` بكلمة مرور الإدارة. لا تحفظ كلمة المرور في الملف الذي سترفعه إلى GitHub.
5. شغّل السكربت.
6. من **Project Settings → API** انسخ عنوان المشروع والمفتاح `anon` إلى [config.js](config.js):

```js
export const supabaseUrl = "https://YOUR_PROJECT.supabase.co";
export const supabaseAnonKey = "YOUR_ANON_KEY";
```

لتغيير كلمة المرور لاحقاً، شغّل هذا السطر فقط في محرر SQL:

```sql
update private.secrets set admin_password = 'your-new-password' where id = 1;
```

## النشر على GitHub Pages

1. أنشئ مستودعاً عاماً على GitHub وارفع هذا المشروع إلى الفرع `main`.
2. من المستودع افتح **Settings → Pages**.
3. اختر الفرع `main` والمجلد `/ (root)` ثم احفظ.
4. الرابط يكون بهذا الشكل: `https://USERNAME.github.io/REPO-NAME/`
5. لوحة الإدارة: نفس الرابط ثم `admin.html`.

## المزامنة مع Cloudflare Pages

1. في Cloudflare افتح **Workers & Pages → Create → Pages → Connect to Git**.
2. اختر نفس مستودع GitHub.
3. اترك أمر البناء فارغاً، واجعل مجلد الإخراج `/`.
4. Cloudflare يعطيك رابطاً على `*.pages.dev`.

كل رفع إلى `main` يحدّث الموقعين. التسجيل من أي رابط يخصم مقعداً من نفس قاعدة Supabase.

## ملاحظات

- رقم الهاتف يُسجَّل مرة واحدة.
- المجموعة تُغلق عند ٣٠ طالباً حتى لو حاول شخصان الحجز في اللحظة نفسها.
- مفتاح `anon` في `config.js` مصمم ليكون علنياً. كلمة مرور الإدارة تبقى داخل Supabase فقط.
