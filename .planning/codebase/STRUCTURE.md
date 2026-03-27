# Codebase Structure

**Analysis Date:** 2026-03-27

## Directory Layout

```
firecrawl/
├── apps/                   # Core application monorepo
│   ├── api/                # Main API server
│   │   ├── src/            # Source code
│   │   │   ├── controllers/
│   │   │   ├── routes/
│   │   │   ├── services/
│   │   │   ├── scraper/
│   │   │   ├── lib/
│   │   │   └── utils/
│   │   └── __tests__/      # API tests
│   │
│   ├── js-sdk/             # JavaScript SDK
│   ├── python-sdk/         # Python SDK
│   ├── rust-sdk/           # Rust SDK
│   ├── java-sdk/           # Java SDK
│   ├── playwright-service/ # Browser automation service
│   ├── test-suite/         # Comprehensive test suite
│   └── ui/                 # User interface
│
└── monorepo configuration files
```

## Directory Purposes

**`apps/api/`:**
- Purpose: Core web scraping API implementation
- Contains: Server configuration, routes, scrapers, services
- Key files:
  - `src/index.ts`: Main server entry point
  - `src/config.ts`: Environment configuration
  - `src/routes/`: API route definitions

**`apps/js-sdk/`:**
- Purpose: JavaScript client library
- Contains: Client implementation, examples
- Supports different usage patterns (browser, Node.js)

**`apps/python-sdk/`:**
- Purpose: Python client library
- Contains: Client classes, type definitions
- Supports async and sync usage

**`apps/rust-sdk/`:**
- Purpose: Rust client library
- Contains: Low-level implementation
- Focuses on performance and safety

**`apps/test-suite/`:**
- Purpose: Comprehensive testing infrastructure
- Contains: Integration tests, load tests
- Supports multiple testing scenarios

## Key File Locations

**Entry Points:**
- `apps/api/src/index.ts`: Main API server
- `apps/api/src/main/`: Additional entry point modules

**Configuration:**
- `apps/api/src/config.ts`: Environment configuration
- `.env`: Environment-specific settings
- `apps/api/tsconfig.json`: TypeScript configuration

**Core Logic:**
- `apps/api/src/scraper/`: Web scraping implementation
- `apps/api/src/services/`: Background services
- `apps/api/src/routes/`: API route handlers

**Testing:**
- `apps/api/__tests__/`: API unit tests
- `apps/test-suite/`: Comprehensive test suite

## Naming Conventions

**Files:**
- Lowercase with hyphens or camelCase
- Suffix indicates purpose (`.service.ts`, `.controller.ts`)

**Directories:**
- Lowercase, kebab-case
- Indicate architectural layer or feature

## Where to Add New Code

**New Feature:**
- Primary code: `apps/api/src/`
  - Controllers: `apps/api/src/controllers/`
  - Routes: `apps/api/src/routes/`
  - Services: `apps/api/src/services/`
- Tests: `apps/api/__tests__/` or `apps/test-suite/`

**New SDK Implementation:**
- Language-specific directory under `apps/`
- Follow existing SDK structure
- Implement client library

**Utilities:**
- Shared helpers: `apps/api/src/utils/`
- Library-wide utilities: Consider extracting to separate package

## Special Directories

**`__tests__`:**
- Purpose: Colocated tests
- Generated: No
- Committed: Yes

**`native/`:**
- Purpose: Native code implementations
- Used in: Performance-critical modules
- Language: Typically Rust or Go

---

*Structure analysis: 2026-03-27*