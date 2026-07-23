---
name: openspec
description: Create technical specifications with spec.md (requirements) and design.md (implementation). Use when asked to write technical specs, design documents, system designs, or when user mentions "spec", "technical design", or "architecture document".
license: Apache-2.0
metadata:
  author: joe
  version: "1.0"
  domain: engineering
---

# OpenSpec Technical Specification Skill

Create comprehensive technical specifications with separated requirements (spec.md) and design (design.md) documents.

## When to Use

- User asks to "create a spec" or "write a technical specification"
- User mentions "design document", "system design", or "technical proposal"
- User wants to document a new feature, service, or system
- User references architecture planning or technical requirements

## Directory Structure

Create TWO files in `docs/openspec/specs/[feature-name]/`:
```
docs/openspec/specs/user-authentication/
├── spec.md      # High-level requirements (stakeholder-facing)
└── design.md    # Technical implementation (engineer-facing)
```

Use kebab-case for directory names:
- `user-authentication`
- `api-gateway-v2`
- `payment-processing`
- `notification-service`

## spec.md Template (Requirements Document)
```
# [Feature/Component Name]

**Status**: [Draft | In Review | Approved | Implemented | Deprecated]
**Version**: [semver, e.g., 1.0.0]
**Last Updated**: [YYYY-MM-DD]
**Owner**: [Name/Team]
**Stakeholders**: [List of stakeholders]

## Overview

[2-3 sentence summary of what this spec covers and why it matters]

## Problem Statement

### Current State
[Describe current situation, pain points, or gaps]

### Desired State
[Describe target state after implementation]

### Success Metrics
- [Metric 1: e.g., Reduce latency to <100ms p99]
- [Metric 2: e.g., Support 10k concurrent users]
- [Metric 3: e.g., Zero data loss during migration]

## Requirements

### Functional Requirements

**MUST have:**
- [ ] [Requirement 1]
- [ ] [Requirement 2]

**SHOULD have:**
- [ ] [Requirement 3]

**COULD have:**
- [ ] [Nice-to-have feature]

**WON'T have (this iteration):**
- [ ] [Explicitly out of scope]

### Non-Functional Requirements

**Performance:**
- [e.g., Response time < 200ms for 95th percentile]

**Scalability:**
- [e.g., Handle 100k requests per second]

**Security:**
- [e.g., TLS 1.3, OAuth2 authentication, encryption at rest]

**Reliability:**
- [e.g., 99.9% uptime SLA]

**Observability:**
- [e.g., Full distributed tracing, structured logging]

## User Stories / Use Cases

### Primary Use Case
**As a** [user type]
**I want** [goal]
**So that** [benefit]

**Acceptance Criteria:**
- [ ] [Criterion 1]
- [ ] [Criterion 2]

### Edge Cases
1. [Edge case description and handling]
2. [Edge case description and handling]

## Dependencies

### Internal Dependencies
- [System/Service 1] - [Why needed]

### External Dependencies
- [Third-party service/library] - [Version, purpose]

### Team Dependencies
- [Team name] - [What's needed from them]

## Constraints and Assumptions

### Constraints
- [Technical: "Must run on AWS EKS"]
- [Business: "Launch by Q2 2026"]
- [Regulatory: "Must comply with GDPR"]

### Assumptions
- [Assumption 1: "User base will not exceed 1M in first year"]
- [Assumption 2: "AWS us-east-1 availability"]

## Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| [Risk 1] | High/Med/Low | High/Med/Low | [How we'll address it] |

## Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Discovery | [timeframe] | [deliverable] |
| Design | [timeframe] | [deliverable] |
| Implementation | [timeframe] | [deliverable] |
| Testing | [timeframe] | [deliverable] |
| Rollout | [timeframe] | [deliverable] |

## Open Questions

- [ ] [Question 1 - Owner: Name, Due: Date]
- [ ] [Question 2 - Owner: Name, Due: Date]

## Related Documents

- [ADR-NNNN: Related decision](../../adr/NNNN-title.md)
- [Design Doc](./design.md)

## Approval Sign-off

- [ ] Engineering Lead: [Name] - [Date]
- [ ] Product Manager: [Name] - [Date]
- [ ] Security Review: [Name] - [Date]
```

## design.md Template (Implementation Document)
```
# [Feature/Component Name] - Technical Design

**Spec Version**: [Links to spec.md version]
**Last Updated**: [YYYY-MM-DD]
**Authors**: [Names]
**Reviewers**: [Names]

## Executive Summary

[1-2 paragraph technical summary of the design approach]

## Architecture Overview

### System Context Diagram

    ┌─────────────┐
    │   Client    │
    └──────┬──────┘
           │
           ▼
    ┌─────────────┐      ┌──────────────┐
    │  API Gateway│─────▶│   Service A  │
    └─────────────┘      └──────────────┘

## Data Model

### Entities

**Entity: User**

    type User struct {
        ID        string    `json:"id"`
        Email     string    `json:"email"`
        CreatedAt time.Time `json:"created_at"`
    }

**Validation Rules:**
- ID: UUID v4, required
- Email: Valid email format, unique, required

### Database Schema

    CREATE TABLE users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email VARCHAR(255) UNIQUE NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    
    CREATE INDEX idx_users_email ON users(email);

## API Design

### POST /api/v1/users

Creates a new user.

**Request:**

    {
      "email": "user@example.com"
    }

**Response: 201 Created**

    {
      "id": "uuid",
      "email": "user@example.com",
      "created_at": "2026-02-15T10:00:00Z"
    }

**Error Responses:**
- 400 Bad Request - Invalid email
- 409 Conflict - Email already exists
- 500 Internal Server Error

## Infrastructure

### Services

**Service: user-service**
- Language: Go 1.23+
- Framework: stdlib + chi router
- Deployment: Kubernetes
- Scaling: Horizontal (2-10 pods)
- Resources: CPU 500m-2000m, Memory 512Mi-2Gi

### Data Stores

**PostgreSQL 15**
- Instance: RDS db.r6g.large
- Backup: Daily snapshots, 30-day retention
- Replication: Multi-AZ

**Redis 7**
- Purpose: Session cache
- Instance: ElastiCache cache.r6g.large
- TTL: 24 hours

## Security

### Authentication
- OAuth2 + JWT
- Token expiry: 1 hour access, 30 day refresh

### Secrets Management
- AWS Secrets Manager for DB credentials
- Rotation: Every 90 days

### Data Protection
- At Rest: AES-256 (RDS, S3)
- In Transit: TLS 1.3
- PII: Hashing for emails

## Observability

### Metrics
- http_requests_total (counter)
- http_request_duration_seconds (histogram)
- db_connections_active (gauge)

### SLIs/SLOs
- Availability: 99.9%
- Latency p99: < 500ms
- Error rate: < 0.1%

### Logging
- Format: JSON structured
- Fields: timestamp, level, message, trace_id
- Destination: CloudWatch Logs
- Retention: 90 days

### Tracing
- System: OpenTelemetry → Tempo
- Sampling: 1% production, 100% staging

## Testing

- Unit tests: >80% coverage, Go testing
- Integration: testcontainers
- E2E: Playwright
- Performance: k6 (1k, 10k, 100k RPS)
- Security: Semgrep (SAST), OWASP ZAP (DAST)

## Deployment

### Rollout
1. Canary: 5% traffic, monitor 1 hour
2. Gradual: 25%, 50%, 100% with 1-hour intervals
3. Rollback: Auto if error rate > 1%

### Feature Flags
- feature.new_api: Boolean, default false
- Tool: LaunchDarkly

## Cost Estimate

| Component | Monthly (USD) |
|-----------|---------------|
| EKS       | $150          |
| EC2       | $300          |
| RDS       | $200          |
| Redis     | $100          |
| Total     | $750          |

## Alternatives Considered

### Alternative 1: NoSQL Database

**Pros:** Better horizontal scaling
**Cons:** No transactions, complex queries difficult
**Why not:** Need ACID guarantees for user data

## References

- [ADR-NNNN](../../adr/NNNN-title.md)
- [API Docs](https://api.example.com)
```

## Workflow

1. **Ask clarifying questions** about requirements
2. **Create directory structure** first
3. **Generate spec.md** with business requirements
4. **Generate design.md** with technical details
5. **Cross-reference related ADRs**
6. **Use concrete examples** based on Go, AWS, Terraform stack

## Best Practices

- spec.md is stakeholder-facing (less technical, business value)
- design.md is engineer-facing (implementation details, code)
- Use diagrams (Mermaid preferred, ASCII art acceptable)
- Include real request/response examples
- Define exact metrics and SLOs
- Document error cases and edge cases
- Include infrastructure cost estimates
- Keep both documents synchronized
