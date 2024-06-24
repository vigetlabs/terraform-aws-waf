#=====================================
# Blocklist IP Sets
#=====================================
resource "aws_wafv2_ip_set" "ipv4" {
  count = module.this.enabled ? 1 : 0

  name               = "${module.this.id}-ipv4-blocklist"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.blocked_ips.ipv4

  tags = merge(module.this.tags, {
    Name = "${module.this.id} - IPV4 Blocklist"
  })
}

resource "aws_wafv2_ip_set" "ipv6" {
  count = module.this.enabled ? 1 : 0

  name               = "${module.this.id}-ipv6-blocklist"
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  addresses          = var.blocked_ips.ipv6

  tags = merge(module.this.tags, {
    Name = "${module.this.id} - WAF IPV6 Blocklist"
  })
}

#=====================================
# CRS ignored uris
#=====================================
resource "aws_wafv2_regex_pattern_set" "ignored_uri" {
  count = module.this.enabled ? 1 : 0

  name  = "ignored_uri"
  scope = "REGIONAL"

  dynamic "regular_expression" {
    for_each = toset(var.common_rule_set_ignored_uri_regex)

    content {
      regex_string = regular_expression.value
    }
  }

  tags = merge(module.this.tags, {
    Name = "${module.this.id} - Ignored URI Patterns"
  })
}

#=====================================
# WAF
#=====================================
## Note override action = none to have default behavior of managed rule when active https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl#none
resource "aws_wafv2_web_acl" "this" {
  count = module.this.enabled ? 1 : 0

  name  = module.this.id
  scope = upper(var.scope)
  tags = merge(module.this.tags, {
    Name = module.this.id
  })

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = module.this.id
    sampled_requests_enabled   = true
  }

  /**
   * WAF Rules
   */
  ## Denial of service https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html
  dynamic "rule" {
    for_each = var.managed_rules.global_dos == true ? [true] : []

    content {
      name     = "AWSRateBasedRuleGlobalDOS"
      priority = 1

      action {
        dynamic "block" {
          for_each = var.waf_mode == "active" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = var.waf_mode == "monitoring" ? [1] : []
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit              = var.dos_rate_limits.global
          aggregate_key_type = "IP"

          scope_down_statement {
            not_statement {
              statement {
                geo_match_statement {
                  country_codes = ["US"]
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSRateBasedRuleGlobalDOS"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.managed_rules.domestic_dos == true ? [true] : []

    content {
      name     = "AWSRateBasedRuleDomesticDOS"
      priority = 2

      action {
        dynamic "block" {
          for_each = var.waf_mode == "active" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = var.waf_mode == "monitoring" ? [1] : []
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit              = var.dos_rate_limits.domestic
          aggregate_key_type = "IP"

          scope_down_statement {
            geo_match_statement {
              country_codes = ["US"]
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSRateBasedRuleDomesticDOS"
        sampled_requests_enabled   = true
      }
    }
  }

  ## AWS Managed ip reputation list https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-ip-rep.html#aws-managed-rule-groups-ip-rep-amazon
  dynamic "rule" {
    for_each = var.managed_rules.ip_reputation == true ? [true] : []

    content {
      name     = "AWSManagedRulesAmazonIpReputationList"
      priority = 3

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAmazonIpReputationList"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesAmazonIpReputationListMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  ## IP Block List
  dynamic "rule" {
    for_each = var.managed_rules.ip_blocklist == true ? [true] : []

    content {
      name     = "AWSIPBlockList"
      priority = 4

      action {
        dynamic "block" {
          for_each = var.waf_mode == "active" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = var.waf_mode == "monitoring" ? [1] : []
          content {}
        }
      }

      statement {
        or_statement {
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.ipv4[0].arn
            }
          }
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.ipv6[0].arn
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSIPBlockList"
        sampled_requests_enabled   = true
      }
    }
  }

  ## Common rules https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html#aws-managed-rule-groups-baseline-crs
  dynamic "rule" {
    for_each = var.managed_rules.common == true ? [true] : []

    content {
      name     = "AWSManagedRulesCommonRuleSet"
      priority = 10

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesCommonRuleSet"
          vendor_name = "AWS"

          scope_down_statement {
            not_statement {
              statement {
                regex_pattern_set_reference_statement {
                  arn = aws_wafv2_regex_pattern_set.ignored_uri[0].arn

                  field_to_match {
                    uri_path {}
                  }

                  text_transformation {
                    priority = 0
                    type     = "NONE"
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesCommonRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  ## Known bad inputs https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html#aws-managed-rule-groups-baseline-known-bad-inputs
  dynamic "rule" {
    for_each = var.managed_rules.bad_inputs == true ? [true] : []

    content {
      name     = "AWSManagedRulesKnownBadInputsRuleSet"
      priority = 20

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesKnownBadInputsRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  ## SQL injection https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html#aws-managed-rule-groups-use-case-sql-db
  dynamic "rule" {
    for_each = var.managed_rules.sqli == true ? [true] : []

    content {
      name     = "AWSManagedRulesSQLiRuleSet"
      priority = 30

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesSQLiRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesSQLiRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  ## Posix exploits https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html#aws-managed-rule-groups-use-case-posix-os
  dynamic "rule" {
    for_each = var.managed_rules.unix == true ? [true] : []

    content {
      name     = "AWSManagedRulesUnixRuleSet"
      priority = 40

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesUnixRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesUnixRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  ## Linux exploits https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html#aws-managed-rule-groups-use-case-linux-os
  dynamic "rule" {
    for_each = var.managed_rules.linux == true ? [true] : []

    content {
      name     = "AWSManagedRulesLinuxRuleSet"
      priority = 50

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesLinuxRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesLinuxRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  ## Windows exploits https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html#aws-managed-rule-groups-use-case-windows-os
  dynamic "rule" {
    for_each = var.managed_rules.windows == true ? [true] : []

    content {
      name     = "AWSManagedRulesWindowsRuleSet"
      priority = 60

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesWindowsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesWindowsRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  ## PHP application exploits https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html#aws-managed-rule-groups-use-case-php-app
  dynamic "rule" {
    for_each = var.managed_rules.php == true ? [true] : []

    content {
      name     = "AWSManagedRulesPHPRuleSet"
      priority = 70

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesPHPRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesPHPRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  ## WordPress exploits https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html#aws-managed-rule-groups-use-case-wordpress-app
  dynamic "rule" {
    for_each = var.managed_rules.wordpress == true ? [true] : []

    content {
      name     = "AWSManagedRulesWordPressRuleSet"
      priority = 80

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesWordPressRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesWordPressRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  # TODO: Change bot control to include some optional rule overrides for good bots
  ## Bot control https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-bot.html
  dynamic "rule" {
    for_each = var.managed_rules.bot_control == true ? [true] : []

    content {
      name     = "AWSManagedRulesBotControlRuleSet"
      priority = 90

      dynamic "override_action" {
        for_each = var.waf_mode == "monitoring" ? [1] : []
        content {
          count {}
        }
      }

      dynamic "override_action" {
        for_each = var.waf_mode == "active" ? [1] : []
        content {
          none {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"

          # Allow common "good" bot categories
          rule_action_override {
            name = "CategoryAdvertising"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategoryArchiver"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategoryContentFetcher"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategoryEmailClient"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategoryHttpLibrary"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategoryLinkChecker"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategoryMiscellaneous"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategoryMonitoring"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategorySearchEngine"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategorySecurity"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategorySeo"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "CategorySocialMedia"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "SignalAutomatedBrowser"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "SignalKnownBotDataCenter"
            action_to_use = {
              allow = {}
            }
          }

          rule_action_override {
            name = "SignalNonBrowserUserAgent"
            action_to_use = {
              allow = {}
            }
          }

          # Captcha evaluate scraping frameworks
          rule_action_override {
            name = "CategoryScrapingFramework"
            action_to_use = {
              captcha = {}
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AWSManagedRulesBotControlRuleSetMetric"
        sampled_requests_enabled   = true
      }
    }
  }
}
