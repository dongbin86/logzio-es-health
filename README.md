## Logz.io Elasticsearch Health Monitor

[Docker hub repository](https://hub.docker.com/r/logzio/logzio-es-health/)

This container runs and monitors your elasticsearch cluster.
It ships its logs automatically to Logz.io via SSL so everything is encrypted.
The container also provides a Nagios plugin script that uses local caches from the regular monitoring routine, so you won't overload your ES cluster with unnecessary queries.

The containers monitors these values:
- Number of initializing shards
- Number of pending tasks
- Description of pending tasks (name, time in queue, urgency, etc..)
- Number of relocating shards
- Number of unassigned shards
- Cluster status (red, yellow, green)
- Mapping size - entire cluster (python length of the cluster state)
- Mapping size - per index (python length of a specific index from cluster state)
- Cluster state version
- JVM heap per node
- Threadpools queue and rejected per node
- Number of docs between readings (to calculate index rate)

***
## Usage (docker run)
#### Mandatory
**LOGZ_TOKEN** - Your [Logz.io App](https://app.logz.io) token, where you can find under "settings" in the web app.
**ELASTICSEARCH_ADDR** - Your elasticsearch cluster to monitor, without protocol and port. Currently supporting only HTTP, and monitoring via the RESTful endpoint at :9200

#### Optional
**INTERVAL_SECONDS** - Number of seconds to sleep between each /_cluster/health and /_cluster/pending_tasks call. Default: 30  
**CLUSTERSTATE_SECONDS** - Number of seconds to sleep between each /_cluster/state call. Default: 3600 (For large clusters this is a heavy query, so be gentle with reducing this interval)  
**LISTENER** - Logz.io Listener address. Default: "https://listener.logz.io:8071"  
**ES_PROTOCOL** - Elasticsearch http protocol. Default: "http"  
**ES_PORT** - Elasticsearch http port. Default: "9200"  
**ES_USER** - Basic auth user  
**ES_PORT** - Basic auth password  

### Example
```bash
docker run -d \
  -e LOGZ_TOKEN="MYSUPERAWESOMELOGZIOTOKEN" \
  -e ELASTICSEARCH_ADDR="elasticsearch.example.com" \
  --restart=always \
  logzio/logzio-es-health
```

***

## Usage (nagios monitor)
Nagios monitoring implements Nagios native plugin interface.
Which means by exit codes:
```bash
exit 0 # Everything is awesome
exit 1 # Warning!
exit 2 # Critical!!
exit 3 # Unknown
```
It will also print a message that both humans and Nagios loves. Expect something like:
```
WARNING: Cluster status is yellow! | status: yellow
```
The data before the pipeline is for your notifications, and the data after the pipeline is for you to use in nagios performance data.

#### Available monitoring components and usage
```bash
docker exec CONTAINER /root/nagios.sh COMPONENT -c CRITICAL -w WARNING
```

Where COMPONENT is in:
```
initializing_shards             (e.g initializing_shards -w 5 -c 10)
number_of_pending_tasks         (e.g number_of_pending_tasks -w 50 -c 100)
relocating_shards               (e.g relocating_shards -c 10 -w 5)
unassigned_shards               (e.g unassigned_shards -w 1 -c 2)
status                          (e.g -c yellow / -c red -w yellow)
mapping_size                    (e.g -c 4000000 -w 3000000 (this one is tricky, tune it carefully))
```
***
## Screenshots of dashboard from Logz.io
#### Dashboard containing data from this docker and from our [perfagent docker](https://hub.docker.com/r/logzio/logzio-perfagent/)
![alt text](http://s14.postimg.org/6zjqk9j6p/es_health_dashboard_censored.jpg "Logz.io Dashboard")
#### Scroll..
![alt text](http://s13.postimg.org/a3ja8zsqv/es_health_dashboard2_censored.jpg "Logz.io Dashboard 2")
***
## About Logz.io
[Logz.io](https://logz.io) combines open source log analytics and behavioural learning intelligence to pinpoint what’s actually important

