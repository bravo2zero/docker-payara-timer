FROM openjdk:8

# install dependencies & tools
RUN apt-get update && apt-get install -y vim unzip

# config env
RUN echo 'alias ll="ls -lh"' >> ~/.bashrc

# install mariadb
ENV MARIADB_PASSWORD password
RUN echo "mysql-server mysql-server/root_password password ${MARIADB_PASSWORD}" >> /root/debconf.txt
RUN echo "mysql-server mysql-server/root_password_again password ${MARIADB_PASSWORD}" >> /root/debconf.txt
RUN debconf-set-selections /root/debconf.txt
RUN apt-get install -y mariadb-server
RUN sed -i 's/user.*mysql/user = root/g' /etc/mysql/my.cnf
RUN sed -e '/bind-address/s/^/#/g' -i /etc/mysql/my.cnf
RUN /bin/bash -c "/usr/bin/mysqld_safe &" && \
	sleep 5 && \
	mysql -u root -p$MARIADB_PASSWORD mysql -e "CREATE USER 'root'@'%' IDENTIFIED BY '${MARIADB_PASSWORD}';" && \
	mysql -u root -p$MARIADB_PASSWORD mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;" && \
	mysql -u root -p$MARIADB_PASSWORD mysql -e "SET character_set_server = 'utf8';"


# install payara
ENV PAYARA_PKG https://s3-eu-west-1.amazonaws.com/payara.fish/Payara+Downloads/Payara+4.1.1.171.0.1/payara-4.1.1.171.0.1.zip
ENV PAYARA_VERSION 171
ENV PKG_FILE_NAME payara-full-$PAYARA_VERSION.zip
ENV PAYARA_PATH /opt/payara41
ENV ADMIN_USER admin
ENV ADMIN_PASSWORD admin

RUN wget --quiet -O /opt/$PKG_FILE_NAME $PAYARA_PKG
RUN unzip -qq /opt/$PKG_FILE_NAME -d /opt
RUN rm /opt/$PKG_FILE_NAME
RUN mkdir -p $PAYARA_PATH/deployments

# download mariadb connector and move it to payara dir (have to push it to domain/lib later)
RUN wget --quiet -O $PAYARA_PATH/mariadb-java-client.jar https://downloads.mariadb.com/Connectors/java/connector-java-1.5.9/mariadb-java-client-1.5.9.jar 
# https://downloads.mariadb.com/Connectors/java/connector-java-1.5.9/mariadb-java-client-1.5.9.jar
# https://downloads.mariadb.com/Connectors/java/connector-java-2.0.1/mariadb-java-client-2.0.1.jar

# create test cluster configuration
WORKDIR $PAYARA_PATH
RUN /bin/bash -c "/usr/bin/mysqld_safe &" && \	
	bin/asadmin create-domain --nopassword=true test && \
	bin/asadmin start-domain test && \
	bin/asadmin create-node-ssh --nodehost localhost node1 && \
	bin/asadmin copy-config default-config cluster-config && \
	bin/asadmin create-cluster --config cluster-config test-cluster && \
	bin/asadmin create-instance --cluster test-cluster --node node1 inst1 && \
	bin/asadmin create-instance --cluster test-cluster --node node1 inst2 && \
	mv mariadb-java-client.jar glassfish/domains/test/lib/

# switch to mariadb datasource for timer and enable hazelcast
RUN /bin/bash -c "/usr/bin/mysqld_safe &" && \
	sleep 5 && \
	mysql -u root -p$MARIADB_PASSWORD mysql -e "CREATE DATABASE payara41 CHARACTER SET = 'utf8';" && \
	bin/asadmin start-domain test && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.property.databaseName= && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.datasource-classname=org.mariadb.jdbc.MariaDbDataSource && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.property.ServerName=localhost && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.property.DatabaseName=payara41 && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.property.Encoding=UTF-8 && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.property.Port=3306 && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.property.User=root && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.property.Password=password && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.validation-classname=org.glassfish.api.jdbc.validation.MySQLConnectionValidation && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.connection-validation-method=custom-validation && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.is-connection-validation-required=true && \
	bin/asadmin set resources.jdbc-connection-pool.__TimerPool.connection-creation-retry-attempts=6 && \
	bin/asadmin set configs.config.server-config.ejb-container.ejb-timer-service.timer-datasource=jdbc/__TimerPool && \
	bin/asadmin set configs.config.default-config.ejb-container.ejb-timer-service.timer-datasource=jdbc/__TimerPool && \
	bin/asadmin create-resource-ref --target test-cluster --enabled=true jdbc/__TimerPool && \
	bin/asadmin set-hazelcast-configuration --enabled=true --target=cluster-config && \
	bin/asadmin set configs.config.cluster-config.availability-service.web-container-availability.persistence-type=hazelcast && \
	bin/asadmin set configs.config.cluster-config.availability-service.ejb-container-availability.sfsb-ha-persistence-type=hazelcast

# set credentials to admin/admin 

RUN echo 'AS_ADMIN_PASSWORD=\n\
AS_ADMIN_NEWPASSWORD='$ADMIN_PASSWORD'\n\
EOF\n'\
>> /opt/tmpfile
RUN echo 'AS_ADMIN_PASSWORD='$ADMIN_PASSWORD'\n\
EOF\n'\
>> /opt/pwdfile
RUN \
 $PAYARA_PATH/bin/asadmin start-domain test && \
 $PAYARA_PATH/bin/asadmin --user $ADMIN_USER --passwordfile=/opt/tmpfile change-admin-password && \
 $PAYARA_PATH/bin/asadmin --user $ADMIN_USER --passwordfile=/opt/pwdfile enable-secure-admin && \
 rm /opt/tmpfile


EXPOSE 3306 4848 8009 8080 8181


# copy deployment artifact
COPY test.payara.timer.ear/target/test.payara.timer.ear-1.0.0-SNAPSHOT.ear /opt/payara41/deployments/

# deploy / undeploy with
# bin/asadmin deploy --target test-cluster --name test.payara.timer deployments/test.payara.timer.ear-1.0.0-SNAPSHOT.ear
# bin/asadmin undeploy --target test-cluster test.payara.timer
# tail instance logs for timer execution
# tail -f /opt/payara41/glassfish/nodes/node1/inst?/logs/server.log

ENTRYPOINT /bin/bash -c "/usr/bin/mysqld_safe &" && /opt/payara41/bin/asadmin start-domain test && /opt/payara41/bin/asadmin login && /opt/payara41/bin/asadmin start-cluster test-cluster && /bin/bash


