#!/bin/bash

function check_db() {
  psql -h ${DB_HOST} -U ${SORMAS_POSTGRES_USER} ${DB_NAME} --no-align --tuples-only --quiet --command="SELECT count(*) FROM pg_database WHERE datname='${DB_NAME}';" 2>/dev/null || echo "0"
}

SLEEP=30
COUNT=0
while [ $(check_db) -ne 1 ];do
  echo "Waiting for ${DB_NAME} DB to get ready ..." 
  sleep ${SLEEP}
  COUNT=$(( ${COUNT} + 1 ))
  if [ ${COUNT} -gt 9 ];then
    echo "DB ${DB_NAME} is not reachable after ${COUNT} attempts. Exiting!"
    exit 1
  fi
done

ROOT_PREFIX=
# make sure to update payara-sormas script when changing the user name
USER_NAME=payara

PAYARA_HOME=${ROOT_PREFIX}/opt/payara5
DOMAINS_HOME=${ROOT_PREFIX}/opt/domains
TEMP_DIR=${ROOT_PREFIX}/opt/${DOMAIN_NAME}/temp
GENERATED_DIR=${ROOT_PREFIX}/opt/${DOMAIN_NAME}/generated
CUSTOM_DIR=${ROOT_PREFIX}/opt/${DOMAIN_NAME}/custom

DEPLOY_PATH=/tmp/${DOMAIN_NAME}
DOWNLOADS_PATH=/var/www/${DOMAIN_NAME}/downloads

PORT_BASE=6000
PORT_ADMIN=6048
DOMAIN_DIR=${DOMAINS_HOME}/${DOMAIN_NAME}
LOG_FILE_PATH=${DOMAIN_DIR}/logs
LOG_FILE_NAME=configure_`date +"%Y-%m-%d_%H-%M-%S"`.log

ASADMIN="${PAYARA_HOME}/bin/asadmin --port ${PORT_ADMIN}"

${PAYARA_HOME}/bin/asadmin start-domain --domaindir ${DOMAINS_HOME} ${DOMAIN_NAME}

echo "Configuring domain and database connection..."

# JVM settings
${ASADMIN} delete-jvm-options -Xmx4096m
${ASADMIN} create-jvm-options -Xmx${JVM_MAX}

# JDBC pool
${ASADMIN} delete-jdbc-resource jdbc/${DOMAIN_NAME}DataPool
${ASADMIN} delete-jdbc-connection-pool ${DOMAIN_NAME}DataPool
${ASADMIN} create-jdbc-connection-pool --restype javax.sql.ConnectionPoolDataSource --datasourceclassname org.postgresql.ds.PGConnectionPoolDataSource --isconnectvalidatereq true --validationmethod custom-validation --validationclassname org.glassfish.api.jdbc.validation.PostgresConnectionValidation --property "portNumber=5432:databaseName=${DB_NAME}:serverName=${DB_HOST}:user=${SORMAS_POSTGRES_USER}:password=${SORMAS_POSTGRES_PASSWORD}" ${DOMAIN_NAME}DataPool
${ASADMIN} create-jdbc-resource --connectionpoolid ${DOMAIN_NAME}DataPool jdbc/${DOMAIN_NAME}DataPool

# Pool for audit log
${ASADMIN} delete-jdbc-resource jdbc/AuditlogPool
${ASADMIN} delete-jdbc-connection-pool ${DOMAIN_NAME}AuditlogPool
${ASADMIN} create-jdbc-connection-pool --restype javax.sql.XADataSource --datasourceclassname org.postgresql.xa.PGXADataSource --isconnectvalidatereq true --validationmethod custom-validation --validationclassname org.glassfish.api.jdbc.validation.PostgresConnectionValidation --property "portNumber=5432:databaseName=${DB_NAME_AUDIT}:serverName=${DB_HOST}:user=${SORMAS_POSTGRES_USER}:password=${SORMAS_POSTGRES_PASSWORD}" ${DOMAIN_NAME}AuditlogPool
${ASADMIN} create-jdbc-resource --connectionpoolid ${DOMAIN_NAME}AuditlogPool jdbc/AuditlogPool

${ASADMIN} delete-javamail-resource mail/MailSession
${ASADMIN} create-javamail-resource --mailhost ${MAIL_HOST} --mailuser "sormas" --fromaddress ${MAIL_FROM} mail/MailSession

# set FQDN for sormas domain
${ASADMIN} set configs.config.server-config.http-service.virtual-server.server.hosts=${SORMAS_SERVER_URL}

${PAYARA_HOME}/bin/asadmin stop-domain --domaindir ${DOMAINS_HOME}
chown -R ${USER_NAME}:${USER_NAME} ${DOMAIN_DIR}

# put deployments into place
for APP in $(ls ${DOMAIN_DIR}/deployments/*.{war,ear} 2>/dev/null);do
  mv ${APP} ${DOMAIN_DIR}/autodeploy
done

echo "Server setup completed."

${PAYARA_HOME}/bin/asadmin start-domain --domaindir ${DOMAINS_HOME} ${DOMAIN_NAME}
tail -f $LOG_FILE_PATH/server.log
