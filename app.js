import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { supabaseAnonKey, supabaseUrl } from "./config.js";

const CAPACITY = 30;
const SESSION_TIME = "٨:٠٠ مساءً";

const GROUPS = [
  { id: "sunday", name: "الأحد" },
  { id: "monday", name: "الإثنين" },
  { id: "tuesday", name: "الثلاثاء" },
  { id: "wednesday", name: "الأربعاء" },
  { id: "thursday", name: "الخميس" },
  { id: "friday", name: "الجمعة" },
  { id: "saturday", name: "السبت" },
];

const MESSAGES = {
  name: "يرجى إدخال الاسم الكامل (٥ أحرف على الأقل).",
  phone: "يرجى إدخال رقم هاتف صحيح.",
  duplicate: "هذا الرقم مسجّل مسبقاً.",
  full: "هذه المجموعة اكتملت. اختر مجموعة أخرى.",
  group: "يرجى اختيار مجموعة.",
  config: "لم يتم ربط قاعدة البيانات بعد. أضف بيانات Supabase في ملف config.js.",
  network: "تعذر الاتصال. تحقق من الإنترنت ثم حاول مرة أخرى.",
};

const detailsStep = document.querySelector("#step-details");
const groupsStep = document.querySelector("#step-groups");
const doneStep = document.querySelector("#step-done");
const detailsForm = document.querySelector("#details-form");
const detailsError = document.querySelector("#details-error");
const groupError = document.querySelector("#group-error");
const groupList = document.querySelector("#group-list");
const seatsStatus = document.querySelector("#seats-status");
const nameInput = document.querySelector("#full-name");
const phoneInput = document.querySelector("#phone");

let student = null;
let saving = false;

detailsForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  hide(detailsError);

  const fullName = nameInput.value.trim();
  const phone = phoneInput.value.trim();
  const phoneDigits = phone.replace(/\D/g, "");

  if (fullName.length < 5) {
    show(detailsError, MESSAGES.name);
    return;
  }

  if (phoneDigits.length < 8 || phoneDigits.length > 15) {
    show(detailsError, MESSAGES.phone);
    return;
  }

  student = { fullName, phone };
  document.querySelector("#summary-name").textContent = fullName;
  document.querySelector("#summary-phone").textContent = phone;
  detailsStep.hidden = true;
  groupsStep.hidden = false;
  await loadSeats();
});

document.querySelector("#back-button").addEventListener("click", () => {
  groupsStep.hidden = true;
  detailsStep.hidden = false;
  hide(groupError);
});

document.querySelector("#again-button").addEventListener("click", () => {
  student = null;
  detailsForm.reset();
  doneStep.hidden = true;
  detailsStep.hidden = false;
});

function client() {
  if (!supabaseUrl.startsWith("https://") || supabaseUrl.includes("YOUR_PROJECT") || supabaseAnonKey.includes("YOUR_ANON_KEY")) {
    return null;
  }
  return createClient(supabaseUrl, supabaseAnonKey);
}

async function loadSeats() {
  hide(groupError);
  seatsStatus.hidden = false;
  seatsStatus.textContent = "جارٍ تحميل المقاعد...";
  groupList.replaceChildren();

  const supabase = client();
  if (!supabase) {
    seatsStatus.hidden = true;
    show(groupError, MESSAGES.config);
    return;
  }

  const { data, error } = await supabase.rpc("seat_counts");
  if (error) {
    seatsStatus.hidden = true;
    show(groupError, MESSAGES.network);
    return;
  }

  seatsStatus.hidden = true;
  renderGroups(data || []);
}

function renderGroups(counts) {
  const takenByDay = Object.fromEntries(GROUPS.map((group) => [group.id, 0]));
  for (const row of counts) {
    if (row.group_day in takenByDay) {
      takenByDay[row.group_day] = Number(row.taken) || 0;
    }
  }

  groupList.replaceChildren();
  for (const group of GROUPS) {
    const taken = takenByDay[group.id];
    const remaining = Math.max(CAPACITY - taken, 0);
    const full = remaining === 0;
    const button = document.createElement("button");
    button.type = "button";
    button.className = full ? "group full" : "group";
    button.disabled = full || saving;
    button.innerHTML = `
      <span>
        <strong>${group.name}</strong>
        <small>${SESSION_TIME}</small>
      </span>
      <span class="seats">${full ? "اكتملت" : `${formatNumber(remaining)} / ${formatNumber(CAPACITY)}`}</span>
    `;
    button.addEventListener("click", () => chooseGroup(group, button));
    groupList.appendChild(button);
  }
}

async function chooseGroup(group, button) {
  if (!student || saving) {
    return;
  }

  const supabase = client();
  if (!supabase) {
    show(groupError, MESSAGES.config);
    return;
  }

  saving = true;
  hide(groupError);
  button.disabled = true;
  const seats = button.querySelector(".seats");
  const previousSeats = seats.textContent;
  seats.textContent = "جارٍ التسجيل...";

  const { data, error } = await supabase.rpc("register_student", {
    p_full_name: student.fullName,
    p_phone: student.phone,
    p_group_day: group.id,
  });

  saving = false;

  if (error || !data) {
    seats.textContent = previousSeats;
    button.disabled = false;
    show(groupError, MESSAGES.network);
    return;
  }

  if (!data.ok) {
    show(groupError, MESSAGES[data.error] || MESSAGES.network);
    await loadSeats();
    return;
  }

  document.querySelector("#done-name").textContent = student.fullName;
  document.querySelector("#done-phone").textContent = student.phone;
  document.querySelector("#done-group").textContent = `${group.name} — ${SESSION_TIME}`;
  groupsStep.hidden = true;
  doneStep.hidden = false;
}

function formatNumber(value) {
  return Number(value).toLocaleString("ar-EG");
}

function show(element, text) {
  element.textContent = text;
  element.hidden = false;
}

function hide(element) {
  element.hidden = true;
  element.textContent = "";
}
