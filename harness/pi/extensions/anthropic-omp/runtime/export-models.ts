import { getBundledModels } from "@oh-my-pi/pi-catalog/models";
import { getSupportedEfforts } from "@oh-my-pi/pi-catalog/model-thinking";
import { THINKING_EFFORTS } from "@oh-my-pi/pi-catalog/effort";

const models = getBundledModels("anthropic").filter(model => model.api === "anthropic-messages").map(model => {
  if (!model.contextWindow || !model.maxTokens) throw new Error(`Missing limits: ${model.id}`);
  const efforts = getSupportedEfforts(model);
  return {
    id: model.id, name: model.name, api: "anthropic-messages", provider: "anthropic-omp",
    baseUrl: model.baseUrl, reasoning: model.reasoning, input: model.input,
    cost: model.cost, contextWindow: model.contextWindow, maxTokens: model.maxTokens,
    thinkingLevelMap: Object.fromEntries(THINKING_EFFORTS.map(effort => [effort, efforts.includes(effort) ? effort : null])),
  };
});
await Bun.write(new URL("../models.json", import.meta.url), JSON.stringify(models, null, 2) + "\n");
