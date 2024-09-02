# Automation goes here

locals {
  # Read bucket definitions
  definitions          = merge([for f in fileset(path.module, "./resources/*.yaml") : yamldecode(file("${path.module}/${f}"))]...)
  buckets              = { for key, bucket in local.definitions : key => bucket if(try(bucket.disable_s3, false) == false) }
  notification_buckets = { for key, bucket in local.definitions : key => bucket if(try(length(bucket.notifications) > 0, false)) }

  # Read bucket policies
  policies = merge([for f in fileset(path.module, "./resources/policies/*.json") : { "${f}" : file("${path.module}/${f}") }]...)

  # Read transfer definitions
  transfer_families = { for key, configs in local.definitions : key => configs.transfer if(try(length(configs.transfer) > 0, false)) }
}



module "s3-bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.1.2"

  for_each = local.buckets

  bucket = can(each.value.bucket_prefix) ? null : each.key

  acceleration_status                         = try(each.value.acceleration_status, null)
  acl                                         = try(each.value.acl, null)
  analytics_configuration                     = try(each.value.analytics_configuration, {})
  attach_deny_insecure_transport_policy       = try(each.value.attach_deny_insecure_transport_policy, false)
  attach_deny_unencrypted_object_uploads      = try(each.value.attach_deny_unencrypted_object_uploads, false)
  attach_elb_log_delivery_policy              = try(each.value.attach_elb_log_delivery_policy, false)
  attach_inventory_destination_policy         = try(each.value.attach_inventory_destination_policy, false)
  attach_lb_log_delivery_policy               = try(each.value.attach_lb_log_delivery_policy, false)
  attach_policy                               = try(each.value.attach_policy, false)
  attach_public_policy                        = try(each.value.attach_public_policy, true)
  attach_require_latest_tls_policy            = try(each.value.attach_require_latest_tls_policy, false)
  block_public_acls                           = try(each.value.block_public_acls, false)
  block_public_policy                         = try(each.value.block_public_policy, false)
  bucket_prefix                               = try(each.value.bucket_prefix, null)
  control_object_ownership                    = try(each.value.control_object_ownership, false)
  cors_rule                                   = try(each.value.cors_rule, [])
  create_bucket                               = try(each.value.create_bucket, true)
  expected_bucket_owner                       = try(each.value.expected_bucket_owner, null)
  force_destroy                               = try(each.value.force_destroy, false)
  grant                                       = try(each.value.grant, [])
  ignore_public_acls                          = try(each.value.ignore_public_acls, false)
  intelligent_tiering                         = try(each.value.intelligent_tiering, {})
  inventory_configuration                     = try(each.value.inventory_configuration, {})
  lifecycle_rule                              = try(each.value.lifecycle_rule, [])
  logging                                     = try(each.value.logging, {})
  metric_configuration                        = try(each.value.metric_configuration, [])
  object_lock_configuration                   = try(each.value.object_lock_configuration, {})
  object_lock_enabled                         = try(each.value.object_lock_enabled, false)
  object_ownership                            = try(each.value.object_ownership, "ObjectWriter")
  policy                                      = try(local.policies["resources/policies/${each.key}.json"], null)
  replication_configuration                   = try(each.value.replication_configuration, {})
  request_payer                               = try(each.value.request_payer, null)
  restrict_public_buckets                     = try(each.value.restrict_public_buckets, false)
  server_side_encryption_configuration        = try(each.value.server_side_encryption_configuration, {})
  tags                                        = merge(var.default_tags, try(each.value.tags, {}))
  versioning                                  = try(each.value.versioning, {})
  website                                     = try(each.value.website, {})
}


module "s3_notification" {
  source  = "terraform-aws-modules/s3-bucket/aws//modules/notification"
  version = "4.1.2"

  for_each = local.notification_buckets

  bucket     = each.key
  create     = try(each.value.notifications.create, false)
  bucket_arn = can(try(each.value.notifications.attach_s3_arn, true)) ? module.s3-bucket[each.key].s3_bucket_arn : null

  # SNS
  create_sns_policy = try(each.value.notifications.sns.attach_policy, false)
  sns_notifications = try(each.value.notifications.sns.definitions, {})

  # SQS
  create_sqs_policy = try(each.value.notifications.sqs.attach_policy, false)
  sqs_notifications = try(each.value.notifications.sqs.definitions, {})

  # EventBridge
  eventbridge = try(each.value.notifications.eventbridge, false)

  # Lambda
  lambda_notifications = try(each.value.notifications.lambda, {})
}

module "transfer_family" {
  source = "./local_modules/transfer-family"

  for_each = local.transfer_families
  name     = each.key
  vpc_name = each.value.vpc_name
  config   = try(each.value, {})

  region       = var.region
  default_tags = var.default_tags

  providers = {
    aws = aws
  }
}