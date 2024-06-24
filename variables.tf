variable "scope" {
  type        = string
  default     = "regional"
  description = <<EOT
    Whether the WAF should be for a regional application or cloudfront
    Note: if cloudfront provider must specify the us-east-1 region
    EOT
  validation {
    condition     = contains(["regional", "cloudfront"], var.scope)
    error_message = "Allowed values: `regional`, `cloudfront`."
  }
}

variable "waf_mode" {
  type        = string
  default     = "monitoring"
  description = "Whether the WAF should be monitoring or active"
  validation {
    condition     = contains(["monitoring", "active"], var.waf_mode)
    error_message = "Allowed values: `monitoring`, `active`."
  }
}

variable "managed_rules" {
  type = object({
    global_dos    = bool
    domestic_dos  = bool
    ip_reputation = bool
    ip_blocklist  = bool
    common        = bool
    bad_inputs    = bool
    sqli          = bool
    unix          = bool
    linux         = bool
    windows       = bool
    php           = bool
    wordpress     = bool
    bot_control   = bool
  })

  default = {
    global_dos    = true
    domestic_dos  = true
    ip_reputation = true
    ip_blocklist  = false
    common        = true
    bad_inputs    = true
    sqli          = true
    unix          = true
    linux         = true
    windows       = false
    php           = false
    wordpress     = false
    bot_control   = false
  }
}

variable "blocked_ips" {
  type = object({
    ipv4 = list(string)
    ipv6 = list(string)
  })

  default = {
    ipv4 = []
    ipv6 = []
  }
}

variable "dos_rate_limits" {
  type = object({
    domestic = number
    global   = number
  })

  default = {
    domestic = 2000
    global   = 500
  }
}

variable "common_rule_set_ignored_uri_regex" {
  type    = list(string)
  default = ["^/admin.*"]
}
