#!/bin/bash

TAG=logzio/logzio-es-health-base

docker build -t $TAG ./

echo "----------------------------------------"
echo "Built: $TAG"
echo "----------------------------------------"

