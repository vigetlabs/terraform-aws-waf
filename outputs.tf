output "id" {
  description = "The ID of the WAF WebACL"
  value       = one(aws_wafv2_web_acl.this[*].id)
}

output "arn" {
  description = "The ARN of the WAF WebACL"
  value       = one(aws_wafv2_web_acl.this[*].arn)
}
