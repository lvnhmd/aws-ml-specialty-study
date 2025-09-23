#!/usr/bin/env bash
# Switch AWS CLI to use the "course" profile

PROFILE="course"
REGION="eu-west-2"

export AWS_PROFILE="$PROFILE"
export AWS_DEFAULT_REGION="$REGION"

echo "✅ Switched AWS CLI to profile: $AWS_PROFILE (region: $AWS_DEFAULT_REGION)"
echo

echo "🔍 Current configuration:"
aws configure list

echo
echo "🔑 Caller identity:"
aws sts get-caller-identity


