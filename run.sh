#!/bin/bash
container="sark/cloudix"

echo
read -p "Pull latest $container image? (y/n)" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    sudo docker pull "$container"
fi

echo "Running $container"
sudo docker run --rm -i -t "$container":latest /bin/bash
