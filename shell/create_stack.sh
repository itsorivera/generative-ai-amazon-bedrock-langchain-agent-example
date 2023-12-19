# chmod u+x create-stack.sh
# source ./create-stack.sh

export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export S3_ARTIFACT_BUCKET_NAME=$STACK_NAME-$ACCOUNT_ID
export DATA_LOADER_S3_KEY="agent/lambda/data-loader/loader_deployment_package.zip"
export LAMBDA_HANDLER_S3_KEY="agent/lambda/agent-handler/agent_deployment_package.zip"
export LEX_BOT_S3_KEY="agent/bot/lex.zip"

aws s3 mb s3://${S3_ARTIFACT_BUCKET_NAME} --region us-east-1
aws s3 cp ../agent/ s3://${S3_ARTIFACT_BUCKET_NAME}/agent/ --recursive --exclude ".DS_Store"

export BEDROCK_LANGCHAIN_LAYER_ARN=$(aws lambda publish-layer-version \
    --layer-name bedrock-langchain-pdfrw \
    --description "Bedrock LangChain pdfrw layer" \
    --license-info "MIT" \
    --content S3Bucket=${S3_ARTIFACT_BUCKET_NAME},S3Key=agent/lambda-layers/bedrock-langchain-pdfrw.zip \
    --compatible-runtimes python3.11 \
    --query LayerVersionArn --output text)

export GITHUB_TOKEN_SECRET_NAME=$(aws secretsmanager create-secret --name $STACK_NAME-git-pat \
--secret-string $GITHUB_PAT --query Name --output text)

aws cloudformation create-stack \
--stack-name ${STACK_NAME} \
--template-url https://s3.us-east-1.amazonaws.com/cf-templates-1idqdojpyngtz-us-east-1/2023-12-19T170242.853Zl35-AWS_CloudFormation_Bedrock_Assistant.yaml \
--parameters \
ParameterKey=S3ArtifactBucket,ParameterValue=${S3_ARTIFACT_BUCKET_NAME} \
ParameterKey=DataLoaderS3Key,ParameterValue=${DATA_LOADER_S3_KEY} \
ParameterKey=LambdaHandlerS3Key,ParameterValue=${LAMBDA_HANDLER_S3_KEY} \
ParameterKey=LexBotS3Key,ParameterValue=${LEX_BOT_S3_KEY} \
ParameterKey=GitHubTokenSecretName,ParameterValue=${GITHUB_TOKEN_SECRET_NAME} \
ParameterKey=BedrockLangChainPyPDFLayerArn,ParameterValue=${BEDROCK_LANGCHAIN_LAYER_ARN} \
ParameterKey=AmplifyRepository,ParameterValue=${AMPLIFY_REPOSITORY} \
--capabilities CAPABILITY_NAMED_IAM

aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].StackStatus"
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME

export LEX_BOT_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`LexBotID`].OutputValue' --output text)

export LAMBDA_ARN=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaARN`].OutputValue' --output text)

aws lexv2-models update-bot-alias --bot-alias-id 'TSTALIASID' --bot-alias-name 'TestBotAlias' --bot-id $LEX_BOT_ID --bot-version 'DRAFT' --bot-alias-locale-settings "{\"en_US\":{\"enabled\":true,\"codeHookSpecification\":{\"lambdaCodeHook\":{\"codeHookInterfaceVersion\":\"1.0\",\"lambdaARN\":\"${LAMBDA_ARN}\"}}}}"

aws lexv2-models build-bot-locale --bot-id $LEX_BOT_ID --bot-version "DRAFT" --locale-id "en_US"
