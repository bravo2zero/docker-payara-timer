# docker-payara-timer
Docker based Timer Service test case for Payara/MariaDB/Hazelcast cluster setup

# Pre-requisites:
* JDK 1.8
* Maven
* Docker

# Usage

* Build test artifact
```bash
mvn clean install
```
* Build docker image using script provided
```bash
./build.sh
```
* Start docker container using provided script
```bash
./start.sh
```
* Use default admin username: `admin` and password: `admin` when prompted
* Deploy/undeploy test artifact with:
```bash
bin/asadmin deploy --target test-cluster --name test.payara.timer deployments/test.payara.timer.ear-1.0.0-SNAPSHOT.ear
bin/asadmin undeploy --target test-cluster test.payara.timer
```

Note: can also tail instance log files with: `tail -f /opt/payara41/glassfish/nodes/node1/inst?/logs/server.log`


