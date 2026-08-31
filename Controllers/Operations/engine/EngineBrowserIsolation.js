const targetUrl = Deno.args[0] || "about:blank";
const lockFilePath = Deno.args[1];

// Buat penanda untuk menahan PowerShell
if (lockFilePath) {
    try { Deno.writeTextFileSync(lockFilePath, "LOCKED"); } catch (e) {}
}

console.log("[*] Mempersiapkan Ruang Steril (Multi-Browser Isolation)...");

const os = Deno.build.os;
const tempPath = Deno.env.get("TEMP") || Deno.env.get("TMP") || (os === "windows" ? "C:\\Windows\\Temp" : "/tmp");

let staleCount = 0;
try {
    for (const entry of Deno.readDirSync(tempPath)) {
        if (entry.isDirectory && entry.name.startsWith("Rasamala_")) {
            staleCount++;
            Deno.removeSync(`${tempPath}/${entry.name}`, { recursive: true });
        }
    }
} catch (e) {}

if (staleCount > 0) {
    console.log(`  [!] Menemukan ${staleCount} folder sesi lama. Membersihkan...`);
}

let browserMappings = [];
if (os === "windows") {
    const localApp = Deno.env.get("LOCALAPPDATA") || "";
    browserMappings = [
        { name: 'Chrome', type: 'Chromium', paths: [
            "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", 
            "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
            `${localApp}\\Google\\Chrome\\Application\\chrome.exe`
        ]},
        { name: 'Brave', type: 'Chromium', paths: [
            "C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe",
            "C:\\Program Files (x86)\\BraveSoftware\\Brave-Browser\\Application\\brave.exe",
            `${localApp}\\BraveSoftware\\Brave-Browser\\Application\\brave.exe`
        ]},
        { name: 'Edge', type: 'Chromium', paths: [
            "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe", 
            "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
            `${localApp}\\Microsoft\\Edge\\Application\\msedge.exe`
        ]},
        { name: 'Firefox', type: 'Firefox', paths: [
            "C:\\Program Files\\Mozilla Firefox\\firefox.exe",
            "C:\\Program Files (x86)\\Mozilla Firefox\\firefox.exe",
            `${localApp}\\Mozilla Firefox\\firefox.exe`
        ]}
    ];
} else if (os === "linux") {
    browserMappings = [
        { name: 'Chrome', type: 'Chromium', paths: ['/usr/bin/google-chrome'] },
        { name: 'Brave',  type: 'Chromium', paths: ['/usr/bin/brave-browser', '/snap/bin/brave'] },
        { name: 'Edge',   type: 'Chromium', paths: ['/usr/bin/microsoft-edge'] },
        { name: 'Firefox',type: 'Firefox',  paths: ['/usr/bin/firefox', '/snap/bin/firefox'] }
    ];
} else if (os === "darwin") {
    browserMappings = [
        { name: 'Chrome', type: 'Chromium', paths: ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'] },
        { name: 'Brave',  type: 'Chromium', paths: ['/Applications/Brave Browser.app/Contents/MacOS/Brave Browser'] },
        { name: 'Edge',   type: 'Chromium', paths: ['/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'] },
        { name: 'Firefox',type: 'Firefox',  paths: ['/Applications/Firefox.app/Contents/MacOS/firefox'] }
    ];
}

const foundBrowsers = [];
for (const map of browserMappings) {
    for (const bPath of map.paths) {
        try {
            if (Deno.statSync(bPath).isFile) {
                foundBrowsers.push({ name: map.name, type: map.type, path: bPath });
                break; 
            }
        } catch { }
    }
}

if (foundBrowsers.length === 0) {
    console.error("Tidak ada browser yang ditemukan di sistem ini.");
    if (lockFilePath) { try { Deno.removeSync(lockFilePath); } catch (e) {} }
    Deno.exit(1);
}

console.log(`  [-] Ditemukan ${foundBrowsers.length} browser. Meluncurkan secara serentak...`);

const activeProcesses = [];
const tempDirectories = [];

for (const browser of foundBrowsers) {
    const tempDir = Deno.makeTempDirSync({ prefix: `Rasamala_${browser.name}_` });
    tempDirectories.push(tempDir);
    const folderName = tempDir.replace(/\\/g, '/').split('/').pop();

    console.log(`      [+] Timer Polling Deno (Asinkron) aktif untuk: ${folderName}`);

    let browserArgs = [];
    if (browser.type === 'Chromium') {
        browserArgs = [
            `--user-data-dir=${tempDir}`, "--incognito", "--no-first-run",
            "--no-default-browser-check", "--disable-extensions", targetUrl
        ];
    } else if (browser.type === 'Firefox') {
        browserArgs = ["-profile", tempDir, "-private-window", targetUrl];
    }

    const command = new Deno.Command(browser.path, { args: browserArgs });
    const childProcess = command.spawn();
    activeProcesses.push(childProcess);
    
    console.log(`      > ${browser.name} diluncurkan (PID: ${childProcess.pid})`);
}

for (const process of activeProcesses) {
    await process.status;
}

console.log("[*] Semua browser telah ditutup. Menghancurkan seluruh jejak sesi...");
for (const dir of tempDirectories) {
    try { Deno.removeSync(dir, { recursive: true }); } catch { }
}

// Hapus penanda agar PowerShell bisa menyelesaikan tugasnya
if (lockFilePath) {
    try { Deno.removeSync(lockFilePath); } catch (e) {}
}
console.log("[v] Sesi steril berhasil dihancurkan.");