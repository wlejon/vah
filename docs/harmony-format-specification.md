# Harmony Response Format Specification

## Overview

The Harmony format is used by OpenAI's gpt-oss-20b model for structured communication, including tool calling and multi-channel responses.

## Token Structure

Harmony uses special control tokens enclosed in `<|` and `|>`:

### Core Tokens

- `<|start|>` - Begin message header
- `<|end|>` - End message
- `<|message|>` - Content start marker
- `<|channel|>` - Channel specification
- `<|constrain|>` - Type constraint (e.g., json, text)
- `<|return|>` - Complete response marker
- `<|call|>` - Tool invocation marker

### Message Structure

A complete Harmony message follows this pattern:

```
<|start|>ROLE<|channel|>CHANNEL_NAME ATTRIBUTES<|constrain|>FORMAT<|message|>CONTENT<|end|>
```

Where:
- `ROLE` = "assistant", "user", "system", or tool name
- `CHANNEL_NAME` = "analysis", "commentary", or "final"
- `ATTRIBUTES` = optional key=value pairs (e.g., "to=recipient")
- `FORMAT` = "json", "text", or other constraint types
- `CONTENT` = the actual message content

### Tool Call Pattern

When the model wants to call a tool:

```
<|start|>assistant<|channel|>commentary to=RECIPIENT<|constrain|>json<|message|>JSON_ARGS<|call|>
```

Example:
```
<|start|>assistant<|channel|>commentary to=functions.list_files <|constrain|>json<|message|>{"path":""}<|call|>
```

Key observations:
- Tool calls use the "commentary" channel
- Recipient is specified with `to=` attribute
- Function names follow pattern: `functions.FUNCTION_NAME`
- Arguments are JSON in the message content
- Ends with `<|call|>` instead of `<|end|>`

### Channel Types

1. **analysis** - Internal reasoning (not shown to user)
2. **commentary** - Tool calls and visible preambles
3. **final** - Consolidated user-facing response

### System Prompt Format

Tools must be defined in the system message using this structure:

```
<|start|>system<|message|>You are an AI assistant.
Knowledge cutoff: YYYY-MM-DD
Current date: YYYY-MM-DD
Reasoning: high|medium|low

# Tools

## functions.TOOL_NAME
Description of the tool.

Parameters:
- param_name (type, required/optional): Description

Returns: Description of return value.

## functions.ANOTHER_TOOL
...

<|end|>
```

## Lexical Elements

### Identifiers
- Start with letter or underscore
- Contain letters, digits, underscores
- Examples: `functions`, `list_files`, `commentary`

### Attributes
- Format: `KEY=VALUE`
- Appear after channel name
- Space-separated
- Examples: `to=functions.list_files`, `format=json`

### Qualified Names
- Format: `NAMESPACE.NAME`
- Examples: `functions.list_files`, `functions.read_file`
- Namespace indicates the tool category

### JSON Content
- Appears after `<|message|>` token
- Must be valid JSON when `<|constrain|>json` is present
- Can be empty object `{}`
- Can contain nested structures

## Response Flow

1. Model emits analysis (optional)
2. Model emits tool call(s) if needed
3. Tool results are sent back to model
4. Model emits final response

Example conversation flow:

```
User: "List the files"

Assistant Analysis (internal):
<|start|>assistant<|channel|>analysis<|message|>Need to call list_files<|end|>

Assistant Tool Call:
<|start|>assistant<|channel|>commentary to=functions.list_files<|constrain|>json<|message|>{"path":""}<|call|>

Tool Response (sent back to model):
Tool Results:
- list_files: [{"name":"file1.md","type":".md"}]

Assistant Final:
<|start|>assistant<|channel|>final<|message|>Here are the files: file1.md<|return|>
```

## Important Notes

- The model outputs the entire token structure as text
- Tokens are NOT stripped by the API - they appear in `message.content`
- Multiple messages can appear in one response
- Not all messages will have all tokens (some may omit `<|constrain|>`, etc.)
- The `<|call|>` token indicates a tool call rather than `<|end|>`
- Spaces matter in attribute parsing (e.g., `to=functions.list_files ` has trailing space)
