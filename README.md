# MQTTex

This a MQTT server and client written in Elixir. 

[![Build Status](https://travis-ci.org/alfert/mqttex.png)](https://travis-ci.org/alfert/mqttex)

## Design

### Connections

One process per logical client connection (i.e. operating on Elixir data structures). On 
the physical connection we have an additional process, which does the network handling
and the encoding/decoding of MQTT messages. The connection state holds the list of subscription
strings, i.e. with wildcards. It also holds the client process to which published messages are send. 

### Subscriptions of topics

Subscriptions of topics are managed by a registration service and Topic Server for each topic. 
The topic server holds a list of subscribed clients and the witheld messages. The registration service
provides functions to find all known topics for a subscription string and for subscribing and 
unsubscribing, i.e. interacting with the topic servers. The subscriptions can be stored in an 
DETS/ETS to survive potential crashes of the topic servers. 

The task of a topic server is receive messages to be published and send them to the subscribed
connections. It also handles the QoQ workflow with each client connection. 

### Supervising

The supervised processes for connections and for topics are dynamically by nature. For both 
a separate supervisor exists. 

## The MQTT state machine

### Server Side 

The several states are shown here the statechart: 

![FSM of the Server Side](../mqtt-server-fsm.dot.png)

### Client Side

## ToDos

### Specific todos
* verify connections
* document client side approach

### Generic todos
* add more unit tests
* add statemachine tests with Proper

