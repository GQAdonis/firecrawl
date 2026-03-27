# Firecrawl Architecture

**Analysis Date:** 2026-03-27

## Pattern Overview

**Overall:** Microservice-based Modular Web Scraping API

**Key Characteristics:**
- Distributed worker architecture
- API-first design
- Configurable and extensible scraping engine
- Multi-version API support
- Robust error handling and observability

## Layers

**API Layer:**
- Purpose: Handle HTTP requests, routing, and API versioning
- Location: `apps/api/src/routes/`
- Contains: API endpoints for different versions (v0, v1, v2)
- Depends on: Controllers, services, scraping modules
- Key files:
  - `v0Router.ts`
  - `v1Router.ts`
  - `v2Router.ts`

**Controller Layer:**
- Purpose: Process requests, coordinate business logic
- Location: `apps/api/src/controllers/`
- Contains: Request validation, response formatting
- Depends on: Services, types
- Key responsibilities: Input validation, error handling

**Service Layer:**
- Purpose: Core business logic and integrations
- Location: `apps/api/src/services/`
- Contains:
  - Queue management
  - External service integrations
  - Background job processing
- Key services:
  - `queue-service.ts`
  - `worker/nuq.ts`
  - `indexing/indexer-queue.ts`

**Scraping Layer:**
- Purpose: Web content extraction and processing
- Location: `apps/api/src/scraper/`
- Contains:
  - URL scraping logic
  - Content parsing
  - Engine selection
- Key modules:
  - `WebScraper/`
  - `scrapeURL/`

## Data Flow

**Scraping Request Flow:**
1. API endpoint receives request
2. Request validated by controller
3. Job enqueued in worker queue
4. Scraping worker processes job
5. Content extracted and transformed
6. Result returned to client

## Key Abstractions

**WebScraper:**
- Purpose: Flexible web content extraction
- Location: `apps/api/src/scraper/WebScraper/`
- Patterns: Strategy pattern for engine selection
- Configurable via feature toggles

**Queue Management:**
- Purpose: Distributed task processing
- Location: `apps/api/src/services/queue-service.ts`
- Patterns: Bull/BullMQ for job scheduling
- Supports multiple queue types (generate, research, billing)

## Entry Points

**Main API Server:**
- Location: `apps/api/src/index.ts`
- Responsibilities:
  - Initialize Express server
  - Set up middleware
  - Register routes
  - Configure error handling
  - Manage server lifecycle

**Worker Entry Point:**
- Location: Multiple entry points in services
- Manages background job processing
- Handles distributed task execution

## Error Handling

**Strategy:**
- Centralized error middleware
- Sentry error tracking
- Detailed error responses
- Graceful degradation

## Cross-Cutting Concerns

**Logging:**
- Custom logger in `apps/api/src/lib/logger.ts`
- Configurable logging levels

**Authentication:**
- API key based
- Team-based access control

**Rate Limiting:**
- Configurable per API key
- Queue-based concurrency control

---

*Architecture analysis: 2026-03-27*