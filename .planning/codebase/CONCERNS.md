# Codebase Concerns

**Analysis Date:** 2026-03-27

## Tech Debt

### TypeScript Type Safety
**Area:** Widespread TypeScript Looseness
- Issue: Extensive use of `any` and TypeScript ignore comments
- Files:
  - `apps/js-sdk/firecrawl/src/v2/methods/*`
  - `apps/api/src/scraper/WebScraper/crawler.ts`
- Impact: Reduced type safety, potential runtime errors
- Fix approach:
  - Systematically replace `any` with specific interfaces
  - Remove `@ts-ignore` comments
  - Add comprehensive type definitions

### Logging and Debugging
**Area:** Inconsistent Logging
- Issue: Scattered `console.log()` calls in production code
- Files:
  - `apps/api/src/scraper/scrapeURL/lib/extractSmartScrape.ts`
  - `apps/api/src/lib/extract/extraction-service.ts`
- Impact: Potential performance overhead, information leakage
- Fix approach:
  - Replace with structured logging
  - Remove or conditionally disable debug logs
  - Implement proper log levels

## Known Bugs

### Potential Rate Limiting Issues
**Area:** Concurrency and Rate Limiting
- Symptoms: No explicit comprehensive rate limiting strategy
- Files:
  - `apps/api/src/services/rate-limiter.test.ts`
  - `apps/api/src/services/queue-worker.ts`
- Trigger: High concurrent request volumes
- Workaround: Implement robust queue and backoff mechanisms

## Performance Bottlenecks

### Large File Processing
**Slow Operation:** Model Price Calculation
- Problem: Extremely large file `model-prices.ts` (22,390 lines)
- Files: `apps/api/src/lib/extract/usage/model-prices.ts`
- Cause: Monolithic pricing configuration
- Improvement path:
  - Split into modular pricing modules
  - Implement lazy loading or caching
  - Consider external configuration management

## Security Considerations

### Potential Information Exposure
**Area:** Debugging and Error Handling
- Risk: Unhandled error scenarios might expose system internals
- Files:
  - `apps/api/src/lib/custom-error.ts`
  - `apps/api/src/lib/error-serde.ts`
- Current mitigation: Minimal error handling detected
- Recommendations:
  - Implement comprehensive error sanitization
  - Add global error handling middleware
  - Ensure no sensitive information is leaked in error responses

## Fragile Areas

### Complex Extraction Logic
**Component:** Extraction Service
- Files:
  - `apps/api/src/lib/extract/extraction-service.ts`
  - `apps/api/src/lib/extract/fire-0/extraction-service-f0.ts`
- Why fragile: Multiple nested transformation and extraction steps
- Safe modification:
  - Add comprehensive unit tests
  - Implement clear interface contracts
  - Use functional composition

## Dependencies at Risk

### SDK Version Complexity
**Package:** Firecrawl SDK
- Risk: Multiple SDK versions (`v1`, `v2`) with potential divergence
- Impact:
  - Maintenance overhead
  - Potential compatibility issues
- Migration plan:
  - Deprecate v1 with clear migration guide
  - Standardize SDK interfaces
  - Provide automated migration scripts

## Test Coverage Gaps

### Limited E2E Test Scenarios
**Untested Area:** Comprehensive Scenario Coverage
- What's not tested:
  - Edge case handling
  - Complex scraping scenarios
- Files: `apps/api/src/__tests__/snips/*`
- Risk: Potential undetected failures in production
- Priority: High
- Recommendations:
  - Expand test suites with diverse scenarios
  - Add chaos testing
  - Implement property-based testing

## Scaling Limits

### Worker and Queue Management
**Resource:** Background Job Processing
- Current capacity: Not clearly defined
- Limit: Potential bottlenecks in concurrent job processing
- Scaling path:
  - Implement horizontal scaling strategies
  - Add more sophisticated queue management
  - Design for elastic worker pool

---

*Concerns audit: 2026-03-27*