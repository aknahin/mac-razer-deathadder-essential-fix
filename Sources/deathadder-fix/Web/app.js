"use strict";

// ---------- config ----------
const MOD = { ctrl: 1, shift: 2, opt: 4, cmd: 8 };

const BUTTONS = {
  left:    { title: "Left button",  locked: true },
  right:   { title: "Right button", locked: true },
  middle:  { title: "Scroll wheel" },
  forward: { title: "Front side button" },
  back:    { title: "Rear side button" },
};

/** Each preset maps to an API action. */
const PRESETS = [
  { name: "Back",            desc: "Mouse button 4 · browsers, VS Code", icon: "←", action: { type: "mouse", value: 4 } },
  { name: "Forward",         desc: "Mouse button 5 · browsers, VS Code", icon: "→", action: { type: "mouse", value: 5 } },
  { name: "Back (Mac apps)", desc: "Works in Finder, Safari, Dia, Music", icon: "⌘[", action: { type: "keyboard", modifiers: MOD.cmd, usage: 0x2f } },
  { name: "Forward (Mac apps)", desc: "Works in Finder, Safari, Dia, Music", icon: "⌘]", action: { type: "keyboard", modifiers: MOD.cmd, usage: 0x30 } },
  { name: "Mission Control", desc: "Show all windows",          icon: "▦", action: { type: "keyboard", modifiers: MOD.ctrl, usage: 0x52 } },
  { name: "Desktop left",    desc: "Previous Space",            icon: "⇠", action: { type: "keyboard", modifiers: MOD.ctrl, usage: 0x50 } },
  { name: "Desktop right",   desc: "Next Space",                icon: "⇢", action: { type: "keyboard", modifiers: MOD.ctrl, usage: 0x4f } },
  { name: "Copy",            desc: "Copy selection",            icon: "⧉", action: { type: "keyboard", modifiers: MOD.cmd, usage: 0x06 } },
  { name: "Paste",           desc: "Paste clipboard",           icon: "⎘", action: { type: "keyboard", modifiers: MOD.cmd, usage: 0x19 } },
  { name: "Middle click",    desc: "Open links in new tab",     icon: "◉", action: { type: "mouse", value: 3 } },
  { name: "Disabled",        desc: "Button does nothing",       icon: "⊘", action: { type: "disabled" } },
];

/** KeyboardEvent.code → HID usage id. */
const HID = (() => {
  const t = {};
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("").forEach((c, i) => (t["Key" + c] = 0x04 + i));
  "1234567890".split("").forEach((c, i) => (t["Digit" + c] = 0x1e + i));
  for (let i = 1; i <= 12; i++) t["F" + i] = 0x3a + i - 1;
  Object.assign(t, {
    Enter: 0x28, Escape: 0x29, Backspace: 0x2a, Tab: 0x2b, Space: 0x2c, Minus: 0x2d, Equal: 0x2e,
    BracketLeft: 0x2f, BracketRight: 0x30, Backslash: 0x31, Semicolon: 0x33, Quote: 0x34, Backquote: 0x35,
    Comma: 0x36, Period: 0x37, Slash: 0x38, Home: 0x4a, PageUp: 0x4b, Delete: 0x4c, End: 0x4d, PageDown: 0x4e,
    ArrowRight: 0x4f, ArrowLeft: 0x50, ArrowDown: 0x51, ArrowUp: 0x52,
  });
  return t;
})();
const HID_NAME = (() => {
  const n = {};
  for (const [code, u] of Object.entries(HID)) {
    n[u] = code.replace(/^Key|^Digit/, "")
      .replace("BracketLeft", "[").replace("BracketRight", "]").replace("ArrowRight", "→").replace("ArrowLeft", "←")
      .replace("ArrowDown", "↓").replace("ArrowUp", "↑").replace("Minus", "-").replace("Equal", "=").replace("Backslash", "\\")
      .replace("Semicolon", ";").replace("Quote", "'").replace("Backquote", "`").replace("Comma", ",").replace("Period", ".").replace("Slash", "/");
  }
  return n;
})();

function formatCombo(mods, usage) {
  let s = "";
  if (mods & MOD.ctrl) s += "⌃";
  if (mods & MOD.opt) s += "⌥";
  if (mods & MOD.shift) s += "⇧";
  if (mods & MOD.cmd) s += "⌘";
  return s + (HID_NAME[usage] || "0x" + usage.toString(16));
}

function sameAction(a, b) {
  if (!a || !b || a.type !== b.type) return false;
  if (a.type === "mouse") return a.value === b.value;
  if (a.type === "keyboard") return a.modifiers === b.modifiers && a.usage === b.usage;
  return true;
}

function labelFor(a) {
  if (!a) return "—";
  if (a.type === "keyboard") return formatCombo(a.modifiers, a.usage);
  if (a.type === "mouse") return ({ 1: "Left click", 2: "Right click", 3: "Middle click", 4: "Back", 5: "Forward" })[a.value] || "Mouse " + a.value;
  if (a.type === "disabled") return "Disabled";
  return a.label || "Custom";
}

// ---------- API ----------
const token = (() => {
  const q = new URLSearchParams(location.search).get("token");
  try { if (q) sessionStorage.setItem("token", q); return q || sessionStorage.getItem("token"); } catch { return q; }
})();

async function api(path, body) {
  const res = await fetch(path, {
    method: body ? "POST" : "GET",
    headers: { "X-Token": token || "", ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || "Request failed (" + res.status + ")");
  return data;
}

// ---------- state + rendering ----------
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];

let state = { connected: null, buttons: {} };
let selected = "back";
let busy = false;
let recorded = null;

function render() {
  const pill = $("#device-pill");
  pill.className = "pill " + (state.connected === null ? "pill-wait" : state.connected ? "pill-ok" : "pill-off");
  $("#device-pill-text").textContent =
    state.connected === null ? "Looking for mouse…" : state.connected ? "DeathAdder Essential connected" : "Mouse not connected";
  $("#meta").textContent = state.connected
    ? `Firmware ${state.firmware} · ${state.mode === 0 ? "Normal mode" : "Driver mode 0x" + state.mode.toString(16)} · Settings stored on the mouse`
    : "Plug the mouse in — this page updates automatically";

  for (const name of Object.keys(BUTTONS)) {
    const a = state.buttons[name];
    const el = $(`[data-label="${name}"]`);
    if (el) el.textContent = state.connected ? labelFor(a) : "—";
    $(`.callout[data-button="${name}"]`)?.classList.toggle("is-off", a?.type === "disabled");
  }

  const sideOff = state.connected && ["back", "forward"].some((b) => state.buttons[b]?.type === "disabled");
  $("#banner").hidden = !sideOff;

  $$("[data-button], [data-for]").forEach((el) =>
    el.classList.toggle("is-selected", (el.dataset.button || el.dataset.for) === selected));

  const cfg = BUTTONS[selected];
  $("#sel-title").textContent = cfg.title;
  $("#sel-current").textContent = state.connected ? labelFor(state.buttons[selected]) : "—";
  $("#locked").hidden = !cfg.locked;
  $("#editor").hidden = !!cfg.locked;

  const list = $("#presets");
  list.replaceChildren(...PRESETS.map((p) => {
    const b = document.createElement("button");
    b.className = "preset" + (sameAction(p.action, state.buttons[selected]) ? " is-current" : "");
    b.disabled = !state.connected || busy;
    b.innerHTML = `<span class="p-ico"></span><span><div class="p-name"></div><div class="p-desc"></div></span><span class="p-keys"></span>`;
    b.querySelector(".p-ico").textContent = p.icon;
    b.querySelector(".p-name").textContent = p.name;
    b.querySelector(".p-desc").textContent = p.desc;
    b.querySelector(".p-keys").textContent = p.action.type === "keyboard" ? formatCombo(p.action.modifiers, p.action.usage) : "";
    b.addEventListener("click", () => assign(p.action, p.name));
    return b;
  }));

  $("#record-apply").disabled = !recorded || !state.connected || busy;
  for (const id of ["#fix", "#reset", "#banner-fix"]) $(id).disabled = !state.connected || busy;
}

function toast(msg, isError = false) {
  const t = $("#toast");
  t.textContent = msg;
  t.className = "toast is-on" + (isError ? " is-error" : "");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.className = "toast"), 2600);
}

async function refresh() {
  if (busy) return;
  try {
    const s = await api("/api/status");
    state = { buttons: {}, ...s };
  } catch (e) {
    state = { connected: false, buttons: {} };
    if (/forbidden/.test(e.message)) {
      $("#device-pill-text").textContent = "Session expired — relaunch DeathAdder Fix";
      return;
    }
  }
  render();
}

async function run(label, fn) {
  busy = true; render();
  try {
    state = { buttons: {}, ...(await fn()) };
    toast("✓ " + label);
  } catch (e) {
    toast(e.message, true);
  } finally {
    busy = false; render();
  }
}

const assign = (action, name) =>
  run(`${BUTTONS[selected].title} → ${name || labelFor(action)}`, () => api("/api/assign", { button: selected, ...action }));

// ---------- selection ----------
function select(name) {
  selected = name;
  stopRecording();
  render();
}
$$("[data-button]").forEach((el) => el.addEventListener("click", () => select(el.dataset.button)));

// ---------- recorder ----------
let recording = false;
function stopRecording() {
  recording = false;
  $("#record").classList.remove("is-recording");
  if (!recorded) $("#record-text").textContent = "Click, then press a key combination";
}
$("#record").addEventListener("click", () => {
  recording = true; recorded = null;
  $("#record").classList.add("is-recording");
  $("#record").classList.remove("has-value");
  $("#record-text").textContent = "Press a key combination…";
  render();
});
$("#record-apply").addEventListener("click", () => {
  if (recorded) assign({ type: "keyboard", ...recorded });
});

// ---------- buttons ----------
$("#fix").addEventListener("click", () => run("Side buttons restored to Back / Forward", () => api("/api/fix", {})));
$("#banner-fix").addEventListener("click", () => run("Side buttons fixed — try them now!", () => api("/api/fix", {})));
$("#reset").addEventListener("click", () => run("All buttons reset to factory defaults", () => api("/api/reset", {})));

$("#quit").addEventListener("click", async () => {
  try { await api("/api/quit", {}); } catch {}
  const d = document.createElement("div");
  d.className = "quit-screen";
  d.innerHTML = "<div><strong>DeathAdder Fix has quit.</strong>Your button settings stay saved on the mouse. You can close this tab.</div>";
  document.body.append(d);
});

// ---------- live tester ----------
const SVG_FOR_EVENT = { 0: "left", 1: "middle", 2: "right", 3: "back", 4: "forward" };
function flash(index) {
  const chip = $(`.chip[data-test="${index}"]`);
  chip?.classList.add("is-on");
  const part = $(`#mouse .anchors [data-for="${SVG_FOR_EVENT[index]}"]`);
  part?.classList.add("is-flash");
  setTimeout(() => { chip?.classList.remove("is-on"); part?.classList.remove("is-flash"); }, 260);
}
document.addEventListener("mousedown", (e) => {
  flash(e.button);
  if (e.button >= 3) e.preventDefault();
});
// Stop side buttons and ⌘[ / ⌘] from navigating away from the app.
document.addEventListener("mouseup", (e) => { if (e.button >= 3) e.preventDefault(); });
document.addEventListener("auxclick", (e) => { if (e.button >= 3) e.preventDefault(); });
history.pushState(null, "", location.href);
window.addEventListener("popstate", () => history.pushState(null, "", location.href));

document.addEventListener("keydown", (e) => {
  const mods = (e.ctrlKey ? MOD.ctrl : 0) | (e.shiftKey ? MOD.shift : 0) | (e.altKey ? MOD.opt : 0) | (e.metaKey ? MOD.cmd : 0);
  const usage = HID[e.code];

  if (recording) {
    e.preventDefault();
    if (!usage) {
      $("#record-text").textContent = (mods ? formatCombo(mods, 0).replace(/0x0$/, "") : "") + " + …";
      return;
    }
    recorded = { modifiers: mods, usage };
    recording = false;
    $("#record").classList.remove("is-recording");
    $("#record").classList.add("has-value");
    $("#record-text").textContent = formatCombo(mods, usage);
    render();
    return;
  }

  if (usage && (mods || e.code.startsWith("F"))) {
    $("#test-key").textContent = "Shortcut: " + formatCombo(mods, usage);
    $("#test-key").classList.add("is-on");
    setTimeout(() => $("#test-key").classList.remove("is-on"), 400);
  }
  if (e.metaKey && (e.code === "BracketLeft" || e.code === "BracketRight")) e.preventDefault();
});

// ---------- boot ----------
render();
refresh();
setInterval(refresh, 4000);
