---
name: security-review
description: Security-focused code and infrastructure review. Use when reviewing code, PRs, Terraform, or when user asks about security. Checks for common vulnerabilities, secrets, misconfigurations.
license: MIT
metadata:
  author: joe
  version: "1.0"
  domain: security
---

# Security Review Skill

Expert security reviewer focusing on common vulnerabilities and AWS/cloud misconfigurations.

## When to Use

- Reviewing code for security issues
- Analyzing Terraform for misconfigurations
- User mentions "security", "vulnerability", or "CVE"
- PR reviews
- Pre-production checks

## Security Checklist

### Secrets and Credentials

- [ ] No hardcoded API keys, passwords, tokens
- [ ] No AWS credentials in code
- [ ] Secrets in environment variables or secrets manager
- [ ] .gitignore includes .env files
- [ ] No credentials in logs

### Input Validation

- [ ] All user input validated
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (output encoding)
- [ ] Path traversal prevention
- [ ] Command injection prevention

### Authentication & Authorization

- [ ] Strong password requirements
- [ ] Rate limiting on auth endpoints
- [ ] Session timeout configured
- [ ] CSRF protection
- [ ] Proper authorization checks

### AWS/Cloud Security

- [ ] S3 buckets not public
- [ ] Security groups follow least privilege
- [ ] IAM roles use least privilege
- [ ] Encryption at rest enabled
- [ ] Encryption in transit (TLS 1.3)
- [ ] VPC flow logs enabled
- [ ] CloudTrail enabled

### Dependencies

- [ ] No known vulnerable dependencies
- [ ] Dependencies pinned to versions
- [ ] Regular dependency updates
- [ ] No unnecessary dependencies

### Logging & Monitoring

- [ ] Security events logged
- [ ] No sensitive data in logs
- [ ] Alerts configured for suspicious activity
- [ ] Log retention policy

## Red Flags to Flag Immediately

    # ❌ Hardcoded secrets
    AWS_SECRET_KEY = "abcd1234..."
    password = "admin123"
    
    # ❌ SQL injection
    query = f"SELECT * FROM users WHERE id = {user_input}"
    
    # ❌ Command injection
    os.system(f"ls {user_input}")
    
    # ❌ Public S3 bucket
    resource "aws_s3_bucket_acl" "public" {
      acl = "public-read"  # ❌
    }
    
    # ❌ Overly permissive IAM
    "Action": "*",
    "Resource": "*"
    
    # ❌ No encryption
    encrypted = false

## Secure Patterns

### Go - SQL Injection Prevention

    // ✅ Good - parameterized query
    row := db.QueryRowContext(ctx, 
        "SELECT * FROM users WHERE email = $1", 
        email,
    )

### Go - Secrets from Environment

    // ✅ Good
    apiKey := os.Getenv("API_KEY")
    if apiKey == "" {
        return fmt.Errorf("API_KEY not set")
    }

### Terraform - S3 Security

    resource "aws_s3_bucket_public_access_block" "secure" {
      bucket = aws_s3_bucket.main.id
      
      block_public_acls       = true
      block_public_policy     = true
      ignore_public_acls      = true
      restrict_public_buckets = true
    }

### Terraform - IAM Least Privilege

    data "aws_iam_policy_document" "lambda" {
      statement {
        effect = "Allow"
        actions = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        resources = ["arn:aws:logs:*:*:*"]
      }
    }

## Review Output Format

    ## Security Review Summary
    
    **Critical Issues:** 2
    **High Issues:** 5
    **Medium Issues:** 3
    **Low Issues:** 1
    
    ### Critical
    
    1. **Hardcoded AWS Credentials** (file.go:23)
       - AWS secret key found in source code
       - Fix: Move to AWS Secrets Manager
    
    ### High
    
    1. **SQL Injection Vulnerability** (handler.go:45)
       - Unsanitized user input in SQL query
       - Fix: Use parameterized queries

## Always Check

- Terraform: `terraform validate` and `tfsec`
- Go: `gosec` static analysis
- Dependencies: `govulncheck` and `npm audit`
- Secrets: `gitleaks` or `trufflehog`
