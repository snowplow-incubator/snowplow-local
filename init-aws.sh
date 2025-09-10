#!/bin/bash

# create the required Kinesis streams to support the collector + enrich
awslocal kinesis create-stream --stream-name collector-good --region ap-southeast-2 --shard-count 1 # collector good
awslocal kinesis create-stream --stream-name collector-bad --region ap-southeast-2 --shard-count 1 # collector bad

# enrichment
awslocal kinesis create-stream --stream-name enriched-good --region ap-southeast-2 --shard-count 1 # enriched good
awslocal kinesis create-stream --stream-name enriched-bad --region ap-southeast-2 --shard-count 1 # enriched bad
awslocal kinesis create-stream --stream-name enriched-incomplete --region ap-southeast-2 --shard-count 1 # enriched incomplete
awslocal kinesis create-stream --stream-name pii --region ap-southeast-2 --shard-count 1 # optional PII stream

# loaders
awslocal kinesis create-stream --stream-name snowflake-loader-bad --region ap-southeast-2 --shard-count 1
awslocal kinesis create-stream --stream-name bigquery-bad --region ap-southeast-2 --shard-count 1
awslocal kinesis create-stream --stream-name snowflake-loader-bad-incomplete --region ap-southeast-2 --shard-count 1
awslocal kinesis create-stream --stream-name databricks-loader-bad --region ap-southeast-2 --shard-count 1

# lake loader bucket
awslocal s3api create-bucket --bucket snowplow-lake-loader --region ap-southeast-2 --create-bucket-configuration LocationConstraint=ap-southeast-2

# snowbridge streams
awslocal kinesis create-stream --stream-name snowbridge-output --region ap-southeast-2 --shard-count 1
awslocal kinesis create-stream --stream-name snowbridge-failed --region ap-southeast-2 --shard-count 1
# snowbridge dynamo tables
awslocal dynamodb create-table --table-name snowbridge_clients --region ap-southeast-2 --key-schema AttributeName=ID,KeyType=HASH --attribute-definitions AttributeName=ID,AttributeType=S --billing-mode PAY_PER_REQUEST
awslocal dynamodb create-table --table-name snowbridge_checkpoints --region ap-southeast-2 --key-schema AttributeName=Shard,KeyType=HASH --attribute-definitions AttributeName=Shard,AttributeType=S --billing-mode PAY_PER_REQUEST
awslocal dynamodb create-table --table-name snowbridge_metadata --region ap-southeast-2 --key-schema AttributeName=Key,KeyType=HASH --attribute-definitions AttributeName=Key,AttributeType=S --billing-mode PAY_PER_REQUEST

# enrichment assets bucket
awslocal s3api create-bucket --bucket enrich-assets --region ap-southeast-2 --create-bucket-configuration LocationConstraint=ap-southeast-2
awslocal s3 cp --recursive /enrich-assets s3://enrich-assets/