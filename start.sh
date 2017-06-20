#!/bin/bash

docker run -ti -p 8080:8080 -p 4848:4848 -p 3306:3306 payara/timer
