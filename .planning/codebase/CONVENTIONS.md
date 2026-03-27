# Coding Conventions

**Analysis Date:** 2026-03-27

## Naming Patterns

**Files:**
- Use `.test.ts` for test files
- Kebab-case for test files and component names
- Follows TypeScript naming conventions

**Functions:**
- camelCase for function names
- Descriptive, verb-first naming (e.g., `getEngineForUrl`)

**Variables:**
- camelCase
- Descriptive names that indicate purpose
- Avoid single-letter variables except in very short scopes

**Types:**
- PascalCase for type and interface names
- Descriptive, noun-based naming

## Code Style

**Formatting:**
- Tool: Prettier
- Key settings:
  - 2-space indentation
  - Trailing commas on all
  - Double quotes
  - 80 character print width
  - Semicolons required
  - LF line endings
  - Bracket spacing enabled
  - Arrow function parens avoided when possible

**Linting:**
- Implicit TypeScript/ESLint rules
- Focus on type safety and best practices

## Import Organization

**Order:**
1. External libraries/frameworks
2. Internal absolute imports
3. Relative imports
4. Type imports

**Path Aliases:**
- Uses TypeScript path aliases (detected in `tsconfig.json`)

## Error Handling

**Patterns:**
- Use of `try`/`catch` blocks
- Explicit error type definitions
- Logging and potential error propagation
- Graceful error handling in async functions

## Logging

**Framework:**
- Likely uses `console` for logging
- Potential custom logging utilities in `src/lib`

**Patterns:**
- Logging for debugging and tracking
- Likely environment-based logging levels

## Comments

**When to Comment:**
- Complex logic explanations
- Algorithm descriptions
- Explaining non-obvious code behavior
- TODO/FIXME markers for future improvements

**JSDoc/TSDoc:**
- Function and method documentation
- Type and interface descriptions
- Parameter and return value explanations

## Function Design

**Size:**
- Prefer smaller, focused functions
- Single Responsibility Principle evident

**Parameters:**
- Typed parameters
- Optional parameters with `?`
- Default parameter values used

**Return Values:**
- Explicit return type annotations
- Consistent return type patterns

## Module Design

**Exports:**
- Named exports preferred
- Consistent export patterns across modules

**Barrel Files:**
- Uses index files for module exports
- Organized import/export structure

---

*Convention analysis: 2026-03-27*