import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const hardhatHome = join(root, ".hardhat-home");
const hardhatCli = join(root, "node_modules", "hardhat", "dist", "src", "cli.js");

mkdirSync(join(hardhatHome, "roaming"), { recursive: true });
mkdirSync(join(hardhatHome, "local"), { recursive: true });
mkdirSync(join(hardhatHome, "config"), { recursive: true });
mkdirSync(join(hardhatHome, "cache"), { recursive: true });

const child = spawn(process.execPath, [hardhatCli, ...process.argv.slice(2)], {
  stdio: "inherit",
  env: {
    ...process.env,
    APPDATA: join(hardhatHome, "roaming"),
    LOCALAPPDATA: join(hardhatHome, "local"),
    XDG_CONFIG_HOME: join(hardhatHome, "config"),
    XDG_CACHE_HOME: join(hardhatHome, "cache"),
  },
});

child.on("exit", (code, signal) => {
  if (signal !== null) {
    process.kill(process.pid, signal);
  }

  process.exit(code ?? 1);
});
