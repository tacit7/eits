# Context Window Calculation

How the DM page calculates and displays context window usage.

## Data Sources

Context is extracted from the most recent message in the session that contains usage data. Two message formats are handled:

### Claude CLI (camelCase)

Messages with `metadata.model_usage` — a map keyed by model name (e.g. `"claude-opus-4-6"`):

```json
{
  "model_usage": {
    "claude-opus-4-6": {
      "inputTokens": 23,
      "cacheReadInputTokens": 584482,
      "cacheCreationInputTokens": 33263,
      "contextWindow": 200000
    }
  }
}
```

`contextWindow` comes from the CLI response. Falls back to `200_000` if absent.

### Anubis / Streaming (snake_case)

Messages with `metadata.usage`:

```json
{
  "usage": {
    "input_tokens": 1,
    "cache_read_input_tokens": 49383,
    "cache_creation_input_tokens": 166
  }
}
```

Context window is hardcoded to `200_000` — Anubis does not report it.

## Calculation

```
used = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
remaining = max(0, context_window - used)
pct = remaining / context_window * 100
```

`remaining` is clamped to `0` because `cache_read_input_tokens` can exceed `context_window` in practice (e.g. session 773: 584k cache reads vs 200k window), which would otherwise produce a negative display.

## Display

Rendered in `dm_page.ex` in the message toolbar:

| pct         | Color                     |
|-------------|---------------------------|
| > 40%       | `text-base-content/30`    |
| 20% – 40%   | `text-warning/70`         |
| < 20%       | `text-error/70`           |

Tooltip shows: `{remaining} / {context_window} tokens remaining`.

Hidden entirely when `context_window == 0` (no usage data yet).

## Source Files

- Extraction: `lib/eye_in_the_sky_web_web/live/dm_live.ex` — `extract_context_window/1` (~line 818)
- Display: `lib/eye_in_the_sky_web_web/components/dm_page.ex` (~line 1040)
