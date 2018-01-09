FROM python:2.7-alpine
WORKDIR /usr/src/app

RUN apk --update add bash

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

ADD scripts/go.py ./go.py
ADD scripts/nagios.sh /root/nagios.sh

RUN chmod a+x ./go.py
RUN chmod a+x /root/nagios.sh

CMD [ "python", "./go.py" ]
