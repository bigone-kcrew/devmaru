import * as kordoc from "kordoc";

console.log("===== KORDOC EXPORTS =====");
console.log(Object.keys(kordoc).sort());

console.log();
console.log("===== DEFAULT EXPORT =====");
console.log(kordoc.default ?? "(none)");
