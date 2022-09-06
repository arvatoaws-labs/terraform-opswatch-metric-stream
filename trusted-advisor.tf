resource "aws_cloudwatch_event_bus" "opswatch" {
  name = "opswatch"
}

resource "aws_cloudwatch_event_rule" "trusted_advisor" {
  name = "trusted_advisor"
  event_bus_name = aws_cloudwatch_event_bus.opswatch.name
  event_pattern = jsonencode({
    source = ["aws.trustedadvisor"]
    detail-type = ["Trusted Advisor Check Item Refresh Notification"]
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  event_bus_name = aws_cloudwatch_event_bus.opswatch.name
  rule = aws_cloudwatch_event_rule.trusted_advisor.name
  target_id = "trusted_advisor_sns"
  arn = aws_sns_topic.trusted_advisor.arn
}

resource "aws_sns_topic" "trusted_advisor" {
  name = "trusted_advisor"
}

resource "aws_sns_topic_policy" "trusted_advisor" {
  arn    = aws_sns_topic.trusted_advisor.arn
  policy = data.aws_iam_policy_document.trusted_advisor_sns.json
}

data "aws_iam_policy_document" "trusted_advisor_sns" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.trusted_advisor.arn]
  }
}

resource "aws_sns_topic_subscription" "opswatch" {
  topic_arn = aws_sns_topic.trusted_advisor.arn
  protocol = "https"
  endpoint = "${var.url}/trusted_advisor"
}