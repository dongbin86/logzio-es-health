#!/bin/bash

TAG=logzio/logzio-es-health

docker build -t $TAG ./

echo "----------------------------------------"
echo "Built: $TAG"
echo "----------------------------------------"
