"use strict";
// Demo harness for docs/demo.gif — never shipped in the app.
//
// Loaded before app.js. It replaces fetch() with an in-memory fake mouse (so recording
// never touches real hardware) and, given ?t=<seconds>, replays the scripted clicks up
// to that moment and draws a green cursor where it would be. make-demo-gif.sh renders
// one screenshot per frame time and stitches them into a GIF.

(() => {
  const t = parseFloat(new URLSearchParams(location.search).get("t") || "0");

  // ---------- fake mouse ----------
  const MOD_CMD = 8;
  const label = (a) =>
    a.type === "disabled" ? "Disabled" :
    a.type === "keyboard" ? (a.modifiers & MOD_CMD ? "⌘" : "") + ({ 0x2f: "[", 0x30: "]" })[a.usage] :
    ({ 1: "Left click", 2: "Right click", 3: "Middle click", 4: "Back", 5: "Forward" })[a.value];
  const buttons = {
    left: { type: "mouse", value: 1 }, right: { type: "mouse", value: 2 }, middle: { type: "mouse", value: 3 },
    back: { type: "disabled" }, forward: { type: "disabled" },      // the bug, as shipped by Synapse
  };
  const status = () => {
    const b = {};
    for (const [k, v] of Object.entries(buttons)) b[k] = { ...v, label: label(v) };
    return { connected: true, firmware: "1.0", mode: 0, buttons: b };
  };
  window.fetch = async (url, opts = {}) => {
    const body = opts.body ? JSON.parse(opts.body) : {};
    if (url.endsWith("/api/fix")) { buttons.back = { type: "mouse", value: 4 }; buttons.forward = { type: "mouse", value: 5 }; }
    if (url.endsWith("/api/assign")) { const { button, ...a } = body; buttons[button] = a; }
    return new Response(JSON.stringify(status()), { status: 200, headers: { "Content-Type": "application/json" } });
  };

  // ---------- script ----------
  // Each step: move the cursor to `target` (a CSS selector), arriving at `at`, then click.
  const STEPS = [
    // `toast`: the click makes the app show a confirmation toast.
    { at: 2.0, target: "#banner-fix",                     toast: true, caption: "Side buttons disabled? One click fixes them" },
    { at: 4.4, target: '.callout[data-button="back"]',                 caption: "Pick a button…" },
    { at: 6.4, target: ".preset:nth-child(3)",            toast: true, caption: "…then click an action. Saved to the mouse instantly" },
    { at: 8.6, target: '.callout[data-button="forward"]',              caption: "Same for the other side button" },
    { at: 10.4, target: ".preset:nth-child(4)",           toast: true, caption: "Now Back / Forward work in Finder & Safari too" },
  ];
  const START = { x: 720, y: 520 };
  const TRAVEL = 1.1;   // seconds of motion before each click
  const ease = (p) => (p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2);

  const center = (sel) => {
    const r = document.querySelector(sel)?.getBoundingClientRect();
    return r ? { x: r.left + r.width / 2, y: r.top + r.height / 2 } : START;
  };

  window.addEventListener("load", () => {
    document.documentElement.classList.add("demo");
    const style = document.createElement("style");
    style.textContent = `
      .demo-cursor { position: fixed; z-index: 100; pointer-events: none; transform: translate(-3px, -2px); filter: drop-shadow(0 3px 6px rgba(0,0,0,.6)); }
      .demo-ripple { position: fixed; z-index: 99; pointer-events: none; border-radius: 50%; border: 3px solid #3ee6a0; transform: translate(-50%, -50%); }
      .demo-caption { position: fixed; z-index: 101; pointer-events: none; padding: 7px 12px; border-radius: 10px;
        background: #3ee6a0; color: #04140d; font: 650 13px -apple-system, sans-serif; white-space: nowrap; box-shadow: 0 8px 24px rgba(0,0,0,.45); }`;
    document.head.append(style);

    // Let app.js boot and its timers (status poll, load tip) settle before replaying.
    setTimeout(async () => {
      let pos = START, last = null, lastToast = null;
      for (const step of STEPS) {
        if (step.at > t) break;
        pos = center(step.target);       // measure before clicking: the fix banner hides itself
        document.querySelector(step.target)?.click();
        await new Promise((r) => setTimeout(r, 250));      // fake API + render
        last = step;
        if (step.toast) lastToast = step;
      }

      // Cursor position for this frame.
      const next = STEPS.find((s) => s.at > t);
      if (next && t > next.at - TRAVEL) {
        const p = ease((t - (next.at - TRAVEL)) / TRAVEL);
        const to = center(next.target);
        pos = { x: pos.x + (to.x - pos.x) * p, y: pos.y + (to.y - pos.y) * p };
      }

      const cursor = document.createElement("div");
      cursor.className = "demo-cursor";
      cursor.style.left = pos.x + "px";
      cursor.style.top = pos.y + "px";
      cursor.innerHTML = `<svg width="30" height="34" viewBox="0 0 30 34"><path d="M3 2l22 13-10 2.4 6.4 11.4-4.4 2.4-6.4-11.4L3 26z" fill="#3ee6a0" stroke="#04140d" stroke-width="2.2" stroke-linejoin="round"/></svg>`;
      document.body.append(cursor);

      // Click ripple for 0.45 s after each click.
      if (last && t - last.at < 0.45) {
        const k = (t - last.at) / 0.45;
        const ring = document.createElement("div");
        ring.className = "demo-ripple";
        const d = 14 + 46 * k;
        Object.assign(ring.style, { left: pos.x + "px", top: pos.y + "px", width: d + "px", height: d + "px", opacity: String(1 - k) });
        document.body.append(ring);
      }

      // Caption describes what's about to happen (or just happened).
      const cap = next && t > next.at - TRAVEL - 0.3 ? next : last;
      if (cap) {
        const c = document.createElement("div");
        c.className = "demo-caption";
        c.textContent = cap.caption;
        document.body.append(c);
        const w = c.offsetWidth;
        c.style.left = Math.min(Math.max(pos.x - w / 2, 12), innerWidth - w - 12) + "px";
        c.style.top = pos.y + 38 + "px";
      }

      // Only show the app's toast for a moment after the click that caused it.
      const toast = document.getElementById("toast");
      if (!lastToast || t - lastToast.at > 1.8 || t - lastToast.at < 0.15) toast.className = "toast";
      document.title = "ready";
    }, 1400);
  });
})();
