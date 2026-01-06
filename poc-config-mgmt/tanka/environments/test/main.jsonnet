// Test Environment Configuration
local pocApp = import 'poc-app.libsonnet';

pocApp {
  config+:: {
    namespace: 'poc-cfg-test',
    environment: 'test',
    publicUrl: 'https://test.example.local',
    image: 'nginx:1.25-alpine',
    replicas: 1,
    storageClass: 'gp2',
    storageSize: '1Gi',
    postgresResources: {
      requests: { memory: '256Mi', cpu: '100m' },
      limits: { memory: '512Mi', cpu: '500m' },
    },
    enableBackup: false,  // No backups in test
  },
}.all
