#!/bin/bash

# Variables
REPOSITORY_URL=$1
REGION=$2
TAG="latest"
DIRECTORY="website"

if git diff --name-only HEAD~1 HEAD -- ${DIRECTORY} | grep -q .; then
    echo "Changes detected in ${DIRECTORY}"

    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REPOSITORY_URL

    # Build the Docker image
    docker build -t ${REPOSITORY_URL}:${TAG} .

    # Push the Docker image to the repository
    docker push ${REPOSITORY_URL}:${TAG}
else
    echo "No changes detected in ${DIRECTORY}"
fi
