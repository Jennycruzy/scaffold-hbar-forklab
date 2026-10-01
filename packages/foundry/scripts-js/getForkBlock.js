import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const network = process.argv[2] || "mainnet";
const file = fileURLToPath(new URL("./forkBlocks.json", import.meta.url));
const blocks = JSON.parse(readFileSync(file, "utf8"));
const block = Number(blocks[network]);
if (!Number.isSafeInteger(block) || block <= 0) {
  console.error(
    `No pinned ${network} fork block is recorded. Run 'yarn foundry:fork:pin'.`
  );
  process.exit(1);
}
console.log(block);
