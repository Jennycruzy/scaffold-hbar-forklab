import { readFile } from "node:fs/promises";
import { z } from "zod";

// Kept structurally identical to TemplateManifestSchema in create-scaffold-hbar/src/types.ts.
const capabilities = z.object({
  frontend: z.array(z.enum(["nextjs-app", "none"])).optional(),
  solidityFramework: z.array(z.enum(["hardhat", "foundry", "none"])).optional(),
  packageManager: z.array(z.enum(["yarn", "npm", "none"])).optional(),
});
const defaults = z.object({
  frontend: z.enum(["nextjs-app", "none"]).optional(),
  solidityFramework: z.enum(["hardhat", "foundry", "none"]).optional(),
  packageManager: z.enum(["yarn", "npm", "none"]).optional(),
});
const outroStep = z
  .object({
    label: z.string().min(1).optional(),
    command: z.string().min(1).optional(),
    url: z.string().min(1).optional(),
    text: z.string().min(1).optional(),
  })
  .refine(step => step.label || step.command || step.url || step.text, {
    message: "Each outro step must include at least one of 'label', 'command', 'url', or 'text'.",
  });
const outro = z
  .object({
    sections: z
      .array(z.object({ title: z.string().min(1).optional(), steps: z.array(outroStep).min(1) }))
      .min(1)
      .optional(),
    steps: z.array(z.string().min(1)).min(1).optional(),
    installCommand: z.string().min(1).optional(),
  })
  .refine(value => value.sections || value.steps || value.installCommand, {
    message: "Template outro must define at least one of 'sections', 'steps', or 'installCommand'.",
  });
const manifestBlock = z.object({
  rename: z
    .record(z.string(), z.object({ to: z.string().min(1), paths: z.array(z.string().min(1)).min(1) }))
    .optional(),
  instructions: z.array(z.string()).optional(),
  requirements: z.record(z.string(), z.string()).optional(),
  envVars: z.array(z.object({ key: z.string().min(1), description: z.string() })).optional(),
  capabilities: capabilities.optional(),
  defaults: defaults.optional(),
  outro: outro.optional(),
});
const TemplateManifestSchema = z.preprocess(
  raw => {
    if (!raw || typeof raw !== "object") return raw;
    const normalized = { ...raw };
    if ("create-hbar" in normalized) {
      if (!("create-scaffold-hbar" in normalized)) {
        normalized["create-scaffold-hbar"] = normalized["create-hbar"];
      }
      delete normalized["create-hbar"];
    }
    return normalized;
  },
  z.object({
    name: z.string().min(1),
    description: z.string().optional(),
    version: z.string().optional(),
    "create-scaffold-hbar": manifestBlock.optional(),
  }),
);

const manifest = JSON.parse(await readFile(new URL("../template.json", import.meta.url), "utf8"));
TemplateManifestSchema.parse(manifest);
console.log("template.json: valid TemplateManifestSchema");
