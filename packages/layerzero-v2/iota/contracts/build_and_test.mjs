#!/bin/sh
':'; // ; cat "$0" | node --input-type=module - $@ ; exit $?

/****
 * Usage:
 *    ./build_and_test.mjs compile [contract_name] - to compile a specific contract, if no contract name is provided, all contracts will be compiled
 *    ./build_and_test.mjs test [contract_name] - to test a specific contract, if no contract name is provided, all contracts will be tested
 */
import { fileURLToPath } from 'url';
import { $, fs } from 'zx';
import path from 'node:path';
import { globSync } from 'glob';

let workdir = path.dirname(fileURLToPath(import.meta.url).replace('[eval1]', '')) + '/';
const allModuleDir = {};

// Global variable to track current backups for emergency revert
let currentBackups = null;

function applyTestToml(contractsDir) {
    const backupFiles = [];
    const testTomlFiles = globSync(contractsDir + '**/Move.test.toml');

    if (testTomlFiles.length === 0) {
        return backupFiles;
    }

    console.log('🔄 Applying Move.test.toml configurations...');

    for (const testTomlFile of testTomlFiles) {
        try {
            const moveTomlFile = testTomlFile.replace('Move.test.toml', 'Move.toml');
            const backupFile = moveTomlFile + '.backup';

            if (fs.existsSync(moveTomlFile)) {
                // Create backup file
                fs.copyFileSync(moveTomlFile, backupFile);
                backupFiles.push({ original: moveTomlFile, backup: backupFile });

                // Replace with Move.test.toml content
                const testContent = fs.readFileSync(testTomlFile, 'utf8');
                fs.writeFileSync(moveTomlFile, testContent);

                console.log(
                    `  ✓ Applied ${path.relative(contractsDir, testTomlFile)} → ${path.relative(contractsDir, moveTomlFile)}`
                );
                console.log(`  ✓ Backup saved: ${path.relative(contractsDir, backupFile)}`);
            }
        } catch (error) {
            console.error(`  ❌ Failed to apply ${testTomlFile}:`, error.message);
        }
    }

    console.log(`✅ Applied ${backupFiles.length} Move.test.toml configurations`);
    return backupFiles;
}

function revertToml(backupFiles, contractsDir) {
    console.log('🔄 Reverting Move.toml files back to original...');

    for (const { original, backup } of backupFiles) {
        try {
            if (fs.existsSync(backup)) {
                // Restore from backup file
                fs.copyFileSync(backup, original);
                // Remove backup file
                fs.unlinkSync(backup);
                console.log(`  ✓ Reverted ${path.relative(contractsDir, original)}`);
            }
        } catch (error) {
            console.error(`  ❌ Failed to revert ${original}:`, error.message);
        }
    }

    console.log(`✅ Reverted ${backupFiles.length} files to original Move.toml`);
}

// Emergency revert function for when process is interrupted
function emergencyRevert() {
    if (currentBackups && currentBackups.length > 0) {
        console.log('\n🚨 Process interrupted! Emergency reverting Move.toml files...');
        try {
            const contractsDir = path.dirname(fileURLToPath(import.meta.url)) + '/';
            revertToml(currentBackups, contractsDir);
            console.log('✅ Emergency revert completed successfully');
        } catch (error) {
            console.error('❌ Emergency revert failed:', error.message);
            console.error(
                '⚠️  WARNING: Some files may still have Move.test.toml content instead of original Move.toml!'
            );
        }
    }
    process.exit(1);
}

// Set up signal handlers for graceful cleanup on abort
process.on('SIGINT', emergencyRevert); // Ctrl+C
process.on('SIGTERM', emergencyRevert); // Termination signal
process.on('SIGHUP', emergencyRevert); // Hangup signal

function parseModule(moveFile) {
    const rawData = fs.readFileSync(moveFile, { recursive: true });
    const moveContent = rawData.toString();

    // Extract module name from Move.toml
    const moduleNameMatch = moveContent.match(/name\s*=\s*"([^"]+)"/);
    if (!moduleNameMatch) {
        throw new Error(`Could not find module name in ${moveFile}`);
    }
    const moduleName = moduleNameMatch[1];

    allModuleDir[moduleName] = {
        dir: path.dirname(moveFile),
    };
    return moduleName;
}

async function compile(moduleName) {
    let workdir = allModuleDir[moduleName].dir;
    console.log(`Building ${moduleName} in ${workdir}`);
    try {
        await $({
            cwd: workdir,
            verbose: true,
            stdio: ['inherit', process.stdout, process.stderr],
        })`iota move build --skip-fetch-latest-git-deps`;
    } catch (e) {
        console.error(`Failed to build ${moduleName} in ${workdir}`);
        process.exit(1);
    }
}

async function test(moduleName) {
    const moduleWorkdir = allModuleDir[moduleName].dir;
    console.log(`Testing ${moduleName} in ${moduleWorkdir}`);

    // Apply Move.test.toml configurations before running tests
    // const contractsDir = path.dirname(fileURLToPath(import.meta.url)) + '/';
    // const backupFiles = applyTestToml(contractsDir);

    // Store backups globally for emergency revert
    // currentBackups = backupFiles;

    try {
        await $({
            cwd: moduleWorkdir,
            verbose: true,
            stdio: ['inherit', process.stdout, process.stderr],
        })`iota move test --skip-fetch-latest-git-deps -d`;

        console.log(`✅ ${moduleName} tests passed`);
    } catch (error) {
        console.log(`❌ ${moduleName} tests failed`);
        throw error;
    } finally {
        // Always revert Move.toml files back, even if tests fail
        // revertToml(backupFiles, contractsDir);
        // Clear global backups after successful revert
        // currentBackups = null;
    }
}

const args = process.argv.slice(2);
if (args.length === 0) {
    throw new Error("please provide a task type: 'test' or 'compile'");
}
const taskType = args[0];
const moduleNames = args[1] !== undefined ? args[1].split(',') : [];

async function main() {
    // workdir already points to the contracts directory
    let contracts = globSync(workdir + '**/Move.toml');

    const modules = new Set();
    for (const contract of contracts) {
        const moduleName = parseModule(contract);
        if (args.length === 2) {
            // Flexible matching: handle kebab-case vs camelCase
            const normalizeModuleName = (name) => name.toLowerCase().replace(/[-_]/g, '');
            const normalizedModuleName = normalizeModuleName(moduleName);

            if (moduleNames.some((name) => normalizeModuleName(name) === normalizedModuleName)) {
                modules.add(moduleName);
            }
        } else {
            modules.add(moduleName);
        }
    }

    console.time(taskType);
    const compiles = [];
    console.log(`modules: ${Array.from(modules).join(', ')}`);

    for (const module of modules) {
        if (taskType === 'test') {
            await test(module);
        } else {
            compiles.push(compile(module));
        }
    }

    await Promise.all(compiles);
    console.timeEnd(taskType);
}

(async () => {
    await main();
})();
