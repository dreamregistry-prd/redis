#!/bin/bash

PARAMETER=$(aws ssm describe-parameters --filters "Key=Name,Values=${parameterKey}"  --output text --no-cli-pager)
if [ -z "$PARAMETER" ]; then
  echo "Parameter ${parameterKey} does not exist. Nothing to do."
  exit 0
fi

aws ssm delete-parameter \
  --name ${parameterKey} \
  --no-cli-pager
