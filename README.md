# Test
https://directus-test.aws.remipetit.fr

# Prod
https://directus-app.aws.remipetit.fr

aws secretsmanager get-secret-value --secret-id myapp/test/directus --region eu-west-3 --query "SecretString" --output text 2>&1 | python3 -m json.tool