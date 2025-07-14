resource "aws_dynamodb_table" "feedback_table" {
  name           = "FeedbackTable"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "feedback_id"

  attribute {
    name = "feedback_id"
    type = "S"
  }

  tags = {
    Name = "Feedback Table"
    Env  = "Dev"
  }
}
# --------------------------------------------------
# IAM role that the Lambda function will assume
# --------------------------------------------------
resource "aws_iam_role" "lambda_exec_role" {
  name               = "lambda-feedback-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags = {
    Name = "Lambda Execution Role"
    Env  = "Dev"
  }
}

# Trust policy: allow Lambda service to assume the role
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Inline policy: allow read/write to DynamoDB table and write logs
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-dynamodb-logs"
  role = aws_iam_role.lambda_exec_role.id

  policy = data.aws_iam_policy_document.lambda_access.json
}

data "aws_iam_policy_document" "lambda_access" {
  statement {
    sid    = "DynamoDBAccess"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [aws_dynamodb_table.feedback_table.arn]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}
resource "aws_lambda_function" "feedback_handler" {
  function_name = "FeedbackHandler"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  filename         = "${path.module}/../lambda/feedback.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/feedback.zip")

  tags = {
    Name = "Feedback Lambda"
    Env  = "Dev"
  }
}
resource "aws_apigatewayv2_api" "feedback_api" {
  name          = "FeedbackHTTPAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.feedback_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.feedback_handler.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.feedback_api.id
  route_key = "POST /feedback"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.feedback_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.feedback_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.feedback_api.execution_arn}/*/*"
}
