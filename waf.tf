resource "aws_wafv2_web_acl" "waf" {
  name  = "${var.envName}-waf"
  scope = "REGIONAL"
  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled  = true
    metric_name                 = "waf-${var.envName}-default-rules"
    sampled_requests_enabled    = true
  }

  rule {
    name = "AWS-Managed-Rules-Common"
    priority = 1
    override_action {
      count {}
    }
    statement {
      managed_rule_group_statement {
        name = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        excluded_rule {
          name = "SizeRestrictions_QUERYSTRING"
        }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name = "waf-${var.envName}-common-rule"
      sampled_requests_enabled = true
    }
  }
}

resource "aws_wafv2_web_acl_association" "waf" {
  web_acl_arn   = aws_wafv2_web_acl.waf.arn
  resource_arn  = aws_lb.frontend.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "waf-kinesis-logs" {
  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf-kinesis-stream.arn]
  resource_arn            = aws_wafv2_web_acl.waf.arn
}

data "aws_iam_policy_document" "firehose-role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose-role" {
  name = "${var.envName}-firehose-waf-logs-role"
  assume_role_policy = data.aws_iam_policy_document.firehose-role.json
}

resource "aws_kinesis_firehose_delivery_stream" "waf-kinesis-stream" {
  destination = "extended_s3"
  name        = "aws-waf-logs-${var.envName}-kinesis-stream"

  extended_s3_configuration {
    bucket_arn  = aws_s3_bucket.waf-bucket.arn
    role_arn    = aws_iam_role.firehose-role.arn
    error_output_prefix = "error-"
  }
}

resource "aws_s3_bucket" "waf-bucket" {
  bucket  = "waf-logs-${var.envName}-${var.region}"
  acl     = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    enabled = true
    id      = "TransitionAfter60"
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }
}
