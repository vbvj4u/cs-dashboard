output "phpmyadmin_url" {
  value = "http://${aws_instance.ecs.public_ip}:8080"
}

output "metabase_url" {
  value = "http://${aws_instance.ecs.public_ip}:3000"
}

output "rds_endpoint" {
  description = "Use as Host when adding the database in Metabase"
  value       = aws_db_instance.mysql.address
}

output "db_password_ssm_parameter" {
  description = "SSM parameter name holding the generated RDS master password. Retrieve with: aws ssm get-parameter --name <this> --with-decryption --query Parameter.Value --output text"
  value       = aws_ssm_parameter.db_password.name
}
