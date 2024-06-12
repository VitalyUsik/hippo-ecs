#!/bin/bash

# Variables
REPOSITORY_URL=$1
REGION=$2
TAG="latest"
DIRECTORY="../website"

# Calculate the hash of the website directory
CURRENT_HASH=$(tar -cf - ${DIRECTORY} | sha256sum | cut -d ' ' -f 1)
# Retrieve the previous hash
if [ -f .docker_build_hash ]; then
    PREVIOUS_HASH=$(cat .docker_build_hash)
else
    PREVIOUS_HASH=""
fi

# Compare the hashes
if [ "$CURRENT_HASH" != "$PREVIOUS_HASH" ]; then
    # Authenticate Docker to ECR
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REPOSITORY_URL

    # Build the Docker image
    docker build -t ${REPOSITORY_URL}:${TAG} .

    # Push the Docker image to the repository
    docker push ${REPOSITORY_URL}:${TAG}

    # Update the hash file
    echo $CURRENT_HASH > .docker_build_hash
else
    echo "No changes detected in the ${DIRECTORY} directory. Skipping Docker build and push."
fi
