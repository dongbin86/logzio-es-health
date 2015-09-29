FROM logzio/logzio-es-health-base # Currently not in dockerhub, so build it locally

MAINTAINER Roi Rav-Hon <roi@logz.io>

ADD scripts/go.py /root/go.py
ADD scripts/nagios.sh /root/nagios.sh

RUN chmod a+x /root/go.py
RUN chmod a+x /root/nagios.sh

WORKDIR /root

CMD ["/root/go.py"]
