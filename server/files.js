// Filesystem helpers for server/main.lua, which has no directory listing of its own.
// Uses Node's fs directly so the resource never starts a shell on the host.
const fs = require('fs');
const path = require('path');

const RESOURCE = GetCurrentResourceName();
const MAX_FILES = 50000;
const SKIPPED_DIRECTORIES = new Set(['node_modules', '.git', '.svn', '.hg']);

function calledByThisResource() {
    const invoker = GetInvokingResource();
    return !invoker || invoker === RESOURCE;
}

// Relative paths ('stream/car.yft') of the regular files in a resource whose
// names end with one of `suffixes`, or of every file when none are given.
exports('listResourceFiles', (resourceName, suffixes) => {
    if (!calledByThisResource() || typeof resourceName !== 'string' || resourceName === '') return [];
    const root = GetResourcePath(resourceName);
    if (!root) return [];
    const wanted = Array.isArray(suffixes) ? suffixes.filter((suffix) => typeof suffix === 'string').map((suffix) => suffix.toLowerCase()) : [];
    const matches = (name) => wanted.length === 0 || wanted.some((suffix) => name.toLowerCase().endsWith(suffix));

    const files = [];
    const pending = [''];
    let visited = 0;
    let truncated = false;
    while (pending.length > 0 && visited < MAX_FILES) {
        const relativeDir = pending.pop();
        let entries;
        try {
            entries = fs.readdirSync(path.join(root, relativeDir), { withFileTypes: true });
        } catch {
            continue;
        }
        for (const entry of entries) {
            visited += 1;
            const relative = relativeDir === '' ? entry.name : `${relativeDir}/${entry.name}`;
            if (entry.isDirectory()) {
                if (!SKIPPED_DIRECTORIES.has(entry.name)) pending.push(relative);
            } else if (entry.isFile() && matches(entry.name)) {
                files.push(relative);
            }
            if (visited >= MAX_FILES) {
                truncated = entries.length > 0 && entry !== entries[entries.length - 1] || pending.length > 0;
                break;
            }
        }
    }
    if (truncated) {
        console.log(`[cortex-admin] File scan of ${resourceName} stopped at ${MAX_FILES} entries; addon vehicles past that point are not listed.`);
    }
    return files;
});

// Creates this resource's photos/ folder for screenshot-basic captures.
exports('ensurePhotoDirectory', () => {
    if (!calledByThisResource()) return false;
    try {
        fs.mkdirSync(path.join(GetResourcePath(RESOURCE), 'photos'), { recursive: true });
        return true;
    } catch (err) {
        console.log(`[cortex-admin] Could not create the photos folder: ${err && err.message}`);
        return false;
    }
});
