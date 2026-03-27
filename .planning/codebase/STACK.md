# Technology Stack

**Analysis Date:** 2026-03-27

## Languages

**Primary:**
- TypeScript 5.8.3 - Core API implementation
- JavaScript (as transpiled TypeScript) - Runtime execution

**Secondary:**
- Rust (via `@mendable/firecrawl-rs`) - Specific services or optimizations

## Runtime

**Environment:**
- Node.js (ES2022 module support)
- Runtime target: NodeNext module resolution
- Package Manager: pnpm 10.16.1

## Frameworks

**Core:**
- Express 4.22.0 - Web server framework
- Bullmq 5.56.7 - Background job processing
- Playwright (service) - Browser automation for web scraping

**Testing:**
- Jest 30.2.0 - Unit and integration testing
- Supertest 6.3.3 - HTTP testing

**Build/Dev:**
- TypeScript 5.8.3 - Type-safe compilation
- tsx 4.20.3 - TypeScript execution
- tsc-watch 7.1.1 - Incremental compilation

## Key Dependencies

**Web Scraping:**
- cheerio 1.0.0-rc.12 - HTML parsing
- tough-cookie 4.1.4 - Cookie management
- undici 7.24.1 - HTTP client

**AI Integrations:**
- @ai-sdk/* (multiple providers) - AI model access
  - OpenAI, Anthropic, Google, Groq, etc.
- ollama-ai-provider 1.2.0 - Local AI model support
- @dqbd/tiktoken 1.0.22 - Token counting

**Utilities:**
- lodash 4.17.23 - Utility functions
- zod 4.1.12 - Runtime type validation
- dotenv 16.3.1 - Environment configuration

## Configuration

**Environment:**
- Configurable via environment variables
- Supports multiple AI providers
- Configurable rate limiting and concurrency
- Optional proxy support

**Build:**
- `tsconfig.json` - TypeScript compilation settings
- `pnpm-workspace.yaml` - Monorepo management

## Platform Requirements

**Development:**
- Node.js 20+ recommended
- pnpm package manager
- Docker (for full local development)

**Production:**
- Node.js runtime
- Redis for job queues
- Optional PostgreSQL for data persistence
- Optional RabbitMQ for message queuing

---

*Stack analysis: 2026-03-27*