#!/usr/bin/python

#
# Main docker script. Loops and query elasticsearch apis, and sends the info to Logz.io throught HTTPS.
# Its also cache the results locally so that nagios monitor can happen quickly on the docker.
#
# Written by Roi Rav-Hon @ Logz.io
#
# Params:
#   Mandatory:
#       LOGZ_TOKEN - Token from your logz.io settings page
#       ELASTICSEARCH_ADDR - Your cluster dns/address. We need to query it somehow, dont we? (currently support only http on port 9200)
#
#   Optional:
#       INTERVAL_SECONDS - What is the sample interval for cluster health and pending tasks.
#                           Note that it doesnt include the running time of the script.
#
#       CLUSTERSTATE_SECONDS - Sample interval of cluster state. This should be much higher since it is a "heavy" api call.
#                               Note again that it doesnt include the script running time.
#
#       LISTENER - Logz.io listener address. Basicly should not be used outsize of logz.io
#
#       ES_PROTOCOL - Elasticsearch protocol for connection (http/https)
#
#       ES_PORT - The port Elasticsearch is listening to
#
#       ES_USER - In case of using basic auth to Elasticsearch, this is the user section
#
#       ES_PASS - And this is the password
#
# All of the parameters should be supplemented to docker as environment variables.. e.g (docker run ... -e INTERVAL_SECONDS=4 ..)
#

import json
import os
import re
import requests
import sys
import time
from threading import Thread, Condition
from logzio import sender

# Gets optional variables
es_protocol = os.getenv('ES_PROTOCOL', 'http')
es_port = os.getenv('ES_PORT', 9200)
es_user = os.getenv('ES_USER', None)
es_pass = os.getenv('ES_PASS', None)
listener = os.getenv('LISTENER')
interval = os.getenv('INTERVAL_SECONDS', 30)
state_interval = os.getenv('CLUSTERSTATE_SECONDS', 3600)

# Get mandatory variables
logzio_token = os.getenv('LOGZ_TOKEN')
elasticsearch_addr = os.getenv('ELASTICSEARCH_ADDR')

ELASTICSEARCH_TYPE = "elasticsearch-health"
CLUSTERSTATE_CACHE_FILE = '/clusterstate.txt'
CLUSTERHEALTH_CACHE_FILE = '/clusterhealth.txt'

protocol = None

# Check if both mandatory are set
if not all([logzio_token, elasticsearch_addr]):
    print ("#############################################################################################")
    print ("You must supply both your Logz.io token, and your your ElasticSearch ip/hostname")
    print ("docker run .... -e LOGZ_TOKEN=<Your Token> -e ELASTICSEARCH_ADDR=<Elasticsearch Address> ....")
    print ("#############################################################################################")

    sys.exit(1)

if listener is None:
    logzioSender = sender.LogzioSender(token=logzio_token)
else:
    logzioSender = sender.LogzioSender(token=logzio_token, url=listener)


def query_elasticsearch(path):
    if es_user is None:
        return requests.get("{}://{}:{}/{}".format(es_protocol, elasticsearch_addr, str(es_port), path)).json()
    else:
        return requests.get("{}://{}:{}/{}".format(es_protocol, elasticsearch_addr, str(es_port), path), auth=(es_user, es_pass)).json()


def query_cluster_state():
    # Set up a conditional thread lock
    lock = Condition()

    # Acquire it
    lock.acquire()

    # Constant monitor
    while True:
        # Get the clusterstate. can take a minute
        state = query_elasticsearch("_cluster/state")

        # Get the cluster mapping size
        cluster_state_size = len(json.dumps(state["metadata"]["indices"]))

        # Creates a json of version and size
        return_json = {
            "type": "elasticsearch-health",
            "clusterstate_version": state["version"],
            "clusterstate_mapping_size": cluster_state_size,
            "cluster_name": cluster_name
        }

        with open(CLUSTERSTATE_CACHE_FILE, 'w') as state_file:

            state_file.write("MAPPING_SIZE:{0}".format(cluster_state_size))

        logzioSender.append(return_json)

        # Now we want to figure out which index has which mapping size
        for index in state["metadata"]["indices"]:

            # Prefix placeholder (for non logz- indices)
            account_prefix = index

            # Check if its logzio internal index (not relevant for open source, but used internaly in logz.io.. sorry for that)
            if re.match("^logz-*", index):
                # Cut the prefix
                account_prefix = "-".join(index.split("-")[:-1])

            # Creates a temp json
            return_json = {
                "type": ELASTICSEARCH_TYPE,
                "clusterstate_index_name": index,
                "clusterstate_index_prefix": account_prefix,
                "clusterstate_index_size": len(json.dumps(state["metadata"]["indices"][index]["mappings"])),
                "cluster_name": cluster_name
            }

            logzioSender.append(return_json)

        # Delete the state json
        del state

        # Sleep for cluster state interval (using a conditional lock here because time.sleep causes deadlocks in some cases for some reason)
        lock.wait(state_interval)


# Query the cluster root once, to get the cluster name
cluster_root = query_elasticsearch("")
cluster_name = cluster_root["cluster_name"]
last_docCount = None

# Start a different thread to query cluster state
thread = Thread(target=query_cluster_state)
thread.start()

# Looping until the end of times. or the containers at least.
while True:

    # Get the cluster health
    health_json = query_elasticsearch("_cluster/health")

    # Append the type
    health_json["type"] = ELASTICSEARCH_TYPE

    # And the cluster name
    health_json["cluster_name"] = cluster_name

    # Query the doc count
    cluster_stats_json = query_elasticsearch("_cluster/stats")

    # Only fire the document if its not our first reading, so we will have delta
    if last_docCount:
        # Add the delta
        health_json["docs_since_last_read"] = int(cluster_stats_json["indices"]["docs"]["count"] - last_docCount)

    # Update the latest reading
    last_docCount = cluster_stats_json["indices"]["docs"]["count"]

    logzioSender.append(health_json)

    # Open cache
    with open(CLUSTERHEALTH_CACHE_FILE, 'w') as health_file:

        # Write cache
        health_file.write("INITIALIZING_SHARDS:{0}\n".format(health_json["initializing_shards"]))
        health_file.write("NUMBER_OF_PENDING_TASKS:{0}\n".format(health_json["number_of_pending_tasks"]))
        health_file.write("RELOCATING_SHARDS:{0}\n".format(health_json["relocating_shards"]))
        health_file.write("UNASSIGNED_SHARDS:{0}\n".format(health_json["unassigned_shards"]))
        health_file.write("STATUS:{0}\n".format(health_json["status"]))

    # Get the pending tasks
    tasks_json = query_elasticsearch("_cluster/pending_tasks")

    # Iterate over them
    for task in tasks_json['tasks']:
        # Append the type
        task["type"] = ELASTICSEARCH_TYPE

        # And the cluster name
        task["cluster_name"] = cluster_name

        logzioSender.append(task)

    # Getting nodes
    nodes_json = query_elasticsearch("_nodes/stats")

    # Iterate over the nodes
    for currNode in nodes_json["nodes"]:

        # Json placeholder
        nodes_holder = {
            "type": ELASTICSEARCH_TYPE,
            "cluster_name": cluster_name,
            "node_name": nodes_json["nodes"][currNode]["name"],
            "heap_used_percent": nodes_json["nodes"][currNode]["jvm"]["mem"]["heap_used_percent"]
        }

        # Add thread pools
        for curr_thread_pool in nodes_json["nodes"][currNode]["thread_pool"]:
            nodes_holder["{0}-queue".format(curr_thread_pool)] = \
                nodes_json["nodes"][currNode]["thread_pool"][curr_thread_pool]["queue"]
            nodes_holder["{0}-rejected".format(curr_thread_pool)] = \
                nodes_json["nodes"][currNode]["thread_pool"][curr_thread_pool]["rejected"]

        logzioSender.append(nodes_holder)

    # Remove all jsons
    del health_json
    del cluster_stats_json
    del tasks_json
    del nodes_json

    # Sleeps for interval!
    time.sleep(interval)
