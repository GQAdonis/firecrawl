# Testing Patterns

**Analysis Date:** 2026-03-27

## Test Framework

**Runner:**
- Jest [Version inferred from `jest.config.ts`]
- Uses `ts-jest` for TypeScript support
- ESM module support

**Assertion Library:**
- Built-in Jest matchers
- `expect()` for assertions

**Run Commands:**
```bash
pnpm test              # Run all tests
pnpm test:watch        # Watch mode (inferred)
pnpm test:coverage     # Coverage report (inferred)
```

## Test File Organization

**Location:**
- Co-located tests: `__tests__` directories
- Test files named with `.test.ts` suffix
- Separate directories for:
  - `unit/`
  - `e2e/`
  - `snips/` (specialized E2E tests)

**Naming:**
- `[module-name].test.ts`
- `[feature].[type].test.ts`

**Structure:**
```
src/
├── __tests__/
│   ├── unit/
│   ├── e2e/
│   └── snips/
```

## Test Structure

**Suite Organization:**
```typescript
describe('Module/Feature', () => {
  beforeEach(() => {
    // Setup
  });

  test('specific behavior', () => {
    // Arrange, Act, Assert
  });

  test.concurrent('supports concurrent tests', () => {
    // Parallel test execution
  });
});
```

**Patterns:**
- `beforeEach()` for test setup
- `afterEach()` for cleanup
- Concurrent test support
- Descriptive test names

## Mocking

**Framework:**
- Jest built-in mocking
- Manual function/module mocking

**Patterns:**
```typescript
jest.mock('./module', () => ({
  functionName: jest.fn()
}));
```

**What to Mock:**
- External dependencies
- Complex logic
- Network calls
- File system interactions

**What NOT to Mock:**
- Simple, pure functions
- Core business logic

## Fixtures and Factories

**Test Data:**
- Inline test data
- Potential factory functions for complex objects

**Location:**
- Inline within test files
- Potential `__fixtures__` directories

## Coverage

**Requirements:**
- No strict coverage requirement detected
- JUnit XML report generation

**View Coverage:**
```bash
pnpm test:coverage
```

## Test Types

**Unit Tests:**
- Isolated module testing
- Focus on individual function behavior
- Located in `__tests__/unit/`

**Integration Tests:**
- Module interaction testing
- Located in potential `integration/` directories

**E2E Tests:**
- Comprehensive scenario testing
- Located in `__tests__/e2e/`
- Supports various scenarios (crawling, scraping, etc.)

## Common Patterns

**Async Testing:**
```typescript
test('async function', async () => {
  const result = await asyncFunction();
  expect(result).toBeDefined();
});
```

**Error Testing:**
```typescript
test('throws expected error', () => {
  expect(() => {
    throwingFunction();
  }).toThrow(SpecificErrorType);
});
```

**Specialized Test Utilities:**
- `testIf()` for conditional test skipping
- Environment-based test configuration

---

*Testing analysis: 2026-03-27*