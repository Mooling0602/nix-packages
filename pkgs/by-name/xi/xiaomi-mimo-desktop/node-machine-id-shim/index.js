// Minimal stand-in for the `node-machine-id` package.
//
// Upstream's Linux build calls `require("node-machine-id").machineIdSync()`
// from app.asar/out/main/index.mjs to derive the Xiaomi passport deviceId, but
// ships neither the package in app.asar/node_modules nor a bundled
// implementation, so the require always fails and every login attempt dies
// with passport 20014 ("参数错误"). This shim restores the documented
// behaviour of the package on Linux and adds a persistent fallback so a
// machine without any system machine-id still gets a stable id.
//
// Contract (matching node-machine-id@1.1.12):
//   machineIdSync(original) -> string   (original ? raw id : sha256 hex)
//   machineId(original)     -> Promise<string>
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");

const SYSTEM_ID_PATHS = ["/var/lib/dbus/machine-id", "/etc/machine-id"];
const CACHE_FILE = path.join(os.homedir(), ".config", "Xiaomi MiMo", "machine-id");

function clean(id) {
  return String(id).replace(/[\r\n\s]+/g, "").toLowerCase();
}

function readFirst(paths) {
  for (const p of paths) {
    try {
      const id = clean(fs.readFileSync(p, "utf8"));
      if (id.length >= 4) return id;
    } catch {
      // try the next candidate
    }
  }
  return "";
}

function readPersistentId() {
  return readFirst([CACHE_FILE]);
}

function persist(id) {
  try {
    fs.mkdirSync(path.dirname(CACHE_FILE), { recursive: true });
    fs.writeFileSync(CACHE_FILE, id + "\n", { mode: 0o600 });
  } catch {
    // A read-only home must not break login; the id stays valid for this run.
  }
  return id;
}

function machineIdSync(original) {
  let id = readFirst(SYSTEM_ID_PATHS) || readPersistentId();
  if (!id) id = persist(crypto.randomBytes(16).toString("hex"));
  return original ? id : crypto.createHash("sha256").update(id).digest("hex");
}

function machineId(original) {
  return Promise.resolve(machineIdSync(original));
}

module.exports = { machineId, machineIdSync };
