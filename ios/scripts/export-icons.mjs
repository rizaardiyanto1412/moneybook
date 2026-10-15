// Writes the web app's line icons as template image sets for the iOS asset catalog.
import fs from "node:fs";
const src = fs.readFileSync(process.argv[2], "utf8");
const start = src.indexOf("export const icons = {");
const end = src.indexOf("\n};", start) + 3;
const svg = (body, vb = "0 0 24 24") =>
  `<svg viewBox="${vb}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
const icons = new Function("svg", src.slice(start, end).replace("export const icons =", "return") )(svg);
const out = process.argv[3];
for (const [name, v] of Object.entries(icons)) {
  if (typeof v !== "string") continue;
  const file = v.replace("<svg ", '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" ').replace(/currentColor/g, "#000").replace(' aria-hidden="true"', "");
  const dir = `${out}/mm.${name}.imageset`;
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(`${dir}/${name}.svg`, file);
  fs.writeFileSync(`${dir}/Contents.json`, JSON.stringify({
    images: [{ filename: `${name}.svg`, idiom: "universal" }],
    info: { author: "xcode", version: 1 },
    properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" },
  }));
}
console.log(Object.keys(icons).join(" "));
