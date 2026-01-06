// Production Environment Configuration
local pocApp = import 'poc-app.libsonnet';

pocApp {
  config+:: {
    namespace: 'poc-cfg-prod',
    environment: 'production',
    publicUrl: 'https://prod.example.local',
    image: 'nginx:1.24-alpine',  // Stable version for prod
    replicas: 2,  // Higher replicas for prod
    storageClass: 'gp2',
    storageSize: '5Gi',  // Larger storage for prod
    postgresResources: {
      requests: { memory: '512Mi', cpu: '250m' },
      limits: { memory: '1Gi', cpu: '1' },
    },
    enableBackup: true,  // Backups enabled in prod
  },
}.all
