// POC Application Library - reusable components for all environments
local k = import 'k.libsonnet';

{
  // Configuration object to be extended per environment
  config:: {
    namespace: 'poc-cfg-base',
    environment: 'base',
    publicUrl: 'https://base.example.local',
    image: 'nginx:1.25-alpine',
    replicas: 1,
    storageClass: 'gp2',
    storageSize: '1Gi',
    postgresResources: {
      requests: { memory: '256Mi', cpu: '100m' },
      limits: { memory: '512Mi', cpu: '500m' },
    },
    enableBackup: false,
  },

  // Namespace resource
  namespace:: k.core.v1.namespace.new($.config.namespace),

  // ConfigMap for demo app
  configMap:: k.core.v1.configMap.new('poc-demo-app-config', {
    PUBLIC_URL: $.config.publicUrl,
    DB_HOST: 'poc-postgres-postgresql',
    DB_PORT: '5432',
    DB_NAME: 'pocdb',
    DB_USER: 'pocapp',
    ENVIRONMENT: $.config.environment,
  }) + k.core.v1.configMap.metadata.withNamespace($.config.namespace),

  // ExternalSecret for database credentials (ESO/AWS Secrets Manager)
  externalSecret:: {
    apiVersion: 'external-secrets.io/v1',
    kind: 'ExternalSecret',
    metadata: {
      name: 'poc-db-credentials',
      namespace: $.config.namespace,
    },
    spec: {
      refreshInterval: '1h',
      secretStoreRef: {
        name: 'knowledge-base-secrets',
        kind: 'ClusterSecretStore',
      },
      target: {
        name: 'poc-db-credentials',
        creationPolicy: 'Owner',
      },
      data: [
        {
          secretKey: 'password',
          remoteRef: {
            key: 'poc-config-mgmt/db-credentials',
            property: 'password',
          },
        },
        {
          secretKey: 'postgres-password',
          remoteRef: {
            key: 'poc-config-mgmt/db-credentials',
            property: 'postgres-password',
          },
        },
      ],
    },
  },

  // Demo app Deployment
  deployment:: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: 'poc-demo-app',
      namespace: $.config.namespace,
      labels: {
        app: 'poc-demo-app',
        environment: $.config.environment,
      },
    },
    spec: {
      replicas: $.config.replicas,
      selector: {
        matchLabels: { app: 'poc-demo-app' },
      },
      template: {
        metadata: {
          labels: {
            app: 'poc-demo-app',
            environment: $.config.environment,
          },
        },
        spec: {
          containers: [{
            name: 'demo-app',
            image: $.config.image,
            ports: [{ containerPort: 80 }],
            envFrom: [{ configMapRef: { name: 'poc-demo-app-config' } }],
            env: [{
              name: 'DB_PASSWORD',
              valueFrom: {
                secretKeyRef: {
                  name: 'poc-db-credentials',
                  key: 'password',
                },
              },
            }],
            resources: {
              requests: { memory: '64Mi', cpu: '50m' },
              limits: { memory: '128Mi', cpu: '100m' },
            },
            livenessProbe: {
              httpGet: { path: '/', port: 80 },
              initialDelaySeconds: 5,
              periodSeconds: 10,
            },
            readinessProbe: {
              httpGet: { path: '/', port: 80 },
              initialDelaySeconds: 5,
              periodSeconds: 5,
            },
          }],
        },
      },
    },
  },

  // Service
  service:: k.core.v1.service.new('poc-demo-app', { app: 'poc-demo-app' }, [{ port: 80, targetPort: 80, name: 'http' }])
    + k.core.v1.service.metadata.withNamespace($.config.namespace),

  // PostgreSQL StatefulSet (simplified - in real scenario use Helm chart output)
  postgres:: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: {
      name: 'poc-postgres-postgresql',
      namespace: $.config.namespace,
      labels: { app: 'postgresql' },
    },
    spec: {
      serviceName: 'poc-postgres-postgresql',
      replicas: 1,
      selector: { matchLabels: { app: 'postgresql' } },
      template: {
        metadata: { labels: { app: 'postgresql' } },
        spec: {
          containers: [{
            name: 'postgresql',
            image: 'bitnami/postgresql:16',
            ports: [{ containerPort: 5432 }],
            env: [
              { name: 'POSTGRESQL_DATABASE', value: 'pocdb' },
              { name: 'POSTGRESQL_USERNAME', value: 'pocapp' },
              { name: 'POSTGRESQL_PASSWORD', valueFrom: { secretKeyRef: { name: 'poc-db-credentials', key: 'password' } } },
              { name: 'POSTGRESQL_POSTGRES_PASSWORD', valueFrom: { secretKeyRef: { name: 'poc-db-credentials', key: 'postgres-password' } } },
            ],
            resources: $.config.postgresResources,
            volumeMounts: [{ name: 'data', mountPath: '/bitnami/postgresql' }],
          }],
        },
      },
      volumeClaimTemplates: [{
        metadata: { name: 'data' },
        spec: {
          accessModes: ['ReadWriteOnce'],
          storageClassName: $.config.storageClass,
          resources: { requests: { storage: $.config.storageSize } },
        },
      }],
    },
  },

  // PostgreSQL Service
  postgresService:: k.core.v1.service.new('poc-postgres-postgresql', { app: 'postgresql' }, [{ port: 5432, targetPort: 5432 }])
    + k.core.v1.service.metadata.withNamespace($.config.namespace),

  // Backup CronJob (conditional based on enableBackup)
  backupCronJob:: if $.config.enableBackup then {
    apiVersion: 'batch/v1',
    kind: 'CronJob',
    metadata: {
      name: 'poc-postgres-backup',
      namespace: $.config.namespace,
    },
    spec: {
      schedule: '0 2 * * *',
      concurrencyPolicy: 'Forbid',
      successfulJobsHistoryLimit: 3,
      failedJobsHistoryLimit: 1,
      jobTemplate: {
        spec: {
          template: {
            spec: {
              restartPolicy: 'OnFailure',
              containers: [{
                name: 'backup',
                image: 'bitnami/postgresql:16',
                command: ['/bin/bash', '-c', 'echo "Backup at $(date)" && PGPASSWORD=$DB_PASSWORD pg_dump -h poc-postgres-postgresql -U pocapp -d pocdb > /tmp/backup.sql && echo "Done"'],
                env: [{
                  name: 'DB_PASSWORD',
                  valueFrom: {
                    secretKeyRef: {
                      name: 'poc-db-credentials',
                      key: 'password',
                    },
                  },
                }],
              }],
            },
          },
        },
      },
    },
  } else null,

  // All resources combined
  all:: std.prune([
    $.namespace,
    $.configMap,
    $.externalSecret,
    $.deployment,
    $.service,
    $.postgres,
    $.postgresService,
    $.backupCronJob,
  ]),
}
