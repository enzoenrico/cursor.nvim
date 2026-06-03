#!/usr/bin/env node
import { Agent } from "@cursor/sdk";

function readArgs(argv) {
  const out = {
    modelParams: [],
    runtime: "local",
    apiKeyEnv: "CURSOR_API_KEY",
    workspace: process.cwd(),
    mode: "agent",
    force: false,
    prompt: "",
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => argv[++i];
    if (arg === "-p" || arg === "--prompt") out.prompt = next() || "";
    else if (arg === "--runtime") out.runtime = next() || out.runtime;
    else if (arg === "--api-key-env") out.apiKeyEnv = next() || out.apiKeyEnv;
    else if (arg === "--workspace") out.workspace = next() || out.workspace;
    else if (arg === "--model") out.model = next();
    else if (arg === "--model-param") out.modelParams.push(next());
    else if (arg === "--mode") out.mode = next() || out.mode;
    else if (arg === "--force") out.force = true;
  }
  return out;
}

function modelSelection(opts) {
  if (!opts.model) return undefined;
  const params = opts.modelParams
    .map((entry) => {
      const [id, ...rest] = String(entry || "").split("=");
      const value = rest.join("=");
      return id && value ? { id, value } : undefined;
    })
    .filter(Boolean);
  return { id: opts.model, params: params.length ? params : undefined };
}

function writeEvent(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

async function main() {
  const opts = readArgs(process.argv.slice(2));
  if (!opts.prompt) throw new Error("cursor-sdk-bridge requires -p <prompt>");
  const apiKey = process.env[opts.apiKeyEnv];
  if (!apiKey) throw new Error(`${opts.apiKeyEnv} is not set`);
  if (opts.runtime !== "local") {
    throw new Error("cursor-sdk-bridge currently supports local SDK agents only");
  }

  const agent = await Agent.create({
    apiKey,
    model: modelSelection(opts),
    mode: opts.mode,
    local: { cwd: opts.workspace, force: opts.force },
  });

  writeEvent({
    type: "agent_created",
    agent_id: agent.agentId,
    model: agent.model,
  });

  const run = await agent.send(opts.prompt, {
    mode: opts.mode,
    model: modelSelection(opts),
    local: { force: opts.force },
  });

  for await (const event of run.stream()) {
    writeEvent(event);
  }

  const result = await run.wait();
  if (result.result) {
    writeEvent({
      type: "assistant",
      agent_id: run.agentId,
      run_id: run.id,
      message: { role: "assistant", content: [{ type: "text", text: result.result }] },
    });
  }
  agent.close();
  if (result.status !== "finished") {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
  process.exitCode = 1;
});
