---
name: terraform-patterns
description: Write production-ready Terraform following HashiCorp best practices. Use for infrastructure code, module design, or Terraform reviews. Emphasizes state management, security, reusability.
license: MIT
metadata:
  author: joe
  version: "1.0"
  stack: terraform
---

# Terraform Best Practices

Production-ready Terraform following HashiCorp best practices with AWS focus.

## When to Use

- Writing Terraform modules
- Reviewing infrastructure code
- Refactoring Terraform
- User mentions "Terraform", "IaC", or infrastructure

## Directory Structure

    terraform/
    ├── environments/
    │   ├── dev/
    │   ├── staging/
    │   └── prod/
    ├── modules/
    │   ├── vpc/
    │   ├── eks/
    │   └── rds/
    └── global/
        └── s3-state-backend/

## Module Structure

    modules/vpc/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── versions.tf
    └── README.md

## Core Principles

1. **One state file per environment** - never share state
2. **Remote state with locking** - always use S3 + DynamoDB
3. **Modules for reusability** - DRY principle
4. **Pin versions** - providers and modules
5. **Use data sources** - don't hardcode IDs

## versions.tf Template

    terraform {
      required_version = ">= 1.5.0"
      
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
      }
      
      backend "s3" {
        bucket         = "myorg-terraform-state"
        key            = "vpc/terraform.tfstate"
        region         = "us-east-1"
        encrypt        = true
        dynamodb_table = "terraform-locks"
      }
    }

## variables.tf Pattern

    variable "environment" {
      description = "Environment name (dev, staging, prod)"
      type        = string
      
      validation {
        condition     = contains(["dev", "staging", "prod"], var.environment)
        error_message = "Environment must be dev, staging, or prod"
      }
    }
    
    variable "vpc_cidr" {
      description = "CIDR block for VPC"
      type        = string
      default     = "10.0.0.0/16"
    }
    
    variable "tags" {
      description = "Common tags for all resources"
      type        = map(string)
      default     = {}
    }

## Resource Naming

    resource "aws_vpc" "main" {
      cidr_block           = var.vpc_cidr
      enable_dns_hostnames = true
      enable_dns_support   = true
      
      tags = merge(
        var.tags,
        {
          Name        = "${var.environment}-vpc"
          Environment = var.environment
          ManagedBy   = "terraform"
        }
      )
    }

## Data Sources Over Hardcoding

    # ❌ Bad
    ami = "ami-12345678"
    
    # ✅ Good
    data "aws_ami" "amazon_linux_2" {
      most_recent = true
      owners      = ["amazon"]
      
      filter {
        name   = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
      }
    }

## outputs.tf Pattern

    output "vpc_id" {
      description = "ID of the VPC"
      value       = aws_vpc.main.id
    }
    
    output "private_subnet_ids" {
      description = "IDs of private subnets"
      value       = aws_subnet.private[*].id
    }

## Security Best Practices

    # Encrypt everything
    resource "aws_s3_bucket" "data" {
      bucket = "${var.environment}-data"
    }
    
    resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
      bucket = aws_s3_bucket.data.id
      
      rule {
        apply_server_side_encryption_by_default {
          sse_algorithm = "AES256"
        }
      }
    }
    
    # Block public access
    resource "aws_s3_bucket_public_access_block" "data" {
      bucket = aws_s3_bucket.data.id
      
      block_public_acls       = true
      block_public_policy     = true
      ignore_public_acls      = true
      restrict_public_buckets = true
    }

## Local Values for DRY

    locals {
      common_tags = {
        Environment = var.environment
        ManagedBy   = "terraform"
        Project     = "myproject"
      }
      
      azs = slice(data.aws_availability_zones.available.names, 0, 3)
    }

## Count vs For Each

    # Use for_each for maps (easier to manage)
    resource "aws_subnet" "private" {
      for_each = {
        for idx, az in local.azs : az => {
          cidr = cidrsubnet(var.vpc_cidr, 8, idx)
          az   = az
        }
      }
      
      vpc_id            = aws_vpc.main.id
      cidr_block        = each.value.cidr
      availability_zone = each.value.az
      
      tags = merge(local.common_tags, {
        Name = "${var.environment}-private-${each.key}"
        Type = "private"
      })
    }

## Common Mistakes

- ❌ Not using remote state
- ❌ Hardcoded credentials
- ❌ No version pinning
- ❌ Resources without tags
- ❌ Not using modules
- ❌ Shared state across environments
- ❌ No terraform fmt/validate in CI

## Always Include

- README with usage examples
- variables.tf with descriptions and validation
- outputs.tf with descriptions
- versions.tf with pinned versions
- .terraform-version file
- Pre-commit hooks for fmt/validate
