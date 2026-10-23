output "instance_profile_name" {
  value = aws_iam_instance_profile.ec2.name
}

output "lambda_role_arns" {
  value = {
    waf_alert        = aws_iam_role.service["assac-lambda-waf-alert-role"].arn
    asg_alert        = aws_iam_role.service["assac-lambda-asg-alert-role"].arn
    cloudwatch_alarm = aws_iam_role.service["assac-role-lambda-cloudwatch-alert"].arn
    guardduty_alert  = aws_iam_role.service["assac-lambda-guardduty-alert-role"].arn
    clawops_call     = aws_iam_role.service["assac-clawops-call-role-e5cl1yy8"].arn
  }
}

output "lambda_role_names" {
  value = {
    waf_alert        = aws_iam_role.service["assac-lambda-waf-alert-role"].name
    asg_alert        = aws_iam_role.service["assac-lambda-asg-alert-role"].name
    cloudwatch_alarm = aws_iam_role.service["assac-role-lambda-cloudwatch-alert"].name
    guardduty_alert  = aws_iam_role.service["assac-lambda-guardduty-alert-role"].name
    clawops_call     = aws_iam_role.service["assac-clawops-call-role-e5cl1yy8"].name
  }
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
