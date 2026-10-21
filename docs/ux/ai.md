# AI chat — UX brief (card W28-ai, roadmap v0.3 "LLM chat (multi-provider, libsecret)")

A chat with a language model, local first: the user's own Ollama server by default, an OpenAI-compatible server or
Anthropic when the user sets one up. A native mod (`mods/ai`, crate `kurashi-mod-ai`): the daemon talks to the
provider, keeps the conversations and streams the answer into the document; the Stage panel `panel:ai` draws it.
Not a sidebar (I116: sidebars are discussed with the user first).

## Job
Ask a quick question without opening a browser tab or a terminal — "what is the jq for this", "translate this
sentence", "explain this error" — read the answer as it is written, copy the code out of it, come back to it later.

## How others do it
- **ii (end-4)** `services/Ai.qml`, `services/ai/*ApiStrategy.qml`, `modules/ii/sidebarLeft/aiChat/*`: the left
  sidebar; Ollama models found by a script, OpenAI/Gemini/Mistral strategies; one `curl` per request, SSE or NDJSON
  lines parsed in QML; keys in the keyring (`KeyringStorage`). The view splits a message into text, code and think
  blocks (`StringUtils.splitMarkdownBlocks`: ```` ```lang ```` fences and `<think>`), each code block with a language
  label and a copy button, a think block folded; per-message copy and "view Markdown source"; `/model`, `/clear`
  commands in the input. **Taken:** the block split (here in Rust, with open fences while streaming), reasoning deltas
  (`delta.reasoning`/`reasoning_content`) shown as a think block, the copy buttons. **Not taken:** the logic in QML, a
  shell (`curl`) per request.
- **shellseikatsu** `Services/LlmService.qml`: a provider registry by wire format (`ollama` NDJSON on `/api/chat`,
  `openai` SSE on `/chat/completions`, `anthropic` SSE events on `/v1/messages`), the model list from `/api/tags`, the
  key from an env var (never on a command line), errors described from the body (`error.message`, `error`, the raw
  text), the session saved as JSON. **Taken:** the three formats and their parsers, the key rule (env var), the error
  description. **Added:** `secret-tool lookup` (libsecret) as the other key source.
- **Alpaca** (GNOME, Ollama client), **Open WebUI**: a chat list on the side, a model picker at the top, stop and
  regenerate on the last answer, a clear "Ollama is not running" page with what to do.
- **Windows Copilot**, **macOS** (Siri/ChatGPT): a system-wide entry from the keyboard; cloud only, which the user is
  told. **Taken:** the launcher entry (`!` + question, contract row 220) and the honest "your messages leave this
  computer" line for cloud providers.
- **GNOME, KDE, COSMIC, Caelestia, DankMaterialShell, Noctalia, HyprPanel**: no built-in chat (plugins or apps).

## Fit (what runs where)
- **Daemon** (`kurashi-mod-ai`): the provider requests on a blocking thread (ureq, rustls), the stream parsers, the
  key lookup, the block split, the conversations under `$XDG_DATA_HOME/kurashi/ai/conversations/<id>.json`, the copy
  (`wl-copy`). Document `mod.ai`, actions `ai.*`.
- **Frontend**: `qml/Panel.qml` (Stage card, 560 px) draws the document and sends intents. No parsing, no requests.
- **Launcher**: `!` + text asks and opens the panel — needs a mod launcher contribution (contract row 220); until then
  the panel is opened from a key binding or `kurashi act mod.panel.open '{"id":"ai","panel":"ai"}'`.

## Design
- **Header:** the conversation's title (or "New chat"); buttons: history, new chat. Under it the model chip
  ("Ollama · llama3.2"): a click lists the models (`ai.models`, fetched then and only then) and picks one (`ai.model`,
  a settings write of the provider's model key — undoable, shown with provenance in Settings).
- **History** (toggled): the saved conversations, newest first, title + relative day; Return opens, Delete removes.
- **Messages:** the user's on the right in a tonal bubble; the answer on the left, full width, as blocks: Markdown
  text, code (monospace on the surface colour, the language and a copy button in its header), think (dim, folded to
  one line with a toggle). Under the last answer: copy, regenerate; a stopped answer says "Stopped".
- **Streaming:** the answer grows in place, at most 10 document patches a second (the daemon buffers); a "Thinking…"
  line until the first text. The send button becomes Stop.
- **Composer:** a multi-line field at the bottom (Return sends, Shift+Return breaks the line), the send button.

## States
| State | Shown |
|---|---|
| empty (no message) | "Ask anything", the provider line ("Answers come from Ollama on this computer" / "… from OpenAI — your messages leave this computer"), the field focused |
| loading (no document yet) | "Loading…" |
| streaming | the growing answer, Stop |
| stopped | the partial answer + "Stopped", Regenerate |
| unreachable | an error bubble: "Ollama does not answer at http://127.0.0.1:11434. Start it with `ollama serve`." + Retry |
| no key | "No API key: set OPENAI_API_KEY or a secret-tool entry (Settings › AI)" + Retry |
| no model | "No model is installed in Ollama (`ollama pull llama3.2`)" / "Choose a model" for the others |
| provider error | the provider's own message (HTTP status + `error.message`), + Retry |
| models loading / failed | in the picker: "Loading models…" / the reason |
| offline | the same as unreachable (the request fails); nothing is sent while no one asks |

## Keyboard and a11y
Tab order: header buttons, model chip, messages (each a list item; Ctrl+C on a focused answer copies it), composer.
Return sends, Shift+Return new line, Escape in the field stops a reply, else closes the card (the Stage's). The
history list is navigable with arrows and Return; Delete removes. Every button has an accessible name; the streaming
answer is not announced token by token (the list item's name is set when the answer settles).

## Motion
None of its own: the Stage card's reveal only. No caret blink, no typing animation (Ma: nothing animates while text
arrives; the patch rate is the motion).

## Multi-output
The Stage card opens on the focused output, as every Stage panel.

## Budget
0 frames and 0 requests while the panel is closed and nothing is being answered. No model-list polling: the list is
fetched when the picker opens. A reply in flight continues while the panel is closed (it is saved when done).
≤ 10 patches/s while streaming. Conversations: JSON files, `history` newest kept (default 50).

## Keys and privacy
API keys are never stored in `config.toml` (I134): the settings name an **environment variable** (`OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`) or **secret-tool attributes** (`service openai`: `secret-tool lookup service openai`, stored
with `secret-tool store --label=… service openai`). The key is looked up at each request, held only for it, never
written to the document, a log or an error. Conversations stay on this computer; `history = 0` saves none.

## Definition of done
Crate tests (Ollama NDJSON, OpenAI SSE, Anthropic SSE parsing; the block split; key lookup without the key in any
output), clippy; `mods/ai/test-ai.sh` (real kurashid, a fake Ollama on localhost) with shots of the panel — empty,
streaming, code block, error — under sekai and none; en + ja strings.

## Later (backlog)
Attachments and images, tool calls, a system prompt per conversation, editing a sent message, search in the history,
the launcher `!` mode (row 220), a mono font token (row 221).
