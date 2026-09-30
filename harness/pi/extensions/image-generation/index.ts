/**
 * Image generation tool for pi, ported from Codex's `ext/image-generation` extension
 * (reference/codex @ 26dd19ef, codex-rs/ext/image-generation/src/tool.rs).
 *
 * Auth, in order:
 *   1. pi's `openai-codex` ChatGPT OAuth login -> https://chatgpt.com/backend-api/codex/images/*
 *      (the same backend Codex uses with ChatGPT auth; counts against the ChatGPT plan's image quota)
 *   2. OPENAI_API_KEY -> https://api.openai.com/v1/images/* (billed to the API key)
 *
 * Images are saved to ~/.pi/agent/generated_images/<session-id>/<tool-call-id>.png.
 */
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { extname, isAbsolute, join, resolve } from "node:path";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

const IMAGE_MODEL = "gpt-image-2";
const MAX_EDIT_IMAGES = 5;
const MAX_INPUT_IMAGE_BYTES = 32 * 1024 * 1024;
const REQUEST_TIMEOUT_MS = 5 * 60_000;
const CODEX_BASE_URL = "https://chatgpt.com/backend-api/codex";
const OPENAI_BASE_URL = "https://api.openai.com/v1";
const JWT_CLAIM_PATH = "https://api.openai.com/auth";

const MIME_BY_EXT: Record<string, string> = {
	".png": "image/png",
	".jpg": "image/jpeg",
	".jpeg": "image/jpeg",
	".webp": "image/webp",
	".gif": "image/gif",
};

const DESCRIPTION = `Generate a new image from a description, or edit existing images based on specific instructions. Use it when:
- The user requests an image based on a scene description, such as a diagram, portrait, comic, meme, or any other visual.
- The user wants to modify an attached or previously generated image with specific changes, including adding or removing elements, altering colors, improving quality/resolution, or transforming the style (e.g., cartoon, oil painting).

Guidelines:
- imagegen can take a few minutes to finish.
- Set \`transparent_background\` to true when the request calls for a transparent background, including background removal or a cutout; set it to false otherwise. For edits, preserve existing transparency unless the user asks to change it.
- Omit both \`referenced_image_paths\` and \`num_last_images_to_include\` when generating a brand new image.
- For edits, use \`referenced_image_paths\` (absolute paths) when every target image has a local file path.
- If you have not seen a local image yet, use \`read\` to inspect it before editing.
- Use \`num_last_images_to_include\` only when at least one target image has no local file path.
- Set \`num_last_images_to_include\` to the smallest number of recent conversation images that includes every target image, up to 5.
- Never provide both \`referenced_image_paths\` and \`num_last_images_to_include\`.
- If neither mechanism can include every target image, ask the user to attach the missing images again.
- Directly generate the image without reconfirmation or clarification unless required images must be attached again.
- Always use this tool for image editing unless the user explicitly requests otherwise.`;

type ImageRef = { image_url: string };
type Backend = { name: "chatgpt" | "openai-api"; baseUrl: string; headers: Record<string, string> };
type ImageResponse = {
	background?: "transparent" | "opaque" | "auto";
	data?: { b64_json?: string; revised_prompt?: string; generation_id?: string }[];
};
export type ImagegenDetails = {
	status: "completed";
	backend: Backend["name"];
	mode: "generate" | "edit";
	prompt: string;
	savedPath?: string;
	transparentBackground?: boolean;
	revisedPrompt?: string;
	imagegenRequestId?: string;
};

function accountIdFromJwt(token: string): string | undefined {
	try {
		const payload = JSON.parse(Buffer.from(token.split(".")[1] ?? "", "base64url").toString("utf8"));
		return payload?.[JWT_CLAIM_PATH]?.chatgpt_account_id;
	} catch {
		return undefined;
	}
}

async function resolveBackend(ctx: ExtensionContext): Promise<Backend> {
	const token = await ctx.modelRegistry.getApiKeyForProvider("openai-codex");
	const accountId = token ? accountIdFromJwt(token) : undefined;
	if (token && accountId) {
		return {
			name: "chatgpt",
			baseUrl: CODEX_BASE_URL,
			headers: { Authorization: `Bearer ${token}`, "chatgpt-account-id": accountId, originator: "pi" },
		};
	}
	const apiKey = process.env.OPENAI_API_KEY;
	if (apiKey) return { name: "openai-api", baseUrl: OPENAI_BASE_URL, headers: { Authorization: `Bearer ${apiKey}` } };
	throw new Error("imagegen needs a ChatGPT login (`/login` -> openai-codex) or OPENAI_API_KEY.");
}

function sanitize(value: string): string {
	return value.replace(/[^A-Za-z0-9_-]/g, "_") || "generated_image";
}

function sniffMime(bytes: Buffer, path: string): string | undefined {
	if (bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "image/png";
	if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
	if (bytes.subarray(0, 4).toString("ascii") === "RIFF" && bytes.subarray(8, 12).toString("ascii") === "WEBP") return "image/webp";
	if (bytes.subarray(0, 4).toString("ascii") === "GIF8") return "image/gif";
	return MIME_BY_EXT[extname(path).toLowerCase()];
}

async function imageFromPath(path: string, cwd: string): Promise<ImageRef> {
	const absolute = isAbsolute(path) ? path : resolve(cwd, path);
	let bytes: Buffer;
	try {
		bytes = await readFile(absolute);
	} catch (error) {
		throw new Error(`unable to read referenced image at \`${absolute}\`: ${(error as Error).message}`);
	}
	if (bytes.length > MAX_INPUT_IMAGE_BYTES) throw new Error(`referenced image at \`${absolute}\` exceeds 32 MiB`);
	const mime = sniffMime(bytes, absolute);
	if (!mime) throw new Error(`unable to process referenced image at \`${absolute}\`: unsupported image format`);
	return { image_url: `data:${mime};base64,${bytes.toString("base64")}` };
}

/** Collects the newest `count` images from the active branch, returned oldest-first (Codex `recent_images`). */
function recentImages(ctx: ExtensionContext, count: number): ImageRef[] {
	const images: ImageRef[] = [];
	const branch = ctx.sessionManager.getBranch();
	outer: for (let i = branch.length - 1; i >= 0; i--) {
		const entry = branch[i] as { type: string; message?: { role?: string; content?: unknown } };
		if (entry.type !== "message" || !entry.message) continue;
		const { role, content } = entry.message;
		if ((role !== "user" && role !== "toolResult") || !Array.isArray(content)) continue;
		for (let j = content.length - 1; j >= 0; j--) {
			const part = content[j] as { type?: string; data?: string; mimeType?: string };
			if (part?.type !== "image" || !part.data) continue;
			images.push({ image_url: `data:${part.mimeType || "image/png"};base64,${part.data}` });
			if (images.length === count) break outer;
		}
	}
	if (images.length !== count) {
		throw new Error(`requested the last ${count} conversation images, but only ${images.length} were available`);
	}
	return images.reverse();
}

async function postImages(
	backend: Backend,
	path: "images/generations" | "images/edits",
	body: unknown,
	signal: AbortSignal | undefined,
): Promise<{ response: ImageResponse; requestId?: string }> {
	const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
	const res = await fetch(`${backend.baseUrl}/${path}`, {
		method: "POST",
		headers: { ...backend.headers, "Content-Type": "application/json", Accept: "application/json" },
		body: JSON.stringify(body),
		signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
	});
	const requestId = res.headers.get("x-codex-imagegen-request-id") || res.headers.get("x-request-id") || undefined;
	const text = await res.text();
	if (!res.ok) {
		let message = text.slice(0, 2000);
		try {
			const parsed = JSON.parse(text);
			message = parsed?.error?.message || parsed?.detail?.message || parsed?.detail || message;
		} catch {}
		const suffix = requestId ? ` (request id: ${requestId})` : "";
		throw new Error(`image generation failed: HTTP ${res.status}: ${typeof message === "string" ? message : JSON.stringify(message)}${suffix}`);
	}
	try {
		return { response: JSON.parse(text) as ImageResponse, requestId };
	} catch (error) {
		throw new Error(`failed to decode image response: ${(error as Error).message}`);
	}
}

const imagegenTool = defineTool({
	name: "imagegen",
	label: "Image Gen",
	description: DESCRIPTION,
	promptSnippet: "Generate or edit images (gpt-image) and save them as PNG files",
	parameters: Type.Object(
		{
			prompt: Type.String({ description: "Description of the image to generate, or the edit to apply." }),
			transparent_background: Type.Optional(
				Type.Boolean({ description: "Whether the output should have a transparent background. Defaults to false." }),
			),
			referenced_image_paths: Type.Optional(
				Type.Array(Type.String(), { maxItems: MAX_EDIT_IMAGES, description: "Absolute paths of local images to edit." }),
			),
			num_last_images_to_include: Type.Optional(
				Type.Integer({ minimum: 1, maximum: MAX_EDIT_IMAGES, description: "Number of most recent conversation images to edit." }),
			),
		},
		{ additionalProperties: false },
	),
	annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true },

	async execute(toolCallId, params, signal, onUpdate, ctx) {
		const paths = params.referenced_image_paths ?? [];
		const count = params.num_last_images_to_include;
		if (paths.length > MAX_EDIT_IMAGES) {
			throw new Error(`\`referenced_image_paths\` must contain at most ${MAX_EDIT_IMAGES} paths`);
		}
		if (paths.length > 0 && count !== undefined) {
			throw new Error("provide only one of `referenced_image_paths` or `num_last_images_to_include`");
		}
		if (count !== undefined && !(Number.isInteger(count) && count >= 1 && count <= MAX_EDIT_IMAGES)) {
			throw new Error(`\`num_last_images_to_include\` must be between 1 and ${MAX_EDIT_IMAGES}`);
		}

		const images =
			paths.length > 0
				? await Promise.all(paths.map((p) => imageFromPath(p, ctx.cwd)))
				: count !== undefined
					? recentImages(ctx, count)
					: undefined;
		const mode = images ? "edit" : "generate";
		const base = {
			prompt: params.prompt,
			background: params.transparent_background ? "transparent" : "opaque",
			model: IMAGE_MODEL,
			quality: "auto",
			size: "auto",
		};

		const backend = await resolveBackend(ctx);
		onUpdate?.({
			content: [{ type: "text", text: `${mode === "edit" ? "Editing" : "Generating"} image via ${backend.name}…` }],
			details: undefined as unknown as ImagegenDetails,
		});
		const { response, requestId } = images
			? await postImages(backend, "images/edits", { images, ...base }, signal)
			: await postImages(backend, "images/generations", base, signal);

		const first = response.data?.[0];
		const b64 = first?.b64_json?.trim();
		if (!b64) throw new Error(`image generation returned no image data${requestId ? ` (request id: ${requestId})` : ""}`);

		let savedPath: string | undefined;
		try {
			const dir = join(getAgentDir(), "generated_images", sanitize(ctx.sessionManager.getSessionId()));
			await mkdir(dir, { recursive: true });
			savedPath = join(dir, `${sanitize(toolCallId)}.png`);
			await writeFile(savedPath, Buffer.from(b64, "base64"), { flag: "wx" });
		} catch (error) {
			savedPath = undefined;
			if (ctx.hasUI) ctx.ui.notify(`imagegen: failed to save image: ${(error as Error).message}`, "warning");
		}

		const transparentBackground =
			response.background === "transparent" ? true : response.background === "opaque" ? false : undefined;
		const content: ({ type: "image"; data: string; mimeType: string } | { type: "text"; text: string })[] = [
			{ type: "image", data: b64, mimeType: "image/png" },
		];
		if (savedPath) {
			content.push({
				type: "text",
				text: `Generated image saved to ${savedPath}.\nIf you need to use it at another path, copy it and leave the original in place unless the user explicitly asks you to delete it.\nThe generated image is already displayed to the user. There is no need to render it in the final response as a Markdown image or file link.`,
			});
		}
		return {
			content,
			details: {
				status: "completed",
				backend: backend.name,
				mode,
				prompt: params.prompt,
				savedPath,
				transparentBackground,
				revisedPrompt: first?.revised_prompt,
				imagegenRequestId: requestId,
			} satisfies ImagegenDetails,
		};
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(imagegenTool);
}
