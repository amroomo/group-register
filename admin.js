import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { supabaseAnonKey, supabaseUrl } from "./config.js";

const GROUPS = {
  sunday: "الأحد",
  monday: "الإثنين",
  tuesday: "الثلاثاء",
  wednesday: "الأربعاء",
  thursday: "الخميس",
  friday: "الجمعة",
  saturday: "السبت",
};

const MESSAGES = {
  password: "كلمة المرور غير صحيحة.",
  setup: "غيّر كلمة المرور الافتراضية داخل Supabase قبل استخدام لوحة الإدارة.",
  config: "لم يتم ربط قاعدة البيانات بعد. أضف بيانات Supabase في ملف config.js.",
  network: "تعذر الاتصال. تحقق من الإنترنت ثم حاول مرة أخرى.",
};

const form = document.querySelector("#admin-form");
const errorBox = document.querySelector("#admin-error");
const results = document.querySelector("#results");
const resultsBody = document.querySelector("#results-body");
const resultsCount = document.querySelector("#results-count");
const emptyState = document.querySelector("#empty-state");
const downloadButton = document.querySelector("#download-button");

let currentRows = [];

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  errorBox.hidden = true;
  const password = document.querySelector("#admin-password").value;

  if (!supabaseUrl.startsWith("https://") || supabaseUrl.includes("YOUR_PROJECT") || supabaseAnonKey.includes("YOUR_ANON_KEY")) {
    showError(MESSAGES.config);
    return;
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey);
  const submitButton = form.querySelector("button");
  submitButton.disabled = true;

  const { data, error } = await supabase.rpc("list_registrations", {
    p_password: password,
  });

  submitButton.disabled = false;

  if (error || !data) {
    showError(MESSAGES.network);
    return;
  }

  if (!data.ok) {
    showError(MESSAGES[data.error] || MESSAGES.password);
    results.hidden = true;
    return;
  }

  currentRows = data.rows || [];
  renderRows(currentRows);
});

downloadButton.addEventListener("click", () => {
  const header = ["الاسم", "الهاتف", "المجموعة", "وقت التسجيل"];
  const lines = [
    header,
    ...currentRows.map((row) => [
      row.full_name,
      row.phone,
      GROUPS[row.group_day] || row.group_day,
      formatTime(row.created_at),
    ]),
  ];
  const csv = `\uFEFF${lines.map((line) => line.map(csvCell).join(",")).join("\n")}`;
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "registrations.csv";
  link.click();
  URL.revokeObjectURL(link.href);
});

function renderRows(rows) {
  results.hidden = false;
  resultsCount.textContent = `${rows.length.toLocaleString("ar-EG")} طالب`;
  emptyState.hidden = rows.length > 0;
  resultsBody.replaceChildren();

  for (const row of rows) {
    const tr = document.createElement("tr");
    for (const value of [
      row.full_name,
      row.phone,
      GROUPS[row.group_day] || row.group_day,
      formatTime(row.created_at),
    ]) {
      const td = document.createElement("td");
      td.textContent = value;
      tr.appendChild(td);
    }
    resultsBody.appendChild(tr);
  }
}

function formatTime(value) {
  return new Intl.DateTimeFormat("ar-EG", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Riyadh",
  }).format(new Date(value));
}

function csvCell(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function showError(text) {
  errorBox.textContent = text;
  errorBox.hidden = false;
}
