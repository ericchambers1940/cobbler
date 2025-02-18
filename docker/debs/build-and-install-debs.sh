#!/bin/bash
# Utility script to build DEBs in a Docker container and then install them

set -euo pipefail

if [ "$1" == "--with-tests" ]
then
    RUN_TESTS=true
    shift
else
    RUN_TESTS=false
fi

TAG=$1
DOCKERFILE=$2

IMAGE=cobbler:$TAG

# Build container
echo "==> Build container ..."
docker build -t "$IMAGE" -f "$DOCKERFILE" .

# Build DEBs
echo "==> Build packages ..."
mkdir -p deb-build tmp
docker run -ti -v "$PWD/deb-build:/usr/src/cobbler/deb-build" -v "$PWD/tmp:/var/tmp" "$IMAGE"

# Launch container and install cobbler
echo "==> Start container ..."
docker run -t -d --name cobbler -v "$PWD/deb-build:/usr/src/cobbler/deb-build" "$IMAGE" /bin/bash

echo "==> Install fresh packages ..."
docker exec -it cobbler bash -c 'dpkg -i deb-build/DEBS/all/cobbler*.deb'

echo "==> Restart Apache and Cobbler daemon ..."
docker exec -it cobbler bash -c 'a2enconf cobbler'

echo "==> Start Supervisor"
docker exec -it cobbler bash -c 'supervisord -c /etc/supervisord.conf'

echo "==> Wait 5 sec. and show Cobbler version ..."
docker exec -it cobbler bash -c 'sleep 5 && cobbler --version'

if $RUN_TESTS
then
    # Almost all of these requirement are already satisfied in the Dockerfiles!
    # Also on Debian mod_wsgi is installed as "libapache2-mod-wsgi-py3"
    echo "==> Running tests ..."
    docker exec -it cobbler bash -c 'pip3 install coverage distro future setuptools sphinx requests future'
    docker exec -it cobbler bash -c 'pip3 install pyyaml netaddr Cheetah3 pymongo distro ldap3 librepo'
    docker exec -it cobbler bash -c 'pip3 install dnspython pyflakes pycodestyle pytest pytest-cov codecov'
    docker exec -it cobbler bash -c 'pytest-3'
fi

# Clean up
echo "==> Stop Cobbler container ..."
docker stop cobbler
echo "==> Delete Cobbler container ..."
docker rm cobbler
rm -rf ./tmp
