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
const downloadDaysButton = document.querySelector("#download-days");
const downloadNamesButton = document.querySelector("#download-names");
const dayBody = document.querySelector("#day-body");
const dayTotal = document.querySelector("#day-total");
const dayNames = document.querySelector("#day-names");

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
  const header = ["الاسم", "الهاتف", "المجموعة الأولى", "المجموعة الثانية", "وقت التسجيل"];
  const lines = [
    header,
    ...currentRows.map((row) => [
      row.full_name,
      row.phone,
      groupName(row.group_day),
      groupName(row.group_day_2),
      formatTime(row.created_at),
    ]),
  ];
  downloadCsv("registrations.csv", lines);
});

downloadDaysButton.addEventListener("click", () => {
  const counts = dayCounts(currentRows);
  const total = counts.reduce((sum, day) => sum + day.count, 0);
  const lines = [
    ["اليوم", "العدد"],
    ...counts.map((day) => [day.name, String(day.count)]),
    ["المجموع", String(total)],
  ];
  downloadCsv("day-counts.csv", lines);
});

downloadNamesButton.addEventListener("click", () => {
  const lines = [["اليوم", "الاسم", "الهاتف"]];
  for (const day of studentsByDay(currentRows)) {
    for (const student of day.students) {
      lines.push([day.name, student.full_name, student.phone]);
    }
  }
  downloadCsv("day-names.csv", lines);
});

function renderRows(rows) {
  results.hidden = false;
  resultsCount.textContent = `${rows.length.toLocaleString("ar-EG")} طالب`;
  emptyState.hidden = rows.length > 0;
  resultsBody.replaceChildren();
  renderDayCounts(rows);
  renderDayNames(rows);

  for (const row of rows) {
    const tr = document.createElement("tr");
    for (const value of [
      row.full_name,
      row.phone,
      groupName(row.group_day),
      groupName(row.group_day_2),
      formatTime(row.created_at),
    ]) {
      const td = document.createElement("td");
      td.textContent = value;
      tr.appendChild(td);
    }
    resultsBody.appendChild(tr);
  }
}

function renderDayCounts(rows) {
  const counts = dayCounts(rows);
  const total = counts.reduce((sum, day) => sum + day.count, 0);
  dayBody.replaceChildren();

  for (const day of counts) {
    const tr = document.createElement("tr");
    for (const value of [day.name, formatNumber(day.count)]) {
      const td = document.createElement("td");
      td.textContent = value;
      tr.appendChild(td);
    }
    dayBody.appendChild(tr);
  }

  dayTotal.textContent = formatNumber(total);
}

function renderDayNames(rows) {
  dayNames.replaceChildren();

  for (const day of studentsByDay(rows)) {
    const section = document.createElement("section");
    section.className = "day-group";

    const title = document.createElement("h3");
    title.textContent = `${day.name} (${formatNumber(day.students.length)})`;
    section.appendChild(title);

    const list = document.createElement("ol");
    for (const student of day.students) {
      const item = document.createElement("li");
      item.textContent = `${student.full_name} — ${student.phone}`;
      list.appendChild(item);
    }
    section.appendChild(list);
    dayNames.appendChild(section);
  }
}

function studentsByDay(rows) {
  const grouped = Object.fromEntries(Object.keys(GROUPS).map((id) => [id, []]));
  for (const row of rows) {
    if (row.group_day in grouped) {
      grouped[row.group_day].push(row);
    }
    if (row.group_day_2 in grouped) {
      grouped[row.group_day_2].push(row);
    }
  }

  return dayCounts(rows)
    .filter((day) => grouped[day.id].length > 0)
    .map((day) => ({
      ...day,
      students: grouped[day.id].sort((a, b) => a.full_name.localeCompare(b.full_name, "ar")),
    }));
}

function dayCounts(rows) {
  const counts = Object.fromEntries(Object.keys(GROUPS).map((id) => [id, 0]));
  for (const row of rows) {
    if (row.group_day in counts) {
      counts[row.group_day] += 1;
    }
    if (row.group_day_2 in counts) {
      counts[row.group_day_2] += 1;
    }
  }

  const order = Object.keys(GROUPS);
  return order
    .map((id) => ({ id, name: GROUPS[id], count: counts[id] }))
    .sort((a, b) => b.count - a.count || order.indexOf(a.id) - order.indexOf(b.id));
}

function formatNumber(value) {
  return Number(value).toLocaleString("ar-EG");
}

function downloadCsv(filename, lines) {
  const csv = `\uFEFF${lines.map((line) => line.map(csvCell).join(",")).join("\n")}`;
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  link.click();
  URL.revokeObjectURL(link.href);
}

function groupName(day) {
  return GROUPS[day] || "—";
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
