const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

const args = process.argv.slice(2);
const targetUrl = args[0] || "about:blank";
const lockFilePath = args[1];

// Buat penanda untuk menahan PowerShell
if (lockFilePath) {
    try {
        fs.writeFileSync(lockFilePath, "LOCKED", "utf8");
    } catch (_) {}
}

console.log("[*] Mempersiapkan Ruang Steril (Multi-Browser Isolation)...");

const platform = os.platform(); // 'win32', 'linux', 'darwin'
const tempPath = os.tmpdir();

// Self-Healing: Bersihkan folder sesi lama yang tertinggal
let staleCount = 0;
try {
    const entries = fs.readdirSync(tempPath);
    for (const entry of entries) {
        if (entry.startsWith("Rasamala_")) {
            const fullEntryPath = path.join(tempPath, entry);
            try {
                if (fs.statSync(fullEntryPath).isDirectory()) {
                    staleCount++;
                    fs.rmSync(fullEntryPath, { recursive: true, force: true });
                }
            } catch (_) {}
        }
    }
} catch (_) {}

if (staleCount > 0) {
    console.log(`  [!] Menemukan ${staleCount} folder sesi lama. Membersihkan...`);
}

let browserMappings = [];
if (platform === "win32") {
    const localApp = process.env.LOCALAPPDATA || "";
    browserMappings = [
        {
            name: "Chrome",
            type: "Chromium",
            paths: [
                "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
                "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
                path.join(localApp, "Google", "Chrome", "Application", "chrome.exe")
            ]
        },
        {
            name: "Brave",
            type: "Chromium",
            paths: [
                "C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe",
                "C:\\Program Files (x86)\\BraveSoftware\\Brave-Browser\\Application\\brave.exe",
                path.join(localApp, "BraveSoftware", "Brave-Browser", "Application", "brave.exe")
            ]
        },
        {
            name: "Edge",
            type: "Chromium",
            paths: [
                "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
                "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
                path.join(localApp, "Microsoft", "Edge", "Application", "msedge.exe")
            ]
        },
        {
            name: "Firefox",
            type: "Firefox",
            paths: [
                "C:\\Program Files\\Mozilla Firefox\\firefox.exe",
                "C:\\Program Files (x86)\\Mozilla Firefox\\firefox.exe",
                path.join(localApp, "Mozilla Firefox", "firefox.exe")
            ]
        }
    ];
} else if (platform === "linux") {
    browserMappings = [
        { name: "Chrome",  type: "Chromium", paths: ["/usr/bin/google-chrome"] },
        { name: "Brave",   type: "Chromium", paths: ["/usr/bin/brave-browser", "/snap/bin/brave"] },
        { name: "Edge",    type: "Chromium", paths: ["/usr/bin/microsoft-edge"] },
        { name: "Firefox", type: "Firefox",  paths: ["/usr/bin/firefox", "/snap/bin/firefox"] }
    ];
} else if (platform === "darwin") {
    browserMappings = [
        { name: "Chrome",  type: "Chromium", paths: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"] },
        { name: "Brave",   type: "Chromium", paths: ["/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"] },
        { name: "Edge",    type: "Chromium", paths: ["/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"] },
        { name: "Firefox", type: "Firefox",  paths: ["/Applications/Firefox.app/Contents/MacOS/firefox"] }
    ];
}

const foundBrowsers = [];
for (const map of browserMappings) {
    for (const bPath of map.paths) {
        try {
            if (fs.statSync(bPath).isFile()) {
                foundBrowsers.push({ name: map.name, type: map.type, path: bPath });
                break;
            }
        } catch (_) {}
    }
}

if (foundBrowsers.length === 0) {
    console.error("Tidak ada browser yang ditemukan di sistem ini.");
    if (lockFilePath) {
        try { fs.rmSync(lockFilePath, { force: true }); } catch (_) {}
    }
    process.exit(1);
}

console.log(`  [-] Ditemukan ${foundBrowsers.length} browser. Meluncurkan secara serentak...`);

const exitPromises = [];
const tempDirectories = [];

for (const browser of foundBrowsers) {
    const randomSuffix = Math.floor(100000000 + Math.random() * 900000000);
    const folderName = `Rasamala_${browser.name}_${randomSuffix}`;
    const tempDir = path.join(tempPath, folderName);

    fs.mkdirSync(tempDir, { recursive: true });
    tempDirectories.push(tempDir);

    console.log(`      [+] Pemantauan LLRT (Asinkron) aktif untuk: ${folderName}`);

    let browserArgs = [];
    if (browser.type === "Chromium") {
        browserArgs = [
            `--user-data-dir=${tempDir}`,
            "--incognito",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            targetUrl
        ];
    } else if (browser.type === "Firefox") {
        browserArgs = ["-profile", tempDir, "-private-window", targetUrl];
    }

    const child = spawn(browser.path, browserArgs, { stdio: "ignore" });
    console.log(`      > ${browser.name} diluncurkan (PID: ${child.pid})`);

    const exitPromise = new Promise((resolve) => {
        child.on("exit", () => resolve());
        child.on("error", () => resolve());
    });
    exitPromises.push(exitPromise);
}

async function waitAndCleanup() {
    await Promise.all(exitPromises);

    console.log("[*] Semua browser telah ditutup. Menghancurkan seluruh jejak sesi...");
    for (const dir of tempDirectories) {
        try {
            fs.rmSync(dir, { recursive: true, force: true });
        } catch (_) {}
    }

    // Hapus penanda agar PowerShell menyelesaikan tugasnya
    if (lockFilePath) {
        try {
            fs.rmSync(lockFilePath, { force: true });
        } catch (_) {}
    }

    console.log("[v] Sesi steril berhasil dihancurkan.");
    process.exit(0);
}

waitAndCleanup();