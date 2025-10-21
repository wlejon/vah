# Model Adapter System

## Purpose

Create a modular system for integrating different language models into VAH's Manufold agent system. Each model may use different formats for tool calling (Harmony format for gpt-oss-20b, function calling for GPT-4, different formats for Claude, Llama, etc.). This system standardizes how VAH exposes its capabilities to any model.

## Core Concept

Think of this as a "driver" system:
- **Device** = Language model (gpt-oss-20b, GPT-4, Claude, Llama, etc.)
- **Standard Interface** = VAH's tool system (file operations, database, HTTP, etc.)
- **Driver** = Model-specific adapter that translates between model format and VAH tools

## Architecture Goals

### 1. Model-Agnostic Tool Definitions

VAH defines tools once in a neutral format:
- Tool name
- Description
- Parameters (name, type, required/optional, description)
- Return value description

### 2. Model-Specific Adapters

Each adapter handles:
- **System Prompt Generation** - Convert tool definitions to model's expected format
- **Lexing** - Tokenize model responses into structured tokens
- **Parsing** - Extract tool calls from token stream
- **Response Formatting** - Format tool results to send back to model

### 3. Separation of Concerns

- **Agent Logic** (model-agnostic) - Workflow states, comprehension validation, schema design
- **Tool Execution** (model-agnostic) - File operations, database queries, HTTP requests
- **Model Adapter** (model-specific) - Translation layer between agent and model

## Implementation Requirements

### Lexer Design

Each model adapter must provide a character-level lexer that:
- Does NOT use regex or pattern matching
- Tokenizes input character by character
- Produces a stream of typed tokens
- Handles all syntactic elements of the model's format

Example token types for Harmony:
- `TOKEN` - Special tokens like `start`, `channel|`, `message`, etc.
- `IDENTIFIER` - Names like `functions`, `list_files`, `commentary`
- `DOT` - The `.` separator
- `EQUALS` - The `=` in attributes
- `WHITESPACE` - Spaces, newlines
- `LBRACE`, `RBRACE` - JSON structure
- `STRING` - Quoted strings
- `NUMBER` - Numeric literals
- `TEXT` - Everything else

### Parser Design

The parser consumes tokens and:
- Builds an abstract representation (AST or similar)
- Identifies tool calls from structure
- Extracts tool names and arguments
- Does NOT make assumptions about content format

Example parsing for Harmony:
1. Walk tokens looking for `TOKEN(channel)`
2. Verify next is `IDENTIFIER(commentary)` or similar
3. Parse attributes to find `to=QUALIFIED_NAME`
4. Split qualified name on `DOT` token
5. Find `TOKEN(message)`
6. Parse JSON tokens until next control token
7. Return structured tool call object

### Tool Modes

Tools are organized into "modes" that provide enhanced capabilities:

**File Mode**
- Read/write operations
- Directory traversal
- File metadata
- Content type detection

**Web Mode**
- URL fetching
- HTML stripping and cleaning
- Link extraction
- Content summarization (via sub-model call)
- Screenshot capture (future)

**Database Mode**
- Schema inspection
- Query execution
- Transaction support
- Result formatting

**Execution Mode**
- Safe sandboxed code execution
- Output capture
- Timeout handling
- Resource limits

Each mode can have sub-agents or sub-models to handle complex operations (e.g., web mode sends scraped HTML to a smaller model to extract key information).

## Adapter Interface

Each model adapter must implement:

### `generate_system_prompt(tools, workflow_state) -> string`
Converts tool definitions and current workflow context into the model's system prompt format.

### `tokenize(response_text) -> tokens[]`
Character-level lexer that produces typed tokens from model response.

### `parse_tool_calls(tokens) -> tool_calls[]`
Parser that extracts tool call objects from token stream.

### `format_tool_results(results) -> string`
Formats tool execution results to send back to the model.

## Why This Matters

### Problem Being Solved

Different models have fundamentally different approaches to tool calling:
- Some use special tokens (Harmony format)
- Some use JSON function calling syntax
- Some use XML-like tags
- Some use natural language descriptions

Without a modular system:
- Tool definitions must be duplicated per model
- Parsing logic becomes intertwined with agent logic
- Adding new models requires touching core agent code
- Can't compare model effectiveness easily

### Solution Benefits

With model adapters:
- Add new models by implementing one adapter
- Agent code remains clean and model-agnostic
- Can A/B test different models without code changes
- Tools are defined once, translated many times
- Easy to debug model-specific issues in isolation

## Design Principles

1. **No Regex in Parsers** - Character-level processing only, for clarity and maintainability
2. **Separation of Syntax and Semantics** - Lexer knows syntax, parser knows structure, agent knows meaning
3. **Explicit Over Implicit** - Make all assumptions visible in code
4. **Fail Gracefully** - Bad tokens or parse failures should not crash the agent
5. **Debuggability** - Every step should be loggable and inspectable

## Future Considerations

### Multi-Model Workflows

Agent might use different models for different tasks:
- Fast small model for simple tool calls
- Larger model for complex reasoning
- Specialized model for code generation

### Model Capabilities

Adapters might declare capabilities:
- Supports streaming responses
- Supports vision/images
- Max context window
- Cost per token
- Latency characteristics

### Adapter Registry

Central registry of available adapters:
- Discovery at runtime
- Version compatibility
- Feature flags
- Performance metrics

## Current Implementation: Harmony Adapter

The first adapter implements support for gpt-oss-20b's Harmony format. This serves as the reference implementation showing:
- How to lex special control tokens
- How to parse structured attributes
- How to extract qualified function names
- How to handle JSON arguments
- How to send results back in a format the model understands

Future adapters will follow this pattern but implement different lexing/parsing rules for their respective model formats.
