# AWS WAF & Shield — Web ACL with managed rules, rate limiting, and logging
#
# Scope: CLOUDFRONT (Web ACLs for CloudFront MUST live in us-east-1).
# Attach to: CloudFront distribution, and optionally a regional Web ACL on the ALB
# behind it for defense in depth.
#
# Usage:
#   terraform init && terraform apply -var="log_bucket_name=my-waf-logs-12345"

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# CloudFront-scoped WAF resources must be created in us-east-1
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

variable "log_bucket_name" {
  description = "S3 bucket receiving WAF logs via Kinesis Firehose"
  type        = string
}

# ---------------------------------------------------------------------------
# Log delivery: WAF -> Kinesis Firehose -> S3 (queryable later with Athena)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "waf_logs" {
  provider = aws.use1
  bucket   = var.log_bucket_name
}

resource "aws_iam_role" "firehose" {
  provider = aws.use1
  name     = "waf-log-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  provider    = aws.use1
  name        = "aws-waf-logs-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.waf_logs.arn
    prefix     = "waf-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
  }
}

# ---------------------------------------------------------------------------
# The Web ACL
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "edge" {
  provider = aws.use1
  name     = "edge-web-acl"
  scope    = "CLOUDFRONT"

  # Default: let traffic through, rules decide the exceptions.
  default_action {
    allow {}
  }

  # 1. AWS Managed Rules — common vulnerabilities (XSS, path traversal, etc.)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      # 'none' = use the rule group's own Allow/Block decisions
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # 2. SQL injection protection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # 3. Known bad inputs (log4shell-style payloads and friends)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # 4. Rate-based rule — the anti-scraper. 200 req / 5 min per IP, then CAPTCHA
  #    (not Block: real users behind NAT shouldn't be punished for one bad IP).
  rule {
    name     = "RateLimitPerIP"
    priority = 4

    action {
      captcha {}
    }

    statement {
      rate_based_statement {
        limit              = 200
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "EdgeWebACL"
    sampled_requests_enabled   = true
  }
}

# ---------------------------------------------------------------------------
# Ship every allow/block decision to S3
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl_logging_configuration" "edge" {
  provider                = aws.use1
  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.edge.arn
}

output "web_acl_arn" {
  description = "Attach this ARN to your CloudFront distribution"
  value       = aws_wafv2_web_acl.edge.arn
}
