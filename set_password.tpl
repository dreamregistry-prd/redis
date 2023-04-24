#!/bin/bash

PASSWORD=$(aws secretsmanager get-random-password --exclude-characters '#$"()*+,./:;=?@[\]_`{|}~'"'" --query "RandomPassword" --output text --no-cli-pager)
aws elasticache modify-user \
  --user-id ${userId} \
  --access-string "on ~* +@all" \
  --passwords "$PASSWORD" \
  --no-cli-pager

STATUS=$(aws elasticache describe-users --user-id ${userId} --query "Users[0].Status" --output text --no-cli-pager)
until [ "$STATUS" == "active" ]; do
  STATUS=$(aws elasticache describe-users --user-id ${userId} --query "Users[0].Status" --output text --no-cli-pager)
  sleep 10
done

aws ssm put-parameter \
  --name ${parameterKey} \
  --value "$PASSWORD" \
  --type SecureString \
  --no-cli-pager
