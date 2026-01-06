// Test7 Environment - demonstrating minimal new env creation
// Just import test and override what's different
local test = import '../test/main.jsonnet';
local pocApp = import 'poc-app.libsonnet';

pocApp {
  config+:: {
    namespace: 'poc-cfg-test7',
    environment: 'test7',
    publicUrl: 'https://test7.example.local',
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
}.all
