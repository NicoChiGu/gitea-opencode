import { spawn } from "node:child_process";

export function spawnFile(command, args = [], options = {}) {
  return new Promise((resolve, reject) => {
    const startedAt = Date.now();
    let heartbeat = null;
    const child = spawn(command, args, {
      cwd: options.cwd || process.cwd(),
      env: options.env || process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      if (options.streamStdout) process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
      if (options.streamStderr) process.stderr.write(chunk);
    });
    if (options.heartbeatLabel) {
      const intervalMs = options.heartbeatIntervalMs || 30000;
      heartbeat = setInterval(() => {
        const seconds = Math.floor((Date.now() - startedAt) / 1000);
        console.log(`[gitea-opencode] ${options.heartbeatLabel} still running (${seconds}s elapsed)`);
      }, intervalMs);
    }
    child.on("error", (error) => {
      if (heartbeat) clearInterval(heartbeat);
      reject(error);
    });
    child.on("close", (code) => {
      if (heartbeat) clearInterval(heartbeat);
      if (code === 0) {
        resolve({ stdout, stderr, code });
      } else {
        const error = new Error(`${command} ${args.join(" ")} failed with exit code ${code}\n${stderr}`.trim());
        error.stdout = stdout;
        error.stderr = stderr;
        error.code = code;
        reject(error);
      }
    });
  });
}
