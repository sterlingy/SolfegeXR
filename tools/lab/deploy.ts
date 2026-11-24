#!/usr/bin/env bun
import { spawnSync } from "node:child_process";
import { access, lstat, mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

const excluded = new Set([".git", "node_modules", ".env", ".cache", "backups", "data"]);
function skip(name: string): boolean {
  return excluded.has(name) || name.startsWith(".env.");
}
function run(command: string, args: string[], capture = false): string {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio: capture ? "pipe" : "inherit",
  });
  if (result.error || result.status !== 0) throw new Error(`${command} failed`);
  return result.stdout?.trim() ?? "";
}
async function inspect(path: string): Promise<void> {
  const stat = await lstat(path);
  if (
    stat.isSymbolicLink() ||
    (!stat.isFile() && !stat.isDirectory()) ||
    (stat.isFile() && stat.nlink !== 1)
  )
    throw new Error(`unsupported source entry: ${path}`);
  if (stat.isDirectory())
    for (const name of await readdir(path)) if (!skip(name)) await inspect(join(path, name));
}
async function buildShell(): Promise<string> {
  if (process.platform === "win32") {
    const result = spawnSync("git", ["--exec-path"], { encoding: "utf8" });
    if (result.status === 0) {
      const executable = join(dirname(dirname(dirname(result.stdout.trim()))), "bin", "bash.exe");
      try {
        await access(executable);
        return executable;
      } catch {
        /* fall back to PATH */
      }
    }
  }
  const shell = Bun.which("bash");
  if (!shell)
    throw new Error("bash is required for the build; install Git Bash and add it to PATH");
  return shell;
}
async function main(): Promise<void> {
  const cwd = process.cwd();
  const manifest = JSON.parse(await readFile(join(cwd, "sterlings-app.json"), "utf8")) as {
    slug?: unknown;
    type?: unknown;
    build?: unknown;
  };
  if (
    typeof manifest.slug !== "string" ||
    !/^[a-z0-9][a-z0-9-]{1,26}$/.test(manifest.slug) ||
    ["hub", "api", "healthz", "apps"].includes(manifest.slug)
  )
    throw new Error("invalid app slug");
  if (!["static", "server", "hybrid"].includes(String(manifest.type)))
    throw new Error("invalid app type");
  if (
    manifest.build !== undefined &&
    (typeof manifest.build !== "string" || [...manifest.build].some((c) => c.charCodeAt(0) < 32))
  )
    throw new Error("invalid build command");
  const host = process.env.STERLINGS_HOST ?? "sterling.shivoolabs.com";
  const user = process.env.STERLINGS_SSH_USER ?? "deploy";
  const key = process.env.STERLINGS_SSH_KEY;
  if (
    !/^[A-Za-z0-9][A-Za-z0-9.-]*$/.test(host) ||
    !/^[a-z_][a-z0-9_-]*$/.test(user) ||
    !key ||
    key.startsWith("-")
  )
    throw new Error("invalid host, user, or STERLINGS_SSH_KEY");
  if (manifest.build) run(await buildShell(), ["-c", manifest.build]);
  await inspect(cwd);
  const temp = await mkdtemp(join(tmpdir(), "sterlings-deploy-"));
  const ssh = ["-i", resolve(key), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"];
  const target = `${user}@${host}`;
  let remote = "";
  try {
    const archive = join(temp, "app.tar.gz");
    run("tar", [
      "--format=ustar",
      "-czf",
      archive,
      ...[...excluded].flatMap((name) => ["--exclude", name]),
      "--exclude",
      ".env.*",
      "-C",
      cwd,
      ".",
    ]);
    let commit = "";
    const status = spawnSync("git", ["status", "--porcelain"], { encoding: "utf8" });
    if (status.status === 0 && !status.stdout.trim()) {
      const sha = run("git", ["rev-parse", "HEAD"], true);
      if (/^[a-f0-9]{40}$/i.test(sha)) commit = ` --commit ${sha}`;
    }
    remote = run(
      "ssh",
      [...ssh, target, "umask 077; mktemp -d /tmp/sterlings-deploy.XXXXXXXX"],
      true,
    );
    if (!/^\/tmp\/sterlings-deploy\.[A-Za-z0-9]{8}$/.test(remote))
      throw new Error("invalid remote temporary directory");
    run("scp", [...ssh, archive, `${target}:${remote}/app.tar.gz`]);
    run("ssh", [
      ...ssh,
      target,
      `sudo /usr/local/bin/labctl app register --slug ${manifest.slug} --archive ${remote}/app.tar.gz --deploy-mode external${commit}`,
    ]);
    console.log(`Deployed https://${host}/apps/${manifest.slug}/ (host registration completed)`);
  } finally {
    if (/^\/tmp\/sterlings-deploy\.[A-Za-z0-9]{8}$/.test(remote)) {
      try {
        run("ssh", [...ssh, target, `rm -rf -- ${remote}`]);
      } catch {
        console.error("Could not clean remote temporary directory");
      }
    }
    await rm(temp, { recursive: true, force: true });
  }
}
main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : "deploy failed");
  process.exitCode = 1;
});
