using './main.bicep'

param workload = 'novaretail'
param env = 'dev'

// Leave empty for a fully private lake.
// To upload test files from your laptop while learning, set your public IP (e.g. '203.0.113.25'),
// redeploy, and remove it again when done.
param clientIp = ''
