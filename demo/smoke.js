const { JSDOM } = require("jsdom"); const fs = require("fs");
const dir = process.argv[2];
let html = fs.readFileSync(dir + "/index.html", "utf8").replace(/<script src=[^>]+><\/script>/, "");
const data = fs.readFileSync(dir + "/pr10640.json", "utf8");
const dom = new JSDOM(html, { runScripts: "dangerously", pretendToBeVisual: true, beforeParse(w) {
  w.fetch = () => Promise.resolve({ json: () => Promise.resolve(JSON.parse(data)) });
  w.CSS = { escape: s => s.replace(/["\\]/g, "\\$&") };
  w.Element.prototype.scrollIntoView = function () {};
  w.onerror = (m) => console.log("PAGE ERROR", m);
}});
const w = dom.window, d = w.document;
const click = el => el.dispatchEvent(new w.MouseEvent("click", { bubbles: true }));
setTimeout(() => {
  try {
    const q = s => d.querySelector(s);
    console.log("steps:", d.querySelectorAll(".step").length, "lines in main:", d.querySelectorAll("#main .ln").length);
    for (const t of ["changes", "files", "search", "path"]) { click(q(`[data-ltab="${t}"]`)); console.log(t, "lbody chars", q("#lbody").innerHTML.length, "|", q("#lfoot").textContent.slice(0, 60)); if (t === "search") { const i = q("#sq"); i.value = "_pump"; i.dispatchEvent(new w.Event("input", { bubbles: true })); console.log("  hits", d.querySelectorAll(".sl").length); click(q(".sl")); console.log("  mode after hit:", q("#modeFiles").getAttribute("aria-pressed")); } }
    click(q('[data-ltab="changes"]')); const hb = q("#hideTests"); hb.checked = false; hb.dispatchEvent(new w.Event("change", { bubbles: true })); console.log("changes rows w/ tests:", d.querySelectorAll(".crow").length);
    click(q('[data-ltab="path"]')); click(q('[data-step="2"]'));
    q('#subMap [data-node="relay"]').dispatchEvent(new w.MouseEvent("dblclick", { bubbles: true }));
    console.log("zoom head:", q("#subHead").textContent.slice(0, 60), "| step:", q(".step-head h2").textContent);
    click(q('#subMap [data-node="pu"]')); console.log("after code-box click, mode steps?", q("#modeSteps").getAttribute("aria-pressed"));
    click(q("#unzoom")); console.log("unzoomed:", q("#subHead").textContent.slice(0, 30));
    q('#subMap [data-node="spec"]').dispatchEvent(new w.MouseEvent("dblclick", { bubbles: true })); console.log("toast:", q("#toast").textContent.slice(0, 50));
    q('[data-step="3"]').focus(); d.dispatchEvent(new w.KeyboardEvent("keydown", { key: ">", metaKey: true, shiftKey: true, bubbles: true })); console.log("chips:", q("#chips").textContent);
    q('#subMap [data-node="session"]').dispatchEvent(new w.MouseEvent("contextmenu", { bubbles: true, clientX: 10, clientY: 10 })); console.log("menu:", [...d.querySelectorAll("#ctx button")].map(b => b.textContent).join(" / "));
    click(q("#closePanel")); console.log("memory notes:", d.querySelectorAll(".mem").length); click(q("[data-dropmem]")); console.log("after drop:", d.querySelectorAll(".mem").length);
    d.querySelector(".finding") || 0;
    click(q('[data-ltab="files"]')); q('[data-file]').focus(); d.dispatchEvent(new w.KeyboardEvent("keydown", { key: ">", metaKey: true, shiftKey: true, bubbles: true })); console.log("toast2:", q("#toast").textContent, "| chips:", q("#chips").textContent);
    click(q('[data-tab="review"]')); click(q('[data-set="f1|approved"]')); click(q("#postBtn")); console.log("confirm shown:", !!q(".confirm"));
    click(q("#modeFiles")); console.log("files mode cards:", d.querySelectorAll(".fcard").length);
    click(q("#blameBtn")); console.log("blame cells:", d.querySelectorAll(".bl b").length);
  } catch (e) { console.log("TEST ERROR", e.stack); }
}, 300);
