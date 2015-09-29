FROM gliderlabs/alpine

MAINTAINER Roi Rav-Hon <roi@logz.io>

# Installs bash and python
RUN apk --update add bash python

# Adds request python module
ADD packages/requests-2.5.1 /requests

# Installs requests
RUN cd /requests && python /requests/setup.py install
